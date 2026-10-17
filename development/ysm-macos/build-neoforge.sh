#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$root/evidence" "$root/dist"
exec > >(tee "$root/evidence/neoforge-build.log") 2>&1
preserve_test_results() {
    if [[ -d "$root/neoforge/build/test-results" ]]; then
        mkdir -p "$root/evidence/neoforge-tests"
        cp -R "$root/neoforge/build/test-results/." "$root/evidence/neoforge-tests/" \
            || echo 'Could not preserve the Gradle test reports'
    fi
}
trap preserve_test_results EXIT
git clone --no-checkout https://github.com/YesSteveModel/YesSteveModel.git "$root/neoforge"
git -C "$root/neoforge" checkout --detach 74c53b58b2f9b680a6c6dc5d5d41e7422fc000bb
git -C "$root/neoforge" apply --check "$root/patches/neoforge.patch"
git -C "$root/neoforge" apply "$root/patches/neoforge.patch"
python3 "$root/resolve-neoforge-dependencies.py"
mkdir -p "$root/neoforge/src/main/resources/META-INF/native"
mac_native="$root/dist/libysm.dylib"
test -f "$mac_native"
cp "$mac_native" "$root/neoforge/src/main/resources/META-INF/native/libysm.dylib"
windows_native="${YSM_WINDOWS_NATIVE_PATH:-}"
if [[ -n "$windows_native" ]]; then
    test -f "$windows_native"
    python3 - "$windows_native" <<'PY'
from pathlib import Path
import sys

data = Path(sys.argv[1]).read_bytes()
if len(data) < 0x40 or data[:2] != b'MZ':
    raise SystemExit('Windows native library is not a PE image')
offset = int.from_bytes(data[0x3c:0x40], 'little')
if offset + 26 > len(data) or data[offset:offset + 4] != b'PE\0\0':
    raise SystemExit('Windows native library has an invalid PE header')
machine = int.from_bytes(data[offset + 4:offset + 6], 'little')
optional_magic = int.from_bytes(data[offset + 24:offset + 26], 'little')
if machine != 0x8664 or optional_magic != 0x20b:
    raise SystemExit('Windows native library must target x64 PE32+')
PY
    cp "$windows_native" "$root/neoforge/src/main/resources/META-INF/native/ysm.dll"
    cp "$windows_native" "$root/dist/ysm.dll"
fi
export YSM_NATIVE_PATH="$mac_native"
cd "$root/neoforge"
bash ./gradlew --no-daemon --max-workers=2 '-Dorg.gradle.jvmargs=-Xmx1800m' test portableTest check shadowJar
jar_file="$(find build/libs -maxdepth 1 -type f -name '*all.jar' -print -quit)"
test -n "$jar_file"
cp "$jar_file" "$root/dist/"
python3 - "$root/dist/$(basename "$jar_file")" "$windows_native" <<'PY'
from pathlib import Path
import hashlib
import sys
import zipfile

jar = Path(sys.argv[1])
windows_native = sys.argv[2]
with zipfile.ZipFile(jar) as archive:
    names = set(archive.namelist())
    mac_name = 'META-INF/native/libysm.dylib'
    windows_name = 'META-INF/native/ysm.dll'
    if mac_name not in names or not archive.read(mac_name):
        raise SystemExit('Packaged JAR is missing the macOS ARM64 native library')
    if windows_native:
        if windows_name not in names:
            raise SystemExit('Packaged JAR is missing the Windows x64 native library')
        expected = hashlib.sha256(Path(windows_native).read_bytes()).hexdigest()
        actual = hashlib.sha256(archive.read(windows_name)).hexdigest()
        if actual != expected:
            raise SystemExit('Packaged Windows native library digest does not match its build artifact')
PY
native_outputs=("$root/dist/"*.jar "$root/dist/libysm.dylib")
if [[ -f "$root/dist/ysm.dll" ]]; then
    native_outputs+=("$root/dist/ysm.dll")
fi
shasum -a 256 "${native_outputs[@]}" > "$root/evidence/neoforge-SHA256SUMS"
