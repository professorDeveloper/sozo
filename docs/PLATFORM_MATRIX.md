# KAIZOKU — CROSS-PLATFORM SUPPORT MATRIX

> **Repository Evidence Base:** Validated against `android/`, `ios/`, `windows/`, `linux/`, `macos/`, native build scripts, CMakeLists, and plugin manifests.

---

## 1. COMPREHENSIVE PLATFORM MATRIX

| Feature Subsystem | Android Phone/Tablet | Android TV | iOS | Windows | Linux | macOS |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| **HLS / Progressive Streaming** | Native ExoPlayer | Native ExoPlayer | Native AVPlayer | libmpv (`media_kit`) | libmpv (`media_kit`) | libmpv (`media_kit`) |
| **Multi-Audio Track Selection** | libmpv (Opt-in) | libmpv (Opt-in) | System Default | libmpv (`media_kit`) | libmpv (`media_kit`) | libmpv (`media_kit`) |
| **DRM CENC Playback** | Media3 ExoPlayer | Media3 ExoPlayer | ❌ N/A | ❌ N/A | ❌ N/A | ❌ N/A |
| **Local HLS Proxy** | Localhost HTTP | Localhost HTTP | Localhost HTTP | Localhost HTTP | Localhost HTTP | Localhost HTTP |
| **Offline Video Downloads** | Foreground Service | ❌ Hidden (Mains) | Dio Chunked Stream | Dio Chunked Stream | Dio Chunked Stream | Dio Chunked Stream |
| **Manga / Comic Reader** | Touch & Continuous | D-pad Step Mode | Touch & Continuous | Mouse / Keys | Mouse / Keys | Mouse / Keys |
| **Light Novel Reader** | Touch Scroll | D-pad Scroll | Touch Scroll | Mouse Wheel | Mouse Wheel | Mouse Wheel |
| **CloudStream Providers (.cs3)** | Native DexLoader | Native DexLoader | ❌ Sandboxed | Via Wi-Fi Bridge | Via Wi-Fi Bridge | Via Wi-Fi Bridge |
| **Aniyomi Extensions (.apk)** | Native DexLoader | Native DexLoader | ❌ Sandboxed | Via Wi-Fi Bridge | Via Wi-Fi Bridge | Via Wi-Fi Bridge |
| **Mihon Manga Ext (.apk)** | Native DexLoader | Native DexLoader | ❌ Sandboxed | Via Wi-Fi Bridge | Via Wi-Fi Bridge | Via Wi-Fi Bridge |
| **Embedded Torrent Stream** | Go TorrServer | Go TorrServer | ❌ Sandboxed | ❌ Bridge/Web | ❌ Bridge/Web | ❌ Bridge/Web |
| **Torrent Indexer Search** | RSS + Regex XML | RSS + Regex XML | RSS + Regex XML | RSS + Regex XML | RSS + Regex XML | RSS + Regex XML |
| **Picture-in-Picture (PiP)** | Native Android PiP | ❌ (Leanback) | Native iOS PiP | ❌ Window Float | ❌ Window Float | ❌ Window Float |
| **10-Foot D-Pad Focus Engine** | ❌ (Touch) | `TvFocusable` Full | ❌ (Touch) | ❌ (Mouse/Key) | ❌ (Mouse/Key) | ❌ (Mouse/Key) |
| **TV Pairing & Remote Control** | Mobile Sender | TV Receiver | Mobile Sender | Desktop Client | Desktop Client | Desktop Client |
| **Google Cast Sender** | `dart_cast` mDNS | ❌ (Target device) | `dart_cast` Bonjour| ❌ (mDNS limited) | ❌ (mDNS limited) | ❌ (mDNS limited) |
| **Anime4K GLSL Shaders** | ❌ (Vulkan/GLES opt) | ❌ | ❌ | libmpv Shaders | libmpv Shaders | libmpv Shaders |
| **Discord Rich Presence** | WebSocket Gateway | ❌ | WebSocket Gateway | Local Named Pipe | Local Unix Socket | Local Unix Socket |
| **App Lock (Biometric/PIN)** | BiometricPrompt | PIN Only (No sensor)| LocalAuthentication| PIN Only | PIN Only | Touch ID / PIN |
| **Deep Links & Universal Links**| App Links + Scheme | App Links | Universal Links | CLI Arguments | CLI Arguments | Apple Events |
| **Push Notifications** | FCM + LocalNotifs | FCM Background | APNs / FCM | ❌ | ❌ | ❌ |
| **Frameless Window Management**| ❌ N/A | ❌ N/A | ❌ N/A | `window_manager` | `window_manager` | `window_manager` |

---

## 2. PLATFORM CONSTRAINTS & BEHAVIORAL SAFEGUARDS

### 2.1 Android TV (Leanback)
* **Launcher Manifest:** Must declare `android.software.leanback` with `android:required="false"` so the single APK installs cleanly on both phones and TVs.
* **Touchscreen Requirement:** `android.hardware.touchscreen` MUST remain `required="false"` or Google Play / Android TV installer will reject the APK.
* **Fingerprint Requirement:** `android.hardware.fingerprint` MUST remain `required="false"` as no TV has biometric fingerprint sensors.
* **TV Banner:** High-resolution Leanback banner asset (`tv_banner.png`, 320x180 px) must be provided in `@drawable/tv_banner`.

### 2.2 Desktop Platforms (Windows, Linux, macOS)
* **MediaKit Runtime Dependency:** Uses dynamic libmpv libraries (`media_kit_libs_windows_video`, `media_kit_libs_linux`, `media_kit_libs_macos_video`).
* **Window Controls:** Custom title bar renders minimize, maximize/restore, and close buttons, hiding automatically during fullscreen playback or comic reading.
* **Scrolling Device Matrix:** Flutter `MaterialScrollBehavior` explicitly configured to accept `mouse`, `trackpad`, `touch`, and `stylus` pointer devices to allow dragging horizontal rails and page carousels with a mouse.

### 2.3 iOS Platform
* **Bonjour Service Declaration:** Requires `_googlecast._tcp` in `NSBonjourServices` of `Info.plist` for Chromecast discovery over Wi-Fi.
* **App Transport Security:** `NSAllowsArbitraryLoads` enabled to stream from HTTP IPTV and anime CDN endpoints without TLS termination failures.
* **Dynamic TabBar:** Detects iOS 26+ native UITabBar material vs fallback custom frosted glass capsule.
