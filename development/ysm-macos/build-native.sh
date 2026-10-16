#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$root/evidence" "$root/dist"
exec > >(tee "$root/evidence/native-build.log") 2>&1
test "$(uname -m)" = arm64
export MACOSX_DEPLOYMENT_TARGET=14.5
brew install llvm@22 lld@22 cmake ninja nasm
llvm_prefix="$(brew --prefix llvm@22)"
export PATH="$llvm_prefix/bin:$(brew --prefix lld@22)/bin:$PATH"
export CC="$llvm_prefix/bin/clang" CXX="$llvm_prefix/bin/clang++"
python3 -m venv "$root/build-venv"
source "$root/build-venv/bin/activate"
python -m pip install 'conan==2.29.1'
clang --version
cmake --version
git --version
xcodebuild -version
df -h .

# Supply a private static C++ runtime. Players must not need Homebrew or extra dylibs.
runtime_prefix="$root/static-runtime"
if [[ ! -f "$runtime_prefix/lib/libc++_static.a" ]]; then
    llvm_version="$(llvm-config --version)"
    git clone --depth 1 --filter=blob:none --sparse --branch "llvmorg-$llvm_version" \
        https://github.com/llvm/llvm-project.git "$root/llvm-runtime-source"
    git -C "$root/llvm-runtime-source" sparse-checkout set runtimes libcxx libcxxabi libunwind libc cmake llvm/cmake llvm/include
    cmake -G Ninja -S "$root/llvm-runtime-source/runtimes" -B "$root/runtime-build" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$runtime_prefix" \
        -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=14.5 -DCMAKE_OSX_ARCHITECTURES=arm64 \
        '-DLLVM_ENABLE_RUNTIMES=libcxx;libcxxabi;libunwind' \
        -DLIBCXX_ENABLE_SHARED=OFF -DLIBCXX_ENABLE_STATIC=ON -DLIBCXX_ABI_VERSION=2 \
        -DLIBCXXABI_ENABLE_SHARED=OFF -DLIBCXXABI_ENABLE_STATIC=ON \
        -DLIBUNWIND_ENABLE_SHARED=OFF -DLIBUNWIND_ENABLE_STATIC=ON \
        -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
        -DLIBCXX_STATICALLY_LINK_ABI_IN_STATIC_LIBRARY=ON \
        -DLIBCXXABI_STATICALLY_LINK_UNWINDER_IN_STATIC_LIBRARY=ON \
        -DLLVM_INCLUDE_TESTS=OFF -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
        -DLIBCXX_ENABLE_TESTS=OFF -DLIBCXXABI_ENABLE_TESTS=OFF -DLIBUNWIND_ENABLE_TESTS=OFF
    cmake --build "$root/runtime-build" --parallel 3
    cmake --install "$root/runtime-build"
    cp "$runtime_prefix/lib/libc++.a" "$runtime_prefix/lib/libc++_static.a"
fi

if [[ ! -d "$root/native/.git" ]]; then
    mkdir -p "$root/native"
    git -C "$root/native" init
    git -C "$root/native" remote add origin https://github.com/YesSteveModel/YesSteveModel-Native.git
    git -C "$root/native" fetch --depth 1 origin e9ac162492a97c7222f652c41624ca150f450354
    git -C "$root/native" checkout --detach e9ac162492a97c7222f652c41624ca150f450354
fi
if [[ -s "$root/patches/native.patch" ]]; then
    git -C "$root/native" apply --check "$root/patches/native.patch"
    git -C "$root/native" apply "$root/patches/native.patch"
fi
cd "$root/native"
export CONAN_HOME="$root/native/conan/cache"
cat >> conan/profile-override <<EOF
tools.build:jobs=3
tools.build:compiler_executables={"c":"$CC","cpp":"$CXX"}
tools.build:cxxflags=["-nostdinc++","-isystem","$runtime_prefix/include/c++/v1","-D_LIBCPP_ABI_VERSION=2","-D_LIBCPP_DISABLE_AVAILABILITY"]
tools.build:sharedlinkflags=["-nostdlib++","-L$runtime_prefix/lib","-lc++_static"]
tools.build:exelinkflags=["-nostdlib++","-L$runtime_prefix/lib","-lc++_static"]
tools.cmake.cmaketoolchain:extra_variables={"CMAKE_OSX_DEPLOYMENT_TARGET":"14.5","CMAKE_OSX_ARCHITECTURES":"arm64","CMAKE_LINKER_TYPE":"LLD","HAS_MACOS_STATIC_LIBCXX":True}
EOF
bash bootstrap.sh setup
bash bootstrap.sh build native
cmake --build build/native-release --target ysm-test --parallel 3
ctest --test-dir build/native-release --output-on-failure --timeout 90 \
    --output-junit "$root/evidence/native-tests.xml"
library="$root/native/build/native-release/modules/lib-jni/libysm.dylib"
test -f "$library"
cp "$library" "$root/dist/libysm.dylib"
codesign --force --sign - "$root/dist/libysm.dylib"
codesign --verify --strict --verbose=2 "$root/dist/libysm.dylib"
file "$root/dist/libysm.dylib" | tee "$root/evidence/architecture.txt"
otool -L "$root/dist/libysm.dylib" | tee "$root/evidence/linkage.txt"
if otool -L "$root/dist/libysm.dylib" | tail -n +2 | grep -Ev '^\s*(/usr/lib/|/System/Library/|$)'; then
    echo 'Unexpected external runtime dependency' >&2
    exit 1
fi
if otool -L "$root/dist/libysm.dylib" | grep -q 'libc++'; then
    echo 'Dynamic C++ runtime is forbidden by the distribution contract' >&2
    exit 1
fi
shasum -a 256 "$root/dist/libysm.dylib" > "$root/evidence/SHA256SUMS"
