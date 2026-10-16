#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
exec > >(tee "$root/evidence/java-build.log") 2>&1
git clone --no-checkout --filter=blob:none https://github.com/YesSteveModel/YesSteveModel.git "$root/java"
git -C "$root/java" checkout --detach 74c53b58b2f9b680a6c6dc5d5d41e7422fc000bb
git -C "$root/java" apply --check "$root/patches/java.patch"
git -C "$root/java" apply "$root/patches/java.patch"
mkdir -p "$root/java/src/main/resources/META-INF/native"
cp "$root/dist/libysm.dylib" "$root/java/src/main/resources/META-INF/native/"
export YSM_NATIVE_PATH="$root/dist/libysm.dylib"
cd "$root/java"
chmod u+x gradlew
./gradlew --no-daemon --max-workers=2 test shadowJar
cp build/libs/*.jar "$root/dist/"
cp -R build/test-results "$root/evidence/java-test-results"
