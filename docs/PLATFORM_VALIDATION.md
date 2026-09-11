# KAIZOKU — PLATFORM READINESS & ENVIRONMENT VALIDATION

> **Validation Standard:** Technical verification based on direct inspection of source code, build scripts, native manifests, and host environment dependencies.
> 
> **Status Levels:**
> - `CODE EXISTS`: Native platform directory and configuration files are present in the repository.
> - `BUILDABLE`: All necessary toolchains, SDKs, and dependencies are verified to compile the target artifact.
> - `RUNNABLE`: Compiled binary can be launched in an emulator or physical environment.
> - `FUNCTIONALLY VERIFIED`: Complete manual or automated behavioral verification has passed on the platform.

---

## 1. PLATFORM STATUS BREAKDOWN

| Platform | Code Exists | Buildable Locally? | Runnable Locally? | Verification Status | Primary Dependencies & SDKs |
|---|:---:|:---:|:---:|:---:|---|
| **Android (Phone/Tablet)** | **YES** | Requires Flutter SDK | Requires Device / AVD | `CODE EXISTS` | Android SDK 34, JDK 17, NDK 26, Gradle 8.4 |
| **Android TV (Leanback)** | **YES** | Requires Flutter SDK | Requires TV AVD | `CODE EXISTS` | Android SDK 34, JDK 17, Leanback API 34 |
| **Windows Desktop (Win32)** | **YES** | Requires Flutter SDK | **YES (Portable Exists)**| `RUNNABLE` (Historical) | MSVC v143, CMake 3.13+, Windows 10/11 SDK |
| **Linux Desktop (GTK)** | **YES** | Requires Linux Host | Requires Linux Host | `CODE EXISTS` | GTK+ 3.0, CMake 3.13+, pkg-config, Clang/GCC |
| **macOS Desktop (Cocoa)** | **YES** | Requires macOS Host | Requires macOS Host | `CODE EXISTS` | Xcode 15+, CocoaPods, macOS 11+ SDK |
| **iOS (Phone/Tablet)** | **YES** | Requires macOS Host | Requires macOS Host | `CODE EXISTS` | Xcode 15+, CocoaPods, iOS 14+ SDK |

---

## 2. DETAILED PLATFORM ANALYSIS

### 2.1 Android (Mobile & Tablet)
* **Status:** `CODE EXISTS` (Locally). Buildable in CI (`.github/workflows/ci.yml`).
* **SDK & Native Requirements:**
  - Android compileSdk 34, minSdk 24, targetSdk 34.
  - Java JDK 17 (installed on host in `C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot\bin` and `D:\tools\jdk-17`).
  - Android SDK (installed on host in `D:\tools\android-sdk`).
  - NDK (specified by Flutter SDK version).
* **Native Dependencies:**
  - `androidx.media3:media3-exoplayer:1.9.2` (DASH, HLS, OkHttp data sources).
  - `com.github.recloudstream.cloudstream:library:v4.7.0` (CloudStream provider runtime).
  - `org.nanohttpd:nanohttpd:2.3.1` (Local Wi-Fi extension bridge).
  - `com.github.recloudstream:torrentserver:7861970` (Embedded Go TorrServer, ~48MB multi-ABI).
  - `app.cash.quickjs:quickjs-android:0.9.2` (QuickJS engine for Aniyomi extractors).
* **Known Limitations & Build Gates:**
  - `isMinifyEnabled = false` is strictly required in `android/app/build.gradle.kts`. Enabling R8 minification strips runtime reflection symbols required by DexClassLoader extension APKs.
* **Verification Scope:**
  - Verified from code: Manifest permissions, foreground service, intent filters, MethodChannels.
  - Requires physical hardware testing: Biometric sensor authentication, background foreground download transfer resilience when device sleeps.

### 2.2 Android TV (Leanback)
* **Status:** `CODE EXISTS`.
* **Platform Specifics:**
  - Single unified APK shared with mobile phones.
  - Declares `android.software.leanback` (required=false), `android.hardware.touchscreen` (required=false).
  - Features dedicated 10-foot remote focus engine (`tv_focusable.dart`) and TV remote shortcuts (`TvShortcuts`).
* **Verification Scope:**
  - Requires physical Android TV or Android TV emulator to test D-pad traversal and remote hardware buttons.

### 2.3 Windows Desktop
* **Status:** `RUNNABLE` (Historical binary verified in `D:\623a6ae8-a6f9-464a-a61e-b49f67cd9b65-Sozo-Windows-portable-2-`).
* **SDK & Native Requirements:**
  - Visual Studio C++ build tools (MSVC), CMake 3.13+.
  - `media_kit_libs_windows_video: ^1.0.11` (Bundles dynamic `mpv-2.dll` and dependencies).
  - `window_manager: ^0.4.3` (Win32 window style manipulation).
* **Known Limitations:**
  - Anime4K GLSL shaders require a Direct3D 11 / OpenGL compatible GPU.
  - CloudStream / Aniyomi extension APKs cannot execute natively on Windows (requires connecting to an Android device running the local NanoHTTPD bridge).

### 2.4 Linux Desktop
* **Status:** `CODE EXISTS`.
* **SDK & Native Requirements:**
  - GTK+ 3.0 development headers, CMake, `media_kit_libs_linux: ^1.2.1`.
* **Limitations:**
  - Requires Linux build host; cannot be compiled directly on Windows without cross-compilation toolchains or Docker containers.

### 2.5 macOS & iOS
* **Status:** `CODE EXISTS`.
* **SDK & Native Requirements:**
  - Apple macOS host with Xcode 15+, CocoaPods, Apple Developer signing certificates.
* **Limitations:**
  - Cannot be compiled on Windows host. Compiled exclusively through macOS CI runners or dedicated Apple development machines.
