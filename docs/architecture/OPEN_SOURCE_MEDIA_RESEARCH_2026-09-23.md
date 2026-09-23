# Open-source media ilovalari: kodga asoslangan tadqiqot

Sana: 2026-09-23. Maqsad: Sozo uchun manbalar/extension UX, ishonch, playback, offline va anime–manga–novel davomiyligidan foydali naqshlarni ajratish.

## Metod va dalil chegarasi

Rasmiy GitHub API orqali default branch commitlari aniqlandi, tree va tanlangan haqiqiy implementatsiya fayllari `/tmp` ga olinib o‘qildi. Quyidagi havolalar o‘zgarmas commitga bog‘langan. Bu runtime/device benchmark yoki barcha funksiyalar auditi emas. README va protokol tavsifi koddan alohida belgilanadi. Koddagi kommentariya bilan bajariluvchi mantiq farq qilsa, bajariluvchi mantiq asos qilindi. Ishchi production kod o‘zgartirilmadi.

Zangetsu — avvalgi `CLOUDSTREAM_ZANGETSU_ANIYOMI_RESEARCH.md` da belgilangan **Spyou/Zangetsu**. Miru — **miru-project** tashkiloti; shu nomdagi boshqa loyihalar bilan aralashtirilmadi. Sozo uchun quyidagi tavsiyalar taklif hisoblanadi: mavjud Sozo funksiyasi yo‘q degan xulosa emas, avval mavjud implementatsiya bilan gap tahlili kerak.

## Manbalar va snapshot

| Repozitoriy | O‘qilgan commit | Dalil turi |
|---|---|---|
| recloudstream/cloudstream | [`0e4793010fbe`](https://github.com/recloudstream/cloudstream/tree/0e4793010fbecf9fed987df9f7b18c448f103008) | Haqiqiy kod + litsenziya |
| aniyomiorg/aniyomi | [`97414446b8a9`](https://github.com/aniyomiorg/aniyomi/tree/97414446b8a95994c72dd33c41c971a89d4d25b8) | Haqiqiy kod + litsenziya |
| Spyou/Zangetsu | [`21712432329d`](https://github.com/Spyou/Zangetsu/tree/21712432329d781023ff1b4241bba146e1150710) | Haqiqiy kod + litsenziya |
| Stremio/stremio-core | [`b3062f7fa790`](https://github.com/Stremio/stremio-core/tree/b3062f7fa790223540022f9a62c12067b646c179) | Haqiqiy kod + litsenziya |
| Stremio/stremio-addon-sdk | [`83bd843ee841`](https://github.com/Stremio/stremio-addon-sdk/tree/83bd843ee84135857db52273297d2ef5929c7366) | Haqiqiy kod + litsenziya |
| miru-project/miru-app | [`8599d0dbfbb1`](https://github.com/miru-project/miru-app/tree/8599d0dbfbb1c1d86dcfa3d8d78e4c438d3fe2c0) | Haqiqiy kod + litsenziya |
| miru-project/miru-alpha | [`63d23f9efc1a`](https://github.com/miru-project/miru-alpha/tree/63d23f9efc1add32ae23febdb862ff83e4954651) | Identity/metadata; frontend implementatsiyasi tekshirilmadi |
| miru-project/miru-core | [`9db82b81b8f5`](https://github.com/miru-project/miru-core/tree/9db82b81b8f5dbfedbc24fdf3a1184ff27891061) | Haqiqiy kod + litsenziya |
| itsmechinmoy/Dantotsu | [`28cbfba30eba`](https://github.com/itsmechinmoy/Dantotsu/tree/28cbfba30ebaa1ec52dea92416d8e4838fc797b0) | Mustaqil continuation kodi; asl rasmiy repo emas |
| mihonapp/mihon | [`f52d890e7f8a`](https://github.com/mihonapp/mihon/tree/f52d890e7f8a3c418ddab41f41d4b577bce0dc06) | Haqiqiy kod + litsenziya |
| LNReader/lnreader | [`920f88aee446`](https://github.com/LNReader/lnreader/tree/920f88aee4460a53ac0a3cf73cdc77ee915eb282) | Haqiqiy kod + litsenziya |

Default branch commit sanasi release sanasi yoki barcha branchlarning faolligi bilan bir xil emas. Eski `miru-app` default branchining eski sanasi Miru oilasi rivojlanmayapti degani emas: yangi `miru-alpha`/`miru-core` alohida loyihalar.

## 1. Cloudstream: extension lifecycle va offline holat mashinasi

**Kod tasdiqlaydi:**

- `PluginManager` online metadata versiyasini installed versiya bilan taqqoslaydi; maxsus always-update qiymatini taniydi; server statusi down bo‘lgan pluginni unload qiladi. Extension holati faqat “o‘rnatilgan/o‘rnatilmagan” emas. [PluginManager.kt](https://github.com/recloudstream/cloudstream/blob/0e4793010fbecf9fed987df9f7b18c448f103008/app/src/main/java/com/lagradost/cloudstream3/plugins/PluginManager.kt).
- Shu manager plugin faylini load/unload qiladi, registry va lifecycle bilan ishlaydi. Bu executable plugin arxitekturasi; repository ro‘yxatini ko‘rsatishning o‘zi executable kodni sandbox qilganini anglatmaydi. [PluginManager.kt](https://github.com/recloudstream/cloudstream/blob/0e4793010fbecf9fed987df9f7b18c448f103008/app/src/main/java/com/lagradost/cloudstream3/plugins/PluginManager.kt).
- `RepositoryManager` repository metadata va plugin fayli yuklanishini ajratadi. Sozo katalogining repository identity, paket identity va runtime identity qismlari ham alohida saqlanishi foydali. Ikkinchi jumla — Sozo taklifi. [RepositoryManager.kt](https://github.com/recloudstream/cloudstream/blob/0e4793010fbecf9fed987df9f7b18c448f103008/app/src/main/java/com/lagradost/cloudstream3/plugins/RepositoryManager.kt).
- Download manager pause/resume/pending holatlari, saqlangan resume paketlari va queue, mirror almashtirish/retry natijalari, HTTP byte range hamda HLS segment indeksini davom ettirish yo‘llariga ega. Barcha hostlar range’ni to‘g‘ri qo‘llaydi degan kafolat bundan kelib chiqmaydi. [DownloadManager.kt](https://github.com/recloudstream/cloudstream/blob/0e4793010fbecf9fed987df9f7b18c448f103008/app/src/main/java/com/lagradost/cloudstream3/utils/downloader/DownloadManager.kt).

**Sozo uchun:** Source kartasida installed version, available version, update failure va temporary outage’ni ajratish; download’da “queued”, “fetching links”, “downloading”, “paused”, “failed”, “completed” bosqichlarini aniq ko‘rsatish. Cloudstream kodidan mobil qizishi bo‘yicha xulosa chiqarilmadi.

## 2. Aniyomi: APK ishonchi, playback progress va download-ahead

- `TrustAnimeExtension` repository signing key yoki aniq `package:version:signature` yozuvi bilan trust tekshiradi; qo‘lda yangi trust berilganda avvalgi paket versiyasi trust yozuvlari olib tashlanadi. Bu trust’ni package nomigagina bog‘lamaslik uchun konkret namuna. [TrustAnimeExtension.kt](https://github.com/aniyomiorg/aniyomi/blob/97414446b8a95994c72dd33c41c971a89d4d25b8/app/src/main/java/eu/kanade/domain/extension/anime/interactor/TrustAnimeExtension.kt).
- `AnimeExtensionLoader` supported library versiyalari ro‘yxatini tekshiradi, signing fingerprints yo‘q bo‘lsa reject qiladi, ishonilmagan APK uchun `Untrusted` natija qaytaradi. Ushbu snapshot supported qiymatlari `14.0`, `16.0`, `17.0`; Sozo bularni ko‘r-ko‘rona hardcode qilmasligi, o‘z runtime compatibility kontraktini ko‘rsatishi kerak. [AnimeExtensionLoader.kt](https://github.com/aniyomiorg/aniyomi/blob/97414446b8a95994c72dd33c41c971a89d4d25b8/app/src/main/java/eu/kanade/tachiyomi/extension/anime/util/AnimeExtensionLoader.kt).
- `PlayerViewModel` episode progress va tarixini alohida saqlaydi; tracking yangilanishi auto-update sozlamasiga bog‘langan. Download-ahead faqat current va next episode allaqachon downloaded bo‘lgan yo‘lda ishlaydi; kod kommentariyasi bu tanlovni jank’ni oldini olish bilan izohlaydi. [PlayerViewModel.kt](https://github.com/aniyomiorg/aniyomi/blob/97414446b8a95994c72dd33c41c971a89d4d25b8/app/src/main/java/eu/kanade/tachiyomi/ui/player/PlayerViewModel.kt).
- `AnimeDownloadManager` downloader, queue va diskdagi download provider/cache bilan ishlaydi; chapter/episode identity’ni transfer vazifasidan ajratish naqshi bor. [AnimeDownloadManager.kt](https://github.com/aniyomiorg/aniyomi/blob/97414446b8a95994c72dd33c41c971a89d4d25b8/app/src/main/java/eu/kanade/tachiyomi/data/download/anime/AnimeDownloadManager.kt).

**Sozo uchun:** install bosqichida “repository trusted”, “package signature verified”, “runtime supported” uchta alohida signal; player progress’ni lokal saqlash va tracker sync’ni ajratish; prefetch/download-ahead’ni limitlash va sozlanadigan qilish. Aniyomi FAQ light novel’ni manga image parser yo‘liga qo‘shishdan cheklaydi; bu Sozo novel uchun alohida text/EPUB model kerakligiga foydali kontrast, barcha forklar imkoniyatlari haqida hukm emas. [Rasmiy FAQ](https://aniyomi.org/docs/faq/general).

## 3. Zangetsu: source health, resolver va o‘qish davomiyligi

- `SourceHealthStore` search va playback evidence’ni alohida yozadi. **Muhim tafovut:** faylning yuqori kommentariyasi timeout/blocked’ni dead deb tasvirlasa ham, joriy `record()` switch faqat `SourceOutcome.error` uchun dead beradi; qolganlari `ok`. Eskirgan dead mark 30 daqiqadan keyin skip qilinmaydi. Demak kommentariyani haqiqiy xulq deb ko‘chirish noto‘g‘ri. [source_health_store.dart](https://github.com/Spyou/Zangetsu/blob/21712432329d781023ff1b4241bba146e1150710/lib/core/playback/source_health_store.dart).
- Playback health oxirgi 14 kundagi **alohida title** muvaffaqiyatsizliklarini hisoblaydi; 6 title’dan keyin advisory dead belgisi; bir muvaffaqiyat yozuvlarni tozalaydi. Bir xil title’ni qayta bosish 6 ta mustaqil dalil bo‘lmaydi. Bu playback indikatori search’dan manbani avtomatik yashirmaydi. [source_health_store.dart](https://github.com/Spyou/Zangetsu/blob/21712432329d781023ff1b4241bba146e1150710/lib/core/playback/source_health_store.dart).
- `PlaybackResolver` candidate verdict sabablarini saqlaydi, generation/abort boshqaruvi va 3 tadan wave qo‘llaydi; default va off-UI sharoitlari uchun budgetlar farqli. Kod kommentariyasi shared JS engine serial ishlashi sabab uchta Future har doim uchta parallel JS bajarilishi degani emasligini ochiq qayd etadi. Qurilmada haqiqiy tezlik o‘lchanmadi. [playback_resolver.dart](https://github.com/Spyou/Zangetsu/blob/21712432329d781023ff1b4241bba146e1150710/lib/core/zmode/playback_resolver.dart).
- `ReadHistory.save()` lokal Hive yozuvini await qiladi, cloud yozuvini odatda 2 daqiqaga throttle qiladi va `flush:true` bilan majburiy yuboradi; incognito saqlashni o‘tkazib yuboradi. Chapter switch/reader exit’da flush qilish talabi API darajasida mavjud; barcha callerlar bu talabni bajarayotgani bu tadqiqotda to‘liq tekshirilmadi. [read_history.dart](https://github.com/Spyou/Zangetsu/blob/21712432329d781023ff1b4241bba146e1150710/lib/core/reading/read_history.dart).
- `ChapterDownloader` batch enqueue’ni bitta write/notify bilan bajaradi, interrupted ishlarni qayta navbatga qo‘yadi, partial sahifalarni saqlab retry’da tayyor fayllarni skip qiladi; rasm so‘rovida page headers ishlatiladi. `TrackerHub` connected tracker’larga fan-out qiladi va bir tracker xatosini boshqalardan ajratadi. [chapter_downloader.dart](https://github.com/Spyou/Zangetsu/blob/21712432329d781023ff1b4241bba146e1150710/lib/core/download/chapter_downloader.dart), [tracker_hub.dart](https://github.com/Spyou/Zangetsu/blob/21712432329d781023ff1b4241bba146e1150710/lib/core/tracker/tracker_hub.dart).

**Sozo uchun:** source health ekranida “search ishlaydi / stream resolve ishlamaydi” ko‘rinishi; failure reason va oxirgi tekshiruv; bir title xatosi sabab butun source’ni disabled qilmaslik. Resolver cancellation asl runtime ishini ham to‘xtatadimi, alohida tekshirish kerak: faqat `.timeout` UI kutishini tugatishi mumkin.

## 4. Stremio: transport kontrakti va watched state

- SDK protokolida addon HTTP JSON resource endpointlarini beradi; `manifest`, `catalog`, `meta`, `stream`, `subtitles` kontraktlari bor. Bu APK/JS faylini klientga install qilishdan boshqa integratsiya modeli. Manifest resources/type/idPrefixes yordamida tegishli requestni route qilish mumkin. **Bu band protokol hujjati.** [protocol.md](https://github.com/Stremio/stremio-addon-sdk/blob/83bd843ee84135857db52273297d2ef5929c7366/docs/protocol.md), [manifest.md](https://github.com/Stremio/stremio-addon-sdk/blob/83bd843ee84135857db52273297d2ef5929c7366/docs/api/responses/manifest.md).
- Haqiqiy SDK `serveHTTP.js` Express router, configurable cache header, config mavjud bo‘lsa `/configure`ga landing redirect va manifest install URL’ini yaratadi. Stremio core `HttpTransport` resource HTTP fetch’ini bajaradi. **Bu band implementatsiya.** [serveHTTP.js](https://github.com/Stremio/stremio-addon-sdk/blob/83bd843ee84135857db52273297d2ef5929c7366/src/serveHTTP.js), [http_transport.rs](https://github.com/Stremio/stremio-core/blob/b3062f7fa790223540022f9a62c12067b646c179/src/addon_transport/http_transport/http_transport.rs).
- Core `Player` modeli seek va `TimeChanged` eventlarini ajratadi; watched mark uchun duration > 0 va live emasligi guard’i bor; time-watched bilan threshold hisoblanadi. Comment klient tegishli seek eventlarini to‘g‘ri berishi kerakligini aytadi: transport yoki modelning o‘zi noto‘g‘ri player eventlarini tuzatib yubormaydi. [player.rs](https://github.com/Stremio/stremio-core/blob/b3062f7fa790223540022f9a62c12067b646c179/src/models/player.rs).
- Library yangilanishi alohida context modulida push/pull/merge oqimlariga ajratilgan. Playback ekranining widget lifecycle’i library sync kontraktining yagona egasi emas. [update_library.rs](https://github.com/Stremio/stremio-core/blob/b3062f7fa790223540022f9a62c12067b646c179/src/models/ctx/update_library.rs).

**Sozo uchun:** har runtime ustidan umumiy resource capability kontrakti, remote addon uchun sozlash/form UX; unknown/live duration’ni `0/0` completion sifatida qabul qilmaslik; watched completion’ni oddiy seek position’dan alohida saqlash. Remote addon HTTP bo‘lgani barcha serverlar ishonchli yoki foydalanuvchi querylari maxfiy degani emas.

## 5. Miru: eski Flutter app va yangi Go rework

- Eski `miru-app` extension service/runtime va umumiy extension modeliga ega. `ReaderController` media content’ni `runtime.watch()` orqali oladi, current episode/group/package/progress’ni tarixga yozadi. Shu base controller’dagi `previousPage()`/`nextPage()` bo‘sh: buni barcha konkret readerlar navigation’siz deb talqin qilib bo‘lmaydi. [extension_service.dart](https://github.com/miru-project/miru-app/blob/8599d0dbfbb1c1d86dcfa3d8d78e4c438d3fe2c0/lib/data/services/extension_service.dart), [extension.dart](https://github.com/miru-project/miru-app/blob/8599d0dbfbb1c1d86dcfa3d8d78e4c438d3fe2c0/lib/models/extension.dart), [reader_controller.dart](https://github.com/miru-project/miru-app/blob/8599d0dbfbb1c1d86dcfa3d8d78e4c438d3fe2c0/lib/controllers/watch/reader_controller.dart).
- Yangi `miru-core` metadata parser `.js` → goja va `.go` → Scriggo runtime’ni markaziy routelashda ajratadi; API version metadata va JS package/filename mosligini tekshiradi. Hamma runtime uchun bir xil implicit default ishlatishdan ko‘ra capability/version farqini yuzaga chiqarish naqshi. [extension.go](https://github.com/miru-project/miru-core/blob/9db82b81b8f5dbfedbc24fdf3a1184ff27891061/pkg/extension/extension.go).
- Yangi downloader concurrency limit, queued priority, reorder, cancel/pause va persist recovery oqimlariga ega. `resumeByID` dispatchida HLS/MP4/torrent yo‘llari ko‘rinadi. **`pkg/download/novel.go` faqat package deklaratsiyasi**: shu fayldan “novel offline to‘liq tayyor” degan xulosa chiqarib bo‘lmaydi. [download.go](https://github.com/miru-project/miru-core/blob/9db82b81b8f5dbfedbc24fdf3a1184ff27891061/pkg/download/download.go), [novel.go](https://github.com/miru-project/miru-core/blob/9db82b81b8f5dbfedbc24fdf3a1184ff27891061/pkg/download/novel.go).
- History DB operatsiyalari alohida modulda: UI bilan persistence chegarasi ko‘rinadi. Bu ma’lumot o‘z-o‘zidan cross-device sync to‘liq ishlashini isbotlamaydi. [history.go](https://github.com/miru-project/miru-core/blob/9db82b81b8f5dbfedbc24fdf3a1184ff27891061/pkg/db/history.go).

**Sozo uchun:** downloader concurrency’ni nazorat qilish, reorder/pause barcha batch uchun ishlashi, runtime imkoniyatlari bo‘yicha disabled action sababi. Bir oiladagi eski app README’sini yangi reworkning shipping funksiyasi deb sanamaslik.

## 6. Dantotsu: provenance chegarasi va tekshirilgan continuation

Asl [rebelonion/Dantotsu](https://github.com/rebelonion/Dantotsu) 2026-09-23 tekshiruvida HTTP **451** qaytardi; GitHub API blok sababini DMCA sifatida bildirdi va [GitHub notice](https://github.com/github/dmca/blob/master/2025/03/2025-03-11-crunchyroll.md)ga bog‘ladi. Asl joriy kodni o‘qilgan deb ko‘rsatmaymiz. `dantotsu.app` tekshiruvda boshqa saytga redirect qildi, shu sabab uni ishonchli current download manzili sifatida tavsiya qilmaymiz.

Quyidagilar **itsmechinmoy/Dantotsu mustaqil continuation** snapshotidan; rasmiy asl upstreamga tenglashtirilmaydi. API uni fork sifatida belgilamagan, shuning uchun “rasmiy fork” deya da’vo qilinmaydi.

- `PlayerProgressManager` ended/forceComplete yoki user watch-percentage orqali completion aniqlaydi; incognito va title-level save-progress sozlamalarini tekshiradi, AniList login bo‘lsa progress yuboradi. [PlayerProgressManager.kt](https://github.com/itsmechinmoy/Dantotsu/blob/28cbfba30ebaa1ec52dea92416d8e4838fc797b0/app/src/main/java/ani/dantotsu/media/anime/player/PlayerProgressManager.kt).
- `PendingProgressUpdate` serializable modelida media ID, anime/manga farqi, progress, status, score, rewatch, privacy va sanalar bor. **Faqat modelni o‘qish durable retry queue end-to-end ishlaydi degan isbot emas.** [PendingProgressUpdate.kt](https://github.com/itsmechinmoy/Dantotsu/blob/28cbfba30ebaa1ec52dea92416d8e4838fc797b0/app/src/main/java/ani/dantotsu/connections/PendingProgressUpdate.kt).
- `DownloadAddonManager` built-in NativeVideoDownloader install qiladi va addon install lifecycle’iga ega. Bu continuation kodidagi hybrid built-in/addon naqshi; asl upstreamning hozirgi xulqi deb ko‘rsatilmaydi. [DownloadAddonManager.kt](https://github.com/itsmechinmoy/Dantotsu/blob/28cbfba30ebaa1ec52dea92416d8e4838fc797b0/app/src/main/java/ani/dantotsu/addons/download/DownloadAddonManager.kt).

**Sozo uchun:** tracking state’ni faqat integer progressga qisqartirmaslik; incognito/individual-title sync preference; identity/provenance’ni source UX’da ochiq ko‘rsatish. Dantotsu continuation custom litsenziyasi sabab to‘g‘ridan-to‘g‘ri kod ko‘chirish alohida tekshiruv talab qiladi.

## 7. Mihon va LNReader: reader hamda novel uchun qo‘shimcha namuna

- **Mihon:** loader installed/shared APK variantlarida version/signature validation, downgrade va signature mismatch tekshiruvlarini bajaradi; migration search alohida ViewModel. Source migration’ni oddiy “source tanlash”dan mustaqil workflow sifatida loyihalash foydali. [ExtensionLoader.kt](https://github.com/mihonapp/mihon/blob/f52d890e7f8a3c418ddab41f41d4b577bce0dc06/app/src/main/java/eu/kanade/tachiyomi/extension/util/ExtensionLoader.kt), [MigrateSearchViewModel.kt](https://github.com/mihonapp/mihon/blob/f52d890e7f8a3c418ddab41f41d4b577bce0dc06/app/src/main/java/eu/kanade/tachiyomi/ui/browse/migration/search/MigrateSearchViewModel.kt).
- **LNReader:** download checkpoint parser integer indeksni `[0,chapterCount]` oralig‘iga clamp qiladi; malformed JSON safe default va failures string filtering bilan ishlaydi. EPUB export temporary file yaratadi, progress’ni 250 ms bilan throttle qiladi, destination’ga copy bosqichini alohida bajaradi. [downloadCheckpoint.ts](https://github.com/LNReader/lnreader/blob/920f88aee4460a53ac0a3cf73cdc77ee915eb282/src/services/download/downloadCheckpoint.ts), [export.ts](https://github.com/LNReader/lnreader/blob/920f88aee4460a53ac0a3cf73cdc77ee915eb282/src/services/epub/export.ts).
- LNReader TTS session hook play/pause/next/previous/replay/stop komandalarini ajratadi va cleanup’da sessionni stop qiladi. Backup options library/settings/plugins/downloadedFiles’ni ajratadi; downloadedFiles library tanloviga bog‘langan. [useTtsSession.ts](https://github.com/LNReader/lnreader/blob/920f88aee4460a53ac0a3cf73cdc77ee915eb282/src/screens/reader/hooks/useTtsSession.ts), [options.ts](https://github.com/LNReader/lnreader/blob/920f88aee4460a53ac0a3cf73cdc77ee915eb282/src/services/backup/options.ts).

**Sozo uchun:** novel text anchor/progress va manga page index’ini alohida model; offline novel/EPUB’ni haqiqiy fayl kontrakti bilan qo‘llash; TTS faqat content semantics tayyor bo‘lgach. Metadata backup va katta offline fayllarni backup qilish alohida tanlov bo‘lishi kerak.

## Litsenziya va qayta foydalanish chegarasi

Quyidagilar repo LICENSE faylidagi deklaratsiyalar; dependency va individual fayl attribution’lari ham tekshirilishi kerak. Arxitektura g‘oyasidan mustaqil implementatsiya va mavjud kodni ko‘chirish bir xil ish emas. Kod/assets import qilinadigan PR oldidan attribution, source disclosure va distribution shartlari tekshiriladi; bu hisobot hech bir kombinatsiyani avtomatik compatible deb tasdiqlamaydi.

| Loyiha | O‘qilgan deklaratsiya |
|---|---|
| recloudstream/cloudstream | [GPL v3](https://github.com/recloudstream/cloudstream/blob/0e4793010fbecf9fed987df9f7b18c448f103008/LICENSE) |
| Spyou/Zangetsu | [GPL v3](https://github.com/Spyou/Zangetsu/blob/21712432329d781023ff1b4241bba146e1150710/LICENSE) |
| aniyomiorg/aniyomi | [Apache 2.0](https://github.com/aniyomiorg/aniyomi/blob/97414446b8a95994c72dd33c41c971a89d4d25b8/LICENSE) |
| mihonapp/mihon | [Apache 2.0](https://github.com/mihonapp/mihon/blob/f52d890e7f8a3c418ddab41f41d4b577bce0dc06/LICENSE) |
| Stremio/stremio-core | [MIT](https://github.com/Stremio/stremio-core/blob/b3062f7fa790223540022f9a62c12067b646c179/LICENSE.md) |
| Stremio/stremio-addon-sdk | [MIT](https://github.com/Stremio/stremio-addon-sdk/blob/83bd843ee84135857db52273297d2ef5929c7366/LICENSE.md) |
| miru-project/miru-app | [AGPL v3](https://github.com/miru-project/miru-app/blob/8599d0dbfbb1c1d86dcfa3d8d78e4c438d3fe2c0/LICENSE) |
| miru-project/miru-core | [AGPL v3](https://github.com/miru-project/miru-core/blob/9db82b81b8f5dbfedbc24fdf3a1184ff27891061/LICENSE) |
| LNReader/lnreader | [MIT](https://github.com/LNReader/lnreader/blob/920f88aee4460a53ac0a3cf73cdc77ee915eb282/LICENSE) |
| itsmechinmoy/Dantotsu | [Custom Unabandon Public License; GPLv3 incorporation va qo‘shimcha shartlar](https://github.com/itsmechinmoy/Dantotsu/blob/28cbfba30ebaa1ec52dea92416d8e4838fc797b0/LICENSE.md) |

## Sozo uchun ustuvor takliflar — hali implementatsiya dalili emas

| Navbat | Taklif | Qabul mezoni / nima bilan tekshirish |
|---|---|---|
| P0 | Source provenance + compatibility + trust alohida holatlar | Repository URL, package/runtime identity, version, imzo/trust va incompatible sabab ko‘rinadi; failed update ishlayotgan installed paketni yo‘qotmaydi. Aniyomi/Mihon/Cloudstream naqshlari. |
| P0 | Search, details, pages/stream health alohida | Empty results manbani dead qilmaydi; bir broken title butun source’ni bloklamaydi; retry va expiry bor; xato source/request bosqichi bilan ko‘rinadi. Zangetsu naqshi, uning comment/code nomuvofiqligini ko‘chirmasdan. |
| P0 | Durable media-specific progress | Manga page, novel anchor/ratio, video position/duration alohida; chapter/episode switch va app background’da local flush; unknown duration completion bermaydi; offline→online sync takroriy yozuvni buzmaydi. Zangetsu/Stremio/LNReader. |
| P0 | Download haqiqatini UI bilan mos qilish | Queued completed sifatida ko‘rsatilmaydi; kill→restart resume; partial files, expired URL qayta resolve; per-page headers/cookie; novel unsupported bo‘lsa aniq sabab. Cloudstream/Zangetsu/Miru/LNReader. |
| P1 | Bounded/cancellable resolver va image prefetch | User chiqishi bilan qolgan ish to‘xtaydi; JS/runtime kuyruq uzunligi limitlanadi; actual device frame time, memory, CPU/thermal trace bilan o‘lchanadi. Wave=3 ni universal optimal deb qabul qilmaslik. |
| P1 | Tracking outbox va source migration | Lokal progress internet bo‘lmasa ham saqlanadi; account/title ID mosligi va pending/error state ko‘rinadi; sync disable/incognito ishlaydi; migration preview chapter mapping va progressni tekshiradi. |
| P1 | Manba diagnostic export | Secrets/cookies/tokenlarsiz runtime versiyasi, failure stage, latency va request ID; foydalanuvchi texnik trace ochmasa oddiy tushunarli sabab ko‘radi. Bu bir necha kod naqshidan chiqarilgan Sozo dizayn taklifi. |
| P2 | EPUB export/TTS va tanlanadigan backup | Export yakunida haqiqiy fayl ochiladi; TTS reader exit’da to‘xtaydi; backup restore library + progress bilan round-trip testdan o‘tadi. |

## Amaliy tekshiruv rejasi

1. Avval Sozo mavjud source/downloader/reader funksiyalarini yuqoridagi qabul mezonlari bilan solishtirish; takror feature yozmaslik.
2. Reproduksiyalar: empty search; 403/Cloudflare; slow provider; bir broken episode; imzo o‘zgargan update; download paytida process kill; offline manga/novel resume; zero/unknown duration; tracker offline/conflict.
3. Emulator va real Android telefonni alohida o‘lchash: bir xil manba/title, bir xil viewport/quality, cold/warm cache. P95 frame time, image decoded memory, active HTTP/JS jobs va device thermal holatini yozish. Bu repolarning mavjudligi yoki kod o‘qishning o‘zi Sozo qizishi sababini isbotlamaydi.
4. Litsenziya/provenance gate’dan keyingina kod qayta ishlatish. Ushbu tadqiqotda upstream ilovalar yig‘ilmadi, ishga tushirilmadi yoki manbalardagi kontent mavjudligi tekshirilmadi.
