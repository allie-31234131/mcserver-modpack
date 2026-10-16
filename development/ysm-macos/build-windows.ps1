$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
New-Item -ItemType Directory -Force -Path "$root/evidence", "$root/dist", "$root/toolchain" | Out-Null
Start-Transcript -Path "$root/evidence/windows-native-build.log"
try {
    $installer = "$root/toolchain/LLVM-22.1.8-win64.exe"
    Invoke-WebRequest -Uri 'https://github.com/llvm/llvm-project/releases/download/llvmorg-22.1.8/LLVM-22.1.8-win64.exe' -OutFile $installer
    if ((Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant() -ne '16e5709785fef73c854646241c4a92c5cd574318d1b33c63330dd7721903e55c') { throw 'LLVM installer hash mismatch' }
    & 7z x -y "-o$root/toolchain/llvm" $installer | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'LLVM extraction failed' }
    $llvm = "$root/toolchain/llvm/bin"
    $env:PATH = "$llvm;C:\Program Files\NASM;$env:PATH"
    if (-not (Get-Command nasm.exe -ErrorAction SilentlyContinue)) {
        choco install nasm --yes --no-progress
        if ($LASTEXITCODE -ne 0) { throw 'NASM install failed' }
    }
    python -m venv "$root/build-venv"
    & "$root/build-venv/Scripts/python.exe" -m pip install 'conan==2.29.1'
    if ($LASTEXITCODE -ne 0) { throw 'Conan install failed' }
    $env:PATH = "$root/build-venv/Scripts;$env:PATH"
    if (-not (Test-Path -LiteralPath "$root/native/.git")) {
        New-Item -ItemType Directory -Force -Path "$root/native" | Out-Null
        git -C "$root/native" init
        git -C "$root/native" remote add origin https://github.com/YesSteveModel/YesSteveModel-Native.git
        git -C "$root/native" fetch --depth 1 origin e9ac162492a97c7222f652c41624ca150f450354
        git -C "$root/native" checkout --detach e9ac162492a97c7222f652c41624ca150f450354
        if ($LASTEXITCODE -ne 0) { throw 'Native checkout failed' }
    }
    git -C "$root/native" apply --check "$root/patches/native.patch"
    if ($LASTEXITCODE -ne 0) { throw 'Native patch check failed' }
    git -C "$root/native" apply "$root/patches/native.patch"
    $env:CC = "$llvm/clang-cl.exe"
    $env:CXX = "$llvm/clang-cl.exe"
    $env:CONAN_HOME = "$root/native/conan/cache"
    $compiler = $env:CC.Replace('\','/')
    $archiver = "$llvm/llvm-lib.exe".Replace('\','/')
    @"
tools.build:jobs=3
tools.build:compiler_executables={"c":"$compiler","cpp":"$compiler"}
tools.cmake.cmaketoolchain:extra_variables={"CMAKE_C_COMPILER":"$compiler","CMAKE_CXX_COMPILER":"$compiler","CMAKE_AR":"$archiver","CMAKE_LINKER_TYPE":"LLD"}
"@ | Add-Content -LiteralPath "$root/native/conan/profile-override" -Encoding utf8
    Push-Location "$root/native"
    try {
        & .\bootstrap.cmd setup
        if ($LASTEXITCODE -ne 0) { throw 'Conan recipe indexing failed' }
        & .\bootstrap.cmd build native
        if ($LASTEXITCODE -ne 0) { throw 'Windows native build failed' }
        cmake --build build/native-release --target ysm-test --parallel 3
        if ($LASTEXITCODE -ne 0) { throw 'Native test build failed' }
        ctest --test-dir build/native-release --output-on-failure --timeout 90 --output-junit "$root/evidence/windows-native-tests.xml"
        if ($LASTEXITCODE -ne 0) { throw 'Native tests failed' }
        Copy-Item -LiteralPath 'build/native-release/modules/lib-jni/ysm.dll' -Destination "$root/dist/ysm.dll"
        & "$llvm/llvm-readobj.exe" --file-headers --coff-imports "$root/dist/ysm.dll" | Out-File "$root/evidence/windows-linkage.txt"
        Get-FileHash -LiteralPath "$root/dist/ysm.dll" -Algorithm SHA256 | Format-List | Out-File "$root/evidence/windows-SHA256.txt"
    } finally { Pop-Location }
} finally { Stop-Transcript }
