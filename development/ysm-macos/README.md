# MCServer YSM macOS development

This development work targets Apple Silicon macOS, with Minecraft 1.21.1 / NeoForge 21.1.256 as the eventual integration target. The current public Java baseline is YSM 3.0 development for Forge 1.20.1. An intermediate Forge artifact is not a NeoForge release and must never enter the production modpack.

The native baseline is YesSteveModel/YesSteveModel-Native `e9ac162492a97c7222f652c41624ca150f450354`. The Java baseline is YesSteveModel/YesSteveModel `74c53b58b2f9b680a6c6dc5d5d41e7422fc000bb`. Both use Apache-2.0; upstream license, attribution, NOTICE and third-party notices remain with their source/artifacts. The model repository has separate rights and is not included in this source build.

`build-native.sh` builds dependencies from the upstream Conan recipes, supplies a static LLVM C++ runtime, builds and tests the ARM64 JNI library, checks ad-hoc signing and rejects non-system dynamic dependencies. `build-java.sh` applies the Java patch and runs the upstream automated tests before packaging an intermediate Forge JAR. Build outputs are development artifacts only. Neither script connects to the MCServer operating server or publishes a modpack manifest/Release.

Acceptance requires native build/tests, Java/JNI tests, NeoForge 1.21.1 integration, existing model compatibility, server/client synchronization, safe opt-out, actual Mac rendering, Iris/DH compatibility and sustained gameplay. Existing YSM 2.6.5 and development 3.0 formats/protocols are not assumed compatible.

The mobile policy remains excluded. Server installation, restart and public modpack publication are deferred by the operator.

`patches/neoforge.patch` is a separate source port for the current MCServer host. `resolve-neoforge-dependencies.py` downloads hash-pinned compile-only APIs; none are automatically installed into the game. `build-neoforge.sh` requires the freshly built native library and Java 21, then runs the full Java/JNI suite, focused portable checks, builtin verification and JAR packaging. The development workflow builds/tests the Windows x64 native library, then builds/tests the Apple Silicon native library and packages the NeoForge JAR with both platform natives. Local compile and focused checks are intermediate observations; actual Mac game/host/render acceptance remains required. See `HANDOFF.md` for the current evidence and remaining checks. This work does not touch the operating server.
