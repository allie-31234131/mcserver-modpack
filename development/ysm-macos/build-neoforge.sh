#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$root/evidence" "$root/dist"
exec > >(tee "$root/evidence/neoforge-build.log") 2>&1
git clone --no-checkout https://github.com/YesSteveModel/YesSteveModel.git "$root/neoforge"
git -C "$root/neoforge" checkout --detach 74c53b58b2f9b680a6c6dc5d5d41e7422fc000bb
git -C "$root/neoforge" apply --check "$root/patches/neoforge.patch"
git -C "$root/neoforge" apply "$root/patches/neoforge.patch"
python3 "$root/resolve-neoforge-dependencies.py"
mkdir -p "$root/neoforge/src/main/resources/META-INF/native"
cp "$root/dist/libysm.dylib" "$root/neoforge/src/main/resources/META-INF/native/libysm.dylib"
export YSM_NATIVE_PATH="$root/dist/libysm.dylib"
cd "$root/neoforge"
bash ./gradlew --no-daemon --max-workers=2 '-Dorg.gradle.jvmargs=-Xmx1800m' test portableTest check shadowJar
mkdir -p "$root/evidence/neoforge-tests"
cp -R build/test-results/. "$root/evidence/neoforge-tests/"
cp build/libs/*all.jar "$root/dist/"
shasum -a 256 "$root/dist/"*.jar > "$root/evidence/neoforge-SHA256SUMS"
