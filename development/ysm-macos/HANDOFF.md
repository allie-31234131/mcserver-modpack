# YSM macOS / NeoForge development handoff

Checked: 2026-10-17 11:04 KST  
Status: development JAR built; not accepted for public or production use.

## Target

- Minecraft 1.21.1, NeoForge 21.1.256, Java 21.
- Desktop Windows x64 and Apple Silicon macOS ARM64.
- This is a YSM 3.0 community port. It is not interchangeable with the server's YSM 2.6.5 or an upstream Forge 1.20.1 build unless separately verified.
- Android/mobile distribution remains excluded. This work has not changed the live server, its modpack manifest, a public Release, or a Gist.

## Artifact inspected

- `neoforge/build/libs/ysm-mcserver-development-3.0-mcserver-dev-neoforge+mc1.21.1-all.jar`
- SHA-256: `bb823028cfff5ea0d86f87b2056e186a586ad0022a3d54e602371e3ca284b071`
- The JAR contains both platform natives: `META-INF/native/libysm.dylib` is Mach-O ARM64 (SHA-256 `4efd730842a8867b0dae37c3759231e3316b1d5bdbf20beadce54570010dfb96`); `META-INF/native/ysm.dll` is PE (SHA-256 `06bffdeb38c353c7312477f74388c24112ab405eb406833b6a9a42535f6a9abc`).
- The archive includes Apache-2.0 and bundled dependency notices/licenses, relocates Quickbuf, and has the Minecraft/NeoForge version constraints in `META-INF/neoforge.mods.toml`.

## Verification evidence

- PASS: Java and test source compilation; `portableTest`; `shadowJar`; `check -x test`; built-in model index verification (default proof 1, non-default models 26, total models 27).
- PASS: focused native runtime integration and audio regression suite (31 tests), including malformed Ogg content now failing through the content-error boundary rather than an uncaught decoder NPE.
- PARTIAL: full Windows-hosted `test` executed 600 test cases: 587 passed, 4 failed, 9 skipped. All four failures are security regression tests that require creating symbolic links; this Windows account lacks the required privilege. No test was disabled or weakened. The same checks must pass on the macOS CI runner before acceptance.
- PARTIAL: legacy model corpus: 901 of 906 source files imported; 3 Opus files are malformed and 2 models lack required player textures. These are rejected inputs, not accepted model fixtures.
- PASS: the current CI run rebuilt and tested both Windows x64 and Apple Silicon ARM64 native libraries. The NeoForge integration job then stopped before Java tests at `generateProto`: Gradle selected the NeoForge Maven mirror for `protoc-3.21.12-osx-aarch_64.exe`, but that mirror returns 404 while Maven Central serves it. Build configuration now routes `com.google.protobuf` exclusively to Maven Central; the updated source still needs a fresh CI run.
- NOT TESTED: opening Minecraft on a physical Apple Silicon Mac; Microsoft account/launcher flow; model selection and display in a real world; Iris/Distant Horizons; live server join/synchronization; sustained gameplay. Compilation and automated tests do not establish those outcomes.

## Required next checks

1. Let the development-branch workflow run both Windows x64 and Apple Silicon native jobs, the full Java/JNI suite, built-in model checks, and the final NeoForge JAR build. Resolve any genuine failure; do not weaken tests to get a green result.
2. Install this development artifact only in an isolated test instance on an Apple Silicon Mac and a Windows client, then validate model selection, rendering, animation, reconnect, cross-platform synchronization, and YSM-disabled behavior against a matching test server.
3. Exercise Iris and Distant Horizons and inspect game logs/crash reports. None of these have been certified by the current artifact inspection.
4. Keep the production server and public modpack unchanged until the operator explicitly schedules a separate acceptance and rollout.
