import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

// 1. Keystore ma'lumotlarini yuklash
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("app/key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.soplay.sozo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
        // Vendored Aniyomi OkHttpExtensions.parseAs uses context receivers.
        freeCompilerArgs += "-Xcontext-receivers"
    }

    buildFeatures {
        // AGP 8 stopped generating BuildConfig by default. `eu.kanade.tachiyomi.AppInfo`
        // — the compat shim modern Mihon extensions link against — reports the host
        // app's version through it, so it has to come back on.
        buildConfig = true
    }

    defaultConfig {
        applicationId = "com.soplay.sozo"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Undo Flutter's per-ABI versionCode offset.
    //
    // With --split-per-abi, FlutterPlugin.kt rewrites each output as
    // `abiVersionCode * 1000 + versionCode` (arm32=1, arm64=2, x86_64=4). So a
    // pubspec of `+14` shipped three APKs numbered 1014 / 2014 / 4014. That
    // exists for the Play Store, which rejects variants sharing a versionCode.
    //
    // We deliver over Telegram, not the Play Store, and the offset actively
    // breaks us: the backend update check stores ONE number and compares it to
    // whatever the installed APK reports. With per-ABI numbers, a v7a user
    // (1014) is forever "behind" an arm64 number (2014), so they are told to
    // update, install the same build again, and are told to update again.
    //
    // Forcing every output back to the pubspec value means the number a user
    // reports is exactly the number set in pubspec.yaml and typed into the
    // admin panel — identical across ABIs, and monotonic across releases.
    // Must use the same legacy API and type Flutter writes through
    // (ApkVariantOutput.versionCodeOverride) — the modern androidComponents
    // API does NOT win against it. Our callback registers after the Flutter
    // plugin's, so it runs last and its value is the one that ships.
    applicationVariants.all {
        outputs.all {
            @Suppress("DEPRECATION")
            (this as com.android.build.gradle.api.ApkVariantOutput).versionCodeOverride =
                flutter.versionCode
        }
    }

    // 2. Raqamli imzo sozlamalarini yaratish (faqat key.properties mavjud bo'lsa).
    // Debug build'da bu fayl bo'lmaydi — shuning uchun release imzosi shartli.
    if (keystorePropertiesFile.exists()) {
        signingConfigs {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // 3. Debug imzosini "release" imzosiga almashtirish (imzo mavjud bo'lsa).
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")

            // R8 (minify) DexClassLoader bilan yuklanadigan manga/aniyomi extension
            // .apk'larini buzadi — ular host simvollariga runtime'da bog'lanadi va
            // R8 ularni o'zgartirib qo'yadi (debugda R8 o'chiq → ishlaydi, releaseда
            // home bo'sh). Keep'lar to'liq bo'lsa-da, full-mode/optimizatsiya buni
            // hal qilmadi. Ishonchli ishlashi uchun release'da minify o'chirildi:
            // APK kattaroq, lekin AOT (tez) va barcha extension'lar yuklanadi.
            // Eslatma: aniq kerakli -keep topilgach, qayta yoqib hajmni kichraytirsa
            // bo'ladi (xato endi home'da ko'rsatiladi — MangaHost/MangaRuntime).
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
    // CloudStream's library pulls okhttp5 + jspecify etc., which collide on some
    // META-INF resources. Drop the duplicates so packaging succeeds.
    packaging {
        resources {
            excludes += setOf(
                "META-INF/versions/9/OSGI-INF/MANIFEST.MF",
                "META-INF/DEPENDENCIES",
                "META-INF/INDEX.LIST",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/LICENSE.md",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt",
                "META-INF/NOTICE.md",
                "META-INF/{AL2.0,LGPL2.1}",
            )
        }
    }
}

flutter {
    source = "../.."
}

// Versions that MUST track keiyoushi/extensions-source's gradle/libs.versions.toml.
//
// Extension APKs declare these `compileOnly` and expect the host to supply the
// runtime at DexClassLoader time. When the host's copy is older than the one an
// extension was compiled against, the extension's generated code calls methods
// that do not exist in our copy and dies with AbstractMethodError /
// NoSuchMethodError — which MangaHost catches and turns into an empty list, so
// the source just silently shows nothing.
//
// That is exactly what serialization 1.7.3 vs the extensions' 1.11.0 was doing:
// every JSON-based source (Comick, MangaDex, Bato …) failed while HTML-scraping
// ones kept working.
//
// Before bumping these, check the upstream file:
// https://github.com/keiyoushi/extensions-source/blob/main/gradle/libs.versions.toml
val extensionSerialization = "1.11.0"
val extensionCoroutines = "1.11.0"
val extensionJsoup = "1.22.2"

// media3, held level with what video_player_android already pulls in.
//
// Two ExoPlayers on one classpath is one ExoPlayer: Gradle resolves to the
// highest version either side asks for, so declaring a lower number here does
// not pin anything — it silently becomes video_player's version at both compile
// and run time. Verified by resolving debugRuntimeClasspath: 1.4.1 declared
// here came out as 1.9.2, which is what the plugin brings.
//
// So the number is written down to MATCH, not to override, and the reason to
// keep it written down is that this code compiles against these APIs directly.
// When a Flutter upgrade moves video_player's media3, this must move with it —
// otherwise the mismatch shows up as a NoSuchMethodError during playback and
// nothing at all at build time.
//
// Check with:
//   ./gradlew :app:dependencies --configuration debugRuntimeClasspath | grep media3
val media3 = "1.9.2"

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // ExoPlayer, driven directly, for the encrypted streams only.
    //
    // video_player_android already bundles an ExoPlayer, but its plugin API
    // exposes no way to attach a DrmSessionManager — the capability is in the
    // engine, not in the surface it offers. Rather than fork the plugin, DRM
    // playback drives media3 itself (see drm/DrmPlayerHost.kt) and renders into
    // a Flutter texture, so it is a drop-in third backend behind the app's
    // existing PlayerController and the player UI never learns it exists.
    //
    // dash because that is what CENC-encrypted channels ship as; hls because a
    // DRM mirror sometimes falls back to one and a missing extractor there
    // presents as an unplayable stream rather than a missing feature.
    implementation("androidx.media3:media3-exoplayer:$media3")
    implementation("androidx.media3:media3-exoplayer-dash:$media3")
    implementation("androidx.media3:media3-exoplayer-hls:$media3")
    implementation("androidx.media3:media3-datasource-okhttp:$media3")

    // CloudStream provider runtime (Android-only feature). The `library` module
    // carries MainAPI/APIHolder/`app` HTTP client/extractors/BasePlugin so .cs3
    // plugins load against it. Resolves on JitPack (POM/module/jar verified at
    // v4.7.0; Gradle picks the KMP android variant via .module). See
    // docs/CLOUDSTREAM_INTEGRATION.md + cloudstream/PluginHost.kt.
    implementation("com.github.recloudstream.cloudstream:library:v4.7.0")
    // CloudStream plugins/extractors use coroutines on the IO dispatcher.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:$extensionCoroutines")
    // compileOnly: lets our clean-room CloudflareKiller implement okhttp3.Interceptor.
    // okhttp itself is supplied at runtime by the CloudStream `library` above (it's
    // `implementation`-scoped there, so it isn't on our compile classpath). The
    // Interceptor/Response/Headers APIs used are stable across okhttp 4.x/5.x.
    compileOnly("com.squareup.okhttp3:okhttp:4.12.0")

    // Aniyomi extension runtime (Android-only). Extension APKs compile against the
    // stub `extensions-lib` as compileOnly, so the host app must supply the real
    // runtime + these libraries at DexClassLoader time. See docs/ANIYOMI_INTEGRATION.md.
    implementation("org.jetbrains.kotlin:kotlin-reflect:2.2.20")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:$extensionSerialization")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json-okio:$extensionSerialization")
    implementation("org.jsoup:jsoup:$extensionJsoup")
    implementation("io.reactivex:rxjava:1.3.8")
    implementation("androidx.preference:preference-ktx:1.2.1")
    // JS engine for Aniyomi extractors that deobfuscate links (QuickJS).
    implementation("app.cash.quickjs:quickjs-android:0.9.2")

    // Local HTTP bridge: lets a desktop soplay client reach the on-device
    // extension hosts when this app runs on a local emulator/device. The server
    // is started only in debug builds (BuildConfig.DEBUG gate in MainActivity).
    // See BridgeServer.kt + docs/DESKTOP_EXTENSIONS_PLAN.md.
    implementation("org.nanohttpd:nanohttpd:2.3.1")

    // Embedded torrent streaming server (Go, via gomobile). Same artifact
    // CloudStream ships; it descends from YouROK/TorrServer through
    // Diegopyl1209/torrentserver-aniyomi, with the `os.Exit` paths removed so a
    // busy port cannot take the whole app down.
    //
    // SIZE: this ships libgojni.so for all four ABIs, ~48 MB uncompressed. It is
    // by far the biggest single native payload in the app — see the size note in
    // .github/workflows/release.yml before changing how ABIs are split.
    implementation("com.github.recloudstream:torrentserver:7861970")
}