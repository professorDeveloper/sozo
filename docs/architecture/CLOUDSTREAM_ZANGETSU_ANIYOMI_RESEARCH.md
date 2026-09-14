# Cloudstream, Zangetsu va Aniyomi: ishlash arxitekturasi

Tekshiruv sanasi: 2026-09-14. Til: o‘zbekcha.

Bu hisobot repository → extension yuklash → katalog/qidiruv → detail/epizod → stream olish → player zanjirini o‘rganadi. Upstream kod bilan Sozo integratsiyasi alohida ko‘rsatilgan. Bu jonli providerlarning ishlash foizi yoki barcha funksiyalarning to‘liq QA auditi emas: ilovalar build qilinmadi, yangi playback testi bajarilmadi. Amaldagi kod eski README/rejalardan ustun dalil sifatida olindi.

Sozo mobile commit: `964784226d7d00c37359182295cce18be9c678c6`.
Sozo TV commit: `52b4b06ea9eb0e604c0f7591b04f05a9e46c4e96`.
Zangetsu tekshirilgan commit: `1e73e19567fa03cf9b8174ee690ab349614c3704`.
Cloudstream upstream commit: `9bca3be59f85668949c2e853ae126c619c87eec6`.
Aniyomi upstream commit: `4b5b90a3749b2c0504d4ffdd9416051d4730226c`.

## 1. Asosiy farq

| Tizim | Extension shakli | Ijro muhiti | Asosiy vazifa |
|---|---|---|---|
| Cloudstream | `.cs3`, manifest va Android DEX | Android classloader + Cloudstream API | Provider/extractor orqali katalog va stream olish |
| Aniyomi | `.apk`, Android metadata va DEX | Android classloader + Aniyomi source/network API | Anime katalogi, epizodlar va server/video variantlarini olish |
| Zangetsu | O‘z `.js` manbalari; Android’da qo‘shimcha `.cs3` va `.apk` | JS engine va alohida native adapterlar | Turli ekotizimlarni bitta Flutter interfeysida birlashtirish |

Zangetsu Cloudstream yoki Aniyomi kodini JavaScript’ga aylantirmaydi. Har bir ekotizimning o‘z runtime’i saqlanadi; natijalar umumiy provider va video modellariga moslanadi. Manbalar: [Zangetsu routing](https://github.com/Spyou/Zangetsu/blob/1e73e19567fa03cf9b8174ee690ab349614c3704/lib/core/repository/source_repository.dart), [BaseProvider](https://github.com/Spyou/Zangetsu/blob/1e73e19567fa03cf9b8174ee690ab349614c3704/lib/core/provider/base_provider.dart), [Cloudstream loader](https://github.com/recloudstream/cloudstream/blob/master/app/src/main/java/com/lagradost/cloudstream3/plugins/PluginManager.kt), [Aniyomi extension qo‘llanmasi](https://github.com/aniyomiorg/aniyomi-extensions/blob/master/CONTRIBUTING.md).

## 2. Cloudstream: repository’dan playergacha

Umumiy zanjir:

```text
repo.json → pluginLists → plugins.json → .cs3
  → manifest.json → pluginClassName → Plugin.load(context)
  → provider/extractor registratsiyasi
  → MainAPI: getMainPage / search / load / loadLinks
  → ExtractorLink + SubtitleFile → player
```

`load(url)` kontent tafsiloti va epizod ma’lumotini beradi. `loadLinks(data)` esa ijro qilinadigan havolalarni yechadi. Epizodning `data` qiymati oddiy URL bo‘lishi shart emas: u providerga tegishli opaque qiymat bo‘lishi mumkin, uni buzmasdan qaytarish kerak. Stream callback’larida URL bilan birga sifat, tur, referer/headerlar, subtitrlar va ayrim manbalarda alohida audio ham keladi. Sozo’dagi aniq moslash: [PluginHost.kt](../../android/app/src/main/kotlin/com/soplay/sozo/cloudstream/PluginHost.kt), xususan `loadJson` va `loadLinksJson`.

Sozo mobile’da:

1. `RepoManager` repo ro‘yxati va metadata’ni SharedPreferences’da saqlaydi. `.cs3` fayllari versiyali nom bilan cache qilinadi. Vaqtinchalik fayl orqali download tugagach final faylga o‘tkaziladi.
2. Startup’da metadata qayta registratsiya qilinadi; classloader birinchi foydalanishda ishga tushadi. Repo’ni to‘liq qo‘shish va bitta plugin o‘rnatish yo‘llari mavjud.
3. `PluginHost` `PathClassLoader` orqali manifestdagi klassni yaratadi; resource talab qiladigan pluginlar uchun ham yo‘l bor.
4. Flutter `soplay/cloudstream` MethodChannel orqali chaqiradi. Provider ID — `cs:<provider nomi>`.
5. HLS, DASH, HTTP va torrent/magnet turlari normalizatsiya qilinadi; streamlar sifat bo‘yicha saralanadi; har bir mirrorning headerlari saqlanadi.

Manbalar: [RepoManager.kt](../../android/app/src/main/kotlin/com/soplay/sozo/cloudstream/RepoManager.kt), [PluginHost.kt](../../android/app/src/main/kotlin/com/soplay/sozo/cloudstream/PluginHost.kt), [Dart channel](../../lib/core/cloudstream/cloudstream_channel.dart), [native dispatcher](../../android/app/src/main/kotlin/com/soplay/sozo/MainActivity.kt).

Mobile dependency hozir `library:v4.8.0`; TV’da `v4.7.0`. Cloudstream library barcha app klasslarini bermaydi: `com.lagradost.cloudstream3` ostidagi mahalliy stub/shim’lar binary bog‘liqliklarni to‘ldiradi. Klass yoki method borligi original ilovaning barcha xulqi takrorlanganini anglatmaydi. Manbalar: [mobile Gradle](../../android/app/build.gradle.kts), [TV Gradle](../../../sozo-tv/app/build.gradle.kts), [stub contract testi](../../android/app/src/test/kotlin/com/lagradost/CloudStreamStubContractTest.kt).

## 3. Aniyomi: APK source runtime

```text
repository index → package metadata → bir yoki bir necha source
  → APK → tachiyomi.animeextension.class
  → DexClassLoader → AnimeSource / AnimeSourceFactory
  → AnimeCatalogueSource
  → popular/latest/search → details → episodes
  → video yoki hoster → video → player
```

Extension host ilovadan source API, HTTP client, cookie/preferences, dependency injection va ayrim hollarda JS bajarishni kutadi. Shuning uchun faqat APK’ni yuklab olish yetarli emas. `AnimeHttpSource` HTTP/parse oqimini beradi, `ParsedAnimeHttpSource` HTML parsing uchun qulay qatlam, factory esa bitta APK ichidan bir nechta source chiqaradi. Upstream manbalar: [extension API](https://unstable-extension-docs.aniyomi.org/), [source ishlab chiqish qo‘llanmasi](https://github.com/aniyomiorg/aniyomi-extensions/blob/master/CONTRIBUTING.md).

Sozo mobile’dagi amaldagi implementatsiya:

- `ExtensionIndex` JSON va gzip/protobuf index formatlarini umumiy metadata’ga keltiradi. Repo qo‘shilganda barcha APK yuklanmaydi; source metadata registratsiya qilinadi.
- `AniyomiHost.ensureApk` birinchi foydalanishda APK’ni oladi: `.part.apk`, uzunlik tekshiruvi, mavjud bo‘lsa repo signing fingerprint tekshiruvi, keyin rename.
- `AniyomiRuntime.bootstrap` Injekt’ga Application, NetworkHelper, JavaScriptEngine va Json beradi. JS yordamchisi QuickJS’dan foydalanadi.
- APK manifestidagi klasslar yaratiladi; factory bo‘lsa source’lar chiqariladi; source ID bo‘yicha cache saqlanadi.
- Eski episode → video yo‘li ham, yangi episode → hoster → video yo‘li ham bor. Kotlin suspend methodlari uchun reflection/Continuation moslashtirish mavjud.
- Provider ID — `an:<source.id>`. Home, search, detail, episodes va media MethodChannel’ga ulangan.
- Update APK URL o‘zgarishiga qaraydi va cache’ni yangilash yo‘liga ega; bu TV implementatsiyasidan farq qiladi.

Manbalar: [ExtensionIndex](../../android/app/src/main/kotlin/com/soplay/sozo/extensions/ExtensionIndex.kt), [repo manager](../../android/app/src/main/kotlin/com/soplay/sozo/aniyomi/AniyomiRepoManager.kt), [host](../../android/app/src/main/kotlin/com/soplay/sozo/aniyomi/AniyomiHost.kt), [runtime](../../android/app/src/main/kotlin/com/soplay/sozo/aniyomi/AniyomiRuntime.kt), [QuickJS helper](../../android/app/src/main/kotlin/eu/kanade/tachiyomi/network/JavaScriptEngine.kt), [signature tekshiruvi](../../android/app/src/main/kotlin/com/soplay/sozo/extensions/ApkSignature.kt).

Moslik chegarasi: hoster API yoki `Video.videoTitle` kabi methodlar aniq binary signature bilan mavjud bo‘lishi kerak. `NoClassDefFoundError`/`NoSuchMethodError` tarmoq muammosi emas, runtime va extension API orasidagi farq bo‘lishi mumkin. `getGenresJson` mobile Aniyomi hostida hozir `[]`; detail ichidagi genre matni bilan genre bo‘yicha browse API bir xil imkoniyat emas. Manba: [AniyomiHost](../../android/app/src/main/kotlin/com/soplay/sozo/aniyomi/AniyomiHost.kt).

### Upstream Aniyomi bilan aynan teng bo‘lmagan qismlar

Original Aniyomi loader tizimga o‘rnatilgan APK va private `.ext` fayllarini qo‘llaydi; signature trust, extension feature va lib versiyasini tekshiradi. U `ChildFirstPathClassLoader`, zarur holatda `PathClassLoader` fallback’dan foydalanadi. Sozo’dagi oddiy `DexClassLoader` adapteri bu mexanizmning aynan nusxasi emas. Ko‘rilgan upstream commit loader’i faqat `14.0` va `16.0` lib versiyalarini qabul qiladi, source API’da esa allaqachon `extensions-lib 17` deb belgilangan methodlar bor. API kodida method mavjudligidan loader o‘sha lib versiyasini qabul qiladi degan xulosa chiqmaydi. Manba: [upstream AnimeExtensionLoader](https://github.com/aniyomiorg/aniyomi/blob/4b5b90a3749b2c0504d4ffdd9416051d4730226c/app/src/main/java/eu/kanade/tachiyomi/extension/anime/util/AnimeExtensionLoader.kt).

Upstream player’da `EpisodeLoader` eski episode-video va yangi hoster API’larni ajratadi; `HosterLoader` hali initialized bo‘lmagan videoni `resolveVideo` bilan kechiktirib yechadi. Rich `Video` modeli bitrate, resolution, subtitle/audio, chapter timestamp, MPV/FFmpeg argumentlari va opaque internalData kabi maydonlarni ham olib yuradi. Sozo’da katalog va oddiy stream ishlashi shu qo‘shimcha imkoniyatlarning barchasi ishlashini isbotlamaydi. Manbalar: [EpisodeLoader](https://github.com/aniyomiorg/aniyomi/blob/4b5b90a3749b2c0504d4ffdd9416051d4730226c/app/src/main/java/eu/kanade/tachiyomi/ui/player/loader/EpisodeLoader.kt), [HosterLoader](https://github.com/aniyomiorg/aniyomi/blob/4b5b90a3749b2c0504d4ffdd9416051d4730226c/app/src/main/java/eu/kanade/tachiyomi/ui/player/loader/HosterLoader.kt), [Video](https://github.com/aniyomiorg/aniyomi/blob/4b5b90a3749b2c0504d4ffdd9416051d4730226c/source-api/src/commonMain/kotlin/eu/kanade/tachiyomi/animesource/model/Video.kt).

Aniyomi SQLDelight’da source ID + anime URL, epizod URL, seen/bookmark, last_second_seen va total_seconds saqlaydi. Cloudstream’da account-scoped bookmark/watch/resume key-value holati bor. Ikkalasida ham vaqtinchalik stream URL bilan doimiy kontent/epizod identifikatori ajratilishi muhim. Manbalar: [Aniyomi animes](https://github.com/aniyomiorg/aniyomi/blob/4b5b90a3749b2c0504d4ffdd9416051d4730226c/data/src/main/sqldelightanime/dataanime/animes.sq), [episodes](https://github.com/aniyomiorg/aniyomi/blob/4b5b90a3749b2c0504d4ffdd9416051d4730226c/data/src/main/sqldelightanime/dataanime/episodes.sq), [Cloudstream DataStoreHelper](https://github.com/recloudstream/cloudstream/blob/9bca3be59f85668949c2e853ae126c619c87eec6/app/src/main/java/com/lagradost/cloudstream3/utils/DataStoreHelper.kt).

## 4. Zangetsu’ning birlashtirish usuli

Zangetsu Flutter/BLoC ilovasi. Screen-facing repository source turini tanlaydi; adapterlar `BaseProvider` bilan bir xil operatsiyalarni beradi: `getInfo`, `getHome`, `popular`, `search`, `getDetail`, `getEpisodes`, `getVideoSources`. `cs:` Cloudstream, `ani:` Aniyomi uchun ishlatiladi. Sozo’da Aniyomi prefiksi `an:` ekanini migratsiya paytida hisobga olish kerak. Manbalar: [source routing](https://github.com/Spyou/Zangetsu/blob/1e73e19567fa03cf9b8174ee690ab349614c3704/lib/core/repository/source_repository.dart), [interface](https://github.com/Spyou/Zangetsu/blob/1e73e19567fa03cf9b8174ee690ab349614c3704/lib/core/provider/base_provider.dart).

### JavaScript manbalari

JS fayllari repository’dan o‘rnatilib Hive registry’da saqlanadi. `flutter_js` runtime’da providerlar `__providers[sourceId]`, extractorlar `__extractors[host]`, sozlamalar `__settings[sourceId]` orqali ajratiladi. Dart fetch, console, crypto va timer bridge’larini beradi. Provider chaqiruvlari native async/FFI reentrancy muammosini cheklash uchun umumiy navbat orqali ketadi. Timeoutlar oddiy chaqiruvda 15 s, detail’da 30 s, video resolution’da 60 s. Barcha platformada faqat QuickJS deb aytib bo‘lmaydi: kodda Apple TV JavaScriptCore uchun yo‘l ham bor. Manbalar: [ProviderManager](https://github.com/Spyou/Zangetsu/blob/1e73e19567fa03cf9b8174ee690ab349614c3704/lib/core/provider/provider_manager.dart), [JS bootstrap](https://github.com/Spyou/Zangetsu/blob/1e73e19567fa03cf9b8174ee690ab349614c3704/lib/core/provider/js_bootstrap.dart).

Install/update/enable/disable/remove registry’da boshqariladi. Saqlash identifikatori `repoUrl::sourceId`, runtime slot’i esa faqat `sourceId`: ikki repo bir xil source ID bersa oxirgi yuklangan kod ustun kelishi mumkin. Bu koddan chiqarilgan moslik xulosasi, jonli reproduksiya emas. Manba: [ProviderRegistry](https://github.com/Spyou/Zangetsu/blob/1e73e19567fa03cf9b8174ee690ab349614c3704/lib/core/provider/provider_registry.dart).

### Native extensionlar va platformalar

Android Cloudstream adapteri `zangetsu/cloudstream` orqali native `.cs3` hostga murojaat qiladi. `fast:true` rejimida dastlabki ishlaydigan link qaytishi, qolganlari keyin polling orqali olinishi mumkin. Aniyomi esa `zangetsu/aniyomi` va alohida APK loader’dan foydalanadi; loader ko‘rilgan commitda extension lib 12.0–16.0 oralig‘ini qabul qiladi. Bu barcha versiyalar barcha metodlarda to‘liq ishlaydi degani emas. Manbalar: [Cloudstream adapter](https://github.com/Spyou/Zangetsu/blob/1e73e19567fa03cf9b8174ee690ab349614c3704/lib/core/provider/cloudstream_provider.dart), [Aniyomi loader](https://github.com/Spyou/Zangetsu/blob/1e73e19567fa03cf9b8174ee690ab349614c3704/android/app/src/main/kotlin/com/spyou/watch_app/aniyomi/AniyomiExtensionLoader.kt).

README iOS’da o‘z JS manbalari ishlashini, Android `.cs3`/`.apk` runtime’lari ishlamasligini bildiradi; adapterlardagi platform guard’lar bunga mos. Repository’da tvOS player kodi bor, lekin kod mavjudligi alohida release mavjudligini isbotlamaydi. Manba: [README](https://github.com/Spyou/Zangetsu/blob/1e73e19567fa03cf9b8174ee690ab349614c3704/README.md).

### Player va tarix

Umumiy player controller `media_kit`/libmpv, headerlar, subtitrlar, resume, auto-next va source almashtirishni boshqaradi. TV launch’da Android ExoPlayer va Apple AVKit yo‘llari bor. Tarix Hive’da `sourceId::showId` kaliti bilan, epizodning asl URL’i va pozitsiyasi bilan saqlanadi; signed-in foydalanuvchi uchun Supabase sync, cloud yozish throttling’i va incognito sharti bor. Manbalar: [player controller](https://github.com/Spyou/Zangetsu/blob/1e73e19567fa03cf9b8174ee690ab349614c3704/lib/features/player/player_controller.dart), [TV routing](https://github.com/Spyou/Zangetsu/blob/1e73e19567fa03cf9b8174ee690ab349614c3704/lib/features/player/tv_playback_launch.dart), [watch history](https://github.com/Spyou/Zangetsu/blob/1e73e19567fa03cf9b8174ee690ab349614c3704/lib/core/playback/watch_history.dart).

## 5. Sozo bilan bog‘lanishi

Sozo’da alohida Zangetsu runtime klassi topilmadi. O‘z JS mexanizmi `JsRuntimeService` orqali headless WebView’da ishlaydi; backend `/extractors`, `/extractors/runtime`, `/extractors/<name>` orqali kod/versiya beradi. Funksiyalar `getHome`, `getCategory`, `search`, `getDetail`, `getEpisodes`, `resolveMedia`. `scope=all` katalogni ham qurilmada bajaradi, resolve-only scope esa stream yechishni bajaradi. JS engine Linux uchun supported emas. Manbalar: [JS runtime](../../lib/core/js/js_runtime_service.dart), [remote assets](../../lib/core/js/extractor_remote.dart), [cache](../../lib/core/js/extractor_cache.dart).

Zangetsu va Sozo JS’ga tayanishi ularning script shartnomasi bir xil degani emas: method nomlari, result shakli va host bridge’lari tekshirilishi kerak. Zangetsu adapterida “Sozo Read” uchun `chapters`/`episodes`, `getChapters`/`getEpisodes`, `getChapterContent`/`getText` moslashtirishlari bor, lekin bu barcha Sozo extractorlarining avtomatik mosligini isbotlamaydi. Manba: [Zangetsu JsProvider](https://github.com/Spyou/Zangetsu/blob/1e73e19567fa03cf9b8174ee690ab349614c3704/lib/core/provider/provider_manager.dart).

Sozo UI’dan playergacha:

```text
SourceBrowse / Home / Search
  → provider prefiksi yoki JS scope bo‘yicha routing
  → native host yoki JS extractor yoki backend
  → umumiy JSON model
  → DetailRepository.resolveMedia → MediaResolveModel
  → mirror tanlash + mirror headerlari → player
```

Manbalar: [source browse](../../lib/features/sources/data/source_browse_repository.dart), [home routing](../../lib/features/home/data/repositories/home_repository_imp.dart), [detail/media routing](../../lib/features/detail/data/repositories/detail_repository_impl.dart), [media modeli](../../lib/features/detail/data/models/media_resolve_model.dart), [player media](../../lib/features/detail/presentation/pages/player_page.media.dart).

Android bo‘lmagan platformada `ExtensionBridge` sozlangan bo‘lsa Cloudstream/Aniyomi channel’lari Android telefon HTTP bridge’iga boradi. Demak DEX iOS yoki desktop’da bajarilmaydi; telefon bajarib JSON qaytaradi. Bridge token bilan himoyalangan. Barcha native methodlar remote dispatcher’da yo‘q: masalan `checkUpdates` va Cloudstream single-plugin install/list methodlari bridge route’larida ko‘rinmaydi. `isSupported` true bo‘lishi methodlar to‘liq tengligini anglatmaydi. Manbalar: [ExtensionBridge](../../lib/core/extensions/extension_bridge.dart), [BridgeServer dispatch](../../android/app/src/main/kotlin/com/soplay/sozo/BridgeServer.kt), [Cloudstream channel](../../lib/core/cloudstream/cloudstream_channel.dart).

## 6. Sozo TV: mobile bilan tafovutlar

TV `ExtensionEngine` ichida `an:`, `cs:`, `sv:` backend’larini birlashtiradi. `ServerHost` va `WebJsRuntime` Sozo JS extractorlarini bajaradi; Zangetsu nomli alohida integratsiya topilmadi. Natija umumiy extension modellari orqali playerga boradi. Manbalar: [ExtensionEngine](../../../sozo-tv/app/src/main/java/com/saikou/sozo_tv/data/extensions/ExtensionEngine.kt), [ServerHost](../../../sozo-tv/app/src/main/java/com/saikou/sozo_tv/engine/server/ServerHost.kt), [WebJsRuntime](../../../sozo-tv/app/src/main/java/com/saikou/sozo_tv/engine/webjs/WebJsRuntime.kt).

| Qism | Mobile | TV |
|---|---|---|
| Cloudstream library | v4.8.0 | v4.7.0 |
| Cloudstream torrent/magnet | Resolve natijasiga `torrent` sifatida uzatiladi | Hostda filtrlanadi |
| Aniyomi APK cache | Remote APK nomiga bog‘langan, update invalidation bor | Barqaror `<package>.apk`, mavjud fayl qayta ishlatiladi |
| Aniyomi download | Temp fayl, uzunlik/fingerprint tekshiruvi | Final faylga to‘g‘ridan-to‘g‘ri yoziladi |
| Aniyomi video API | Hoster yo‘li va eski API fallback | Episode video yo‘li va URL fallback |

Manbalar: [TV Cloudstream host](../../../sozo-tv/app/src/main/java/com/saikou/sozo_tv/engine/cloudstream/PluginHost.kt), [TV Aniyomi host](../../../sozo-tv/app/src/main/java/com/saikou/sozo_tv/engine/aniyomi/AniyomiHost.kt), [TV Aniyomi runtime](../../../sozo-tv/app/src/main/java/com/saikou/sozo_tv/engine/aniyomi/AniyomiRuntime.kt), mobile manbalari 2–3-bo‘limda.

## 7. Koddan aniqlangan muhim cheklovlar

1. **Eski Aniyomi hujjati amaldagi holatni aks ettirmaydi.** `ANIYOMI_INTEGRATION.md` Stage 2 pending deydi; real runtime va channel handlerlar mavjud. `CLOUDSTREAM_INTEGRATION.md` ham eski versiya/platform ma’lumotlarini saqlagan. Manbalar: [eski Aniyomi hujjati](../ANIYOMI_INTEGRATION.md), [eski Cloudstream hujjati](../CLOUDSTREAM_INTEGRATION.md), [MainActivity](../../android/app/src/main/kotlin/com/soplay/sozo/MainActivity.kt).
2. **TV Aniyomi update mavjud APK binary’ni yangilamaydi.** `checkUpdates` index’ni qayta oladi va yangi source’larni hisoblaydi; `ensureApk` mavjud nonempty `<package>.apk`ni darhol qaytaradi. Runtime shu path/source’ni cache qiladi. Shuning uchun metadata yangilanishi extension kodi yangilanishiga teng emas. Manbalar: [TV RepoManager](../../../sozo-tv/app/src/main/java/com/saikou/sozo_tv/engine/aniyomi/AniyomiRepoManager.kt), [TV Host](../../../sozo-tv/app/src/main/java/com/saikou/sozo_tv/engine/aniyomi/AniyomiHost.kt).
3. **Mobile Cloudstream alohida audio yo‘lida ma’lumot yo‘qoladi.** Native host `audioTracks`ni JSON’ga yozadi, ammo `VideoSourceModel` va `VideoSourceEntity` bu maydonni o‘qimaydi/saqlamaydi. Bu tashqi audio renditionlar haqida; manifest yoki videoning ichidagi audio treklar alohida masala. Manbalar: [native mapper](../../android/app/src/main/kotlin/com/soplay/sozo/cloudstream/PluginHost.kt), [Dart mapper](../../lib/features/detail/data/models/video_source_model.dart), [entity](../../lib/features/detail/domain/entities/video_source_entity.dart).
4. **Aniyomi mobile mapper Cloudstream mapperidan torroq.** `.m3u8` bo‘lsa HLS, aks holda HTTP deb belgilaydi; `Video.audioTracks`ni uzatmaydi. DASH yoki alohida audio beradigan extensionlarda adapter natijasini alohida tekshirish kerak. Bu barcha shunday streamlar albatta ijro bo‘lmaydi degan xulosa emas. Manbalar: [Aniyomi loadLinksJson](../../android/app/src/main/kotlin/com/soplay/sozo/aniyomi/AniyomiHost.kt), [Video](../../android/app/src/main/kotlin/eu/kanade/tachiyomi/animesource/model/Video.kt).
5. **Remote bridge native channel bilan to‘liq teng emas.** Channel’da mavjud ayrim management methodlari HTTP dispatcher’da yo‘q; umumiy transport xatolari ayrim wrapperlarda null/empty’ga aylanadi. Manbalar: [BridgeServer](../../android/app/src/main/kotlin/com/soplay/sozo/BridgeServer.kt), [ExtensionBridge](../../lib/core/extensions/extension_bridge.dart).

Bu tekshiruvda cheklovlar hujjatlashtirildi, production kod o‘zgartirilmadi.

## 8. Ishlayotganini qanday isbotlash kerak

Har bir ekotizim uchun alohida tekshiruv zanjiri zarur:

1. Repo index o‘qilishi va source ID/versiyaning to‘g‘ri kelishi.
2. Bitta extension’ning yuklanishi va startup’dan keyin qayta ochilishi.
3. Home, search pagination, detail va episode ketma-ketligi.
4. Episode data o‘zgarmasdan resolve’ga yetishi.
5. Stream URL + har bir mirrorning headerlari + sifat + subtitr/audio saqlanishi.
6. Qurilmada haqiqiy ijro, seek, mirror almashtirish, resume.
7. Extension update’dan so‘ng yangi binary va cache invalidation.
8. Bo‘sh katalog, tarmoq xatosi, ABI xatosi va stream topilmagan holatlarni ajratish.

TV’da [2026-09-12 search matritsasi](../../../sozo-tv/docs/audits/2026-09-12/cloudstream-matrix.md) bor. U tarixiy bitta query tekshiruvi; hozirgi barcha providerlar uchun playback isboti emas. Ushbu hisobotning yangi bajarilgan verifikatsiyasi — birlamchi kod va hujjatlarni solishtirish; yuqoridagi device testlar hali bajarilmagan.
