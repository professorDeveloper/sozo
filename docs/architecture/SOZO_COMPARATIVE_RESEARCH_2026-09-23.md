# Sozo: raqobatchilar, GitHub implementatsiyalari va rivojlantirish ustuvorliklari

Tekshiruv sanasi: **2026-09-23**. Asosiy xulosa: Sozo uchun eng katta foyda source tanlashdan boshlab playback/o‘qish, progress, offline va tiklashgacha bo‘lgan oqimni ishonchli qilishdan keladi. Hozirgi kodda ko‘plab funksiyalar mavjud; quyidagi reja ularni qayta yozish emas, aniqlangan chegaralarni yopishga qaratilgan.

## Qamrov va dalil chegarasi

Sozo mobil ishchi daraxti, tegishli Android hostlari va backendning tanlangan account/catalog qismlari o‘qildi. Ishchi daraxtda oldindan mavjud commit qilinmagan o‘zgarishlar bor: **kodda mavjud** degani **release’da tekshirilgan** degani emas.

Cloudstream, Aniyomi, Zangetsu, Stremio, Miru, Mihon, LNReader, Jellyfin, MediaKit, AndroidX Media3 va Dantotsu’ning alohida continuation loyihasida tanlangan haqiqiy implementatsiya oqimlari o‘qildi. GitHub havolalari o‘qilgan commitga bog‘langan. Barcha repositorylarning har bir satri o‘qilgani da’vo qilinmaydi. Netflix, Crunchyroll, Disney+, Prime Video va Plex uchun rasmiy ommaviy hujjatlar ishlatildi; ularning xususiy production kodi tekshirilmagan.

Tadqiqot tarkibi:

- [Sozo funksiyalari va aniq kod dalillari](SOZO_FEATURE_INVENTORY_2026-09-23.md).
- [Cloudstream, Aniyomi, Zangetsu, Stremio, Miru va boshqa GitHub loyihalari](OPEN_SOURCE_MEDIA_RESEARCH_2026-09-23.md).
- [Mihon va LNReader: backup, migration, download kodlari](READER_CODE_PATTERNS_2026-09-23.md).
- [Netflix va boshqa xizmatlar; Jellyfin playback kodi](STREAMING_SERVICES_RESEARCH_2026-09-23.md).

Bu tekshiruvda production kodi o‘zgartirilmadi, qurilma ma’lumoti o‘chirilmadi, build/test yoki jonli source uptime sinovi bajarilmadi. Samsung S22 Ultra’dagi qora ekran/qizishning yakuniy sababi static koddan tasdiqlanmaydi.

## 1. Sozo’da allaqachon bor imkoniyatlar

| Yo‘nalish | Hozirgi holat | Keyingi foydali ish |
|---|---|---|
| Source katalogi va qo‘shish | SourcesHub ichida SourceCatalogPage, qidiruv/til/ecosystem/type filtrlar, installer bor | Tanlash, o‘rnatish, faollashtirish va diagnostika ma’nolarini soddalashtirish |
| Runtime’lar | Cloudstream, Aniyomi, manga native hostlari; Mangayomi/LNReader JS yo‘llari | Platforma va extension compatibility’ni oldindan ko‘rsatish; arbitrary Dart/APK qo‘llovini va’da qilmaslik |
| Player | Native, MediaKit, external; sifat/mirror, subtitle, AniSkip, PiP, sleep, preview mavjud | Qurilmaga mos tanlov, first-frame dalili, xatodan progressni saqlab chiqish |
| Manga va novel | Image reader va prose yo‘llari, chapter navigation/progress/typography mavjud | Source almashganda continuity, o‘qish tezligi va xato sabablarini tekshirish |
| Offline | Video/manga/novel; HTML va EPUB export, pause/resume/retry, joy boshqaruvi | Partial natijalar, kill/restart va failed-only retry mezonlarini mustahkamlash |
| Download siyosati | Wi-Fi, cooldown va storage headroom bor | Keyingi N epizod/chapter, followed-title auto-enqueue, charging/schedule siyosati |
| Tracking | AniList va MAL, manual title links, history/incognito bor | Har tracker uchun durable pending progress va xato ko‘rinishi |
| Discovery | Home/search/cross-search, genre, calendar/upcoming, follow va notification bor | Tilga mos discovery, sababli tavsiyalar, dublikat identity’ni boshqarish |
| Watch party | Room/control/reconnect, chat va reaction bor | Buffering/ready, noto‘g‘ri episode/duration va persistent history chegaralarini tekshirish |
| Cast/TV | Chromecast, TV pairing/remote bor | Capability aniqligi; AirPlay/DLNA alohida yangi ish |
| Account | Auth/profile edit/private lists/app lock bor | Household profile va parental rating siyosati alohida data modeli talab qiladi |
| Stats | Kundalik/provider bo‘yicha watched seconds, streak/trivia bor | Mavjud yozuvlar oralig‘i bilan halol recap; oldingi yillarni taxmin qilmaslik |
| Backup | Oltita Hive box export/import qilinadi | Native source/repo sozlamalari va restore coverage to‘liq emas |

Batafsil fayl yo‘llari inventar hisobotida berilgan. `docs/ROADMAP.md`dagi marketplace, watch-party chat/reaction va Wi-Fi download’ni kelajak funksiyasi sifatida ko‘rsatgan bandlar eskirgan. Novel offline/EPUB ham hozirgi kodda mavjud.

## 2. Qaysi loyihadan nima o‘rganildi

| Loyiha | Haqiqiy o‘qilgan mexanizm / rasmiy dalil | Sozo’ga mos xulosa |
|---|---|---|
| Cloudstream | Plugin version/status/load-unload; queue, range/HLS resume | Source lifecycle va transfer bosqichlarini aniq model qilish |
| Aniyomi | APK signature/trust/API compatibility; progress; cheklangan download-ahead | Trust, runtime mosligi va installed holatini alohida ko‘rsatish |
| Zangetsu | Search/playback health, resolver budget, reading flush, partial page download | Har operation bo‘yicha health va chegaralangan source ish hajmi |
| Stremio | HTTP addon resource kontrakti, seek/time-watched, library push/pull | Runtime ortida umumiy capability va canonical media identity |
| Miru | Eski Flutter runtime hamda yangi Go metadata/downloader | Bir oiladagi turli avlod kodini aralashtirmaslik; queue lifecycle |
| Mihon | Backup validate/restore, chapter migration, source-aware refresh | Tekshiriladigan backup, xavfsiz migration, per-source concurrency |
| LNReader | Tanlanadigan archive, prose migration, checkpoints, TTS session | Novel anchor/settings, qisman download, TTS lifecycle |
| Jellyfin | DeviceProfile/PlaybackInfo, direct-play/fallback, resume/completion | Codec/track mosligi, pozitsiyani saqlaydigan fallback |
| Netflix | Profil, Continue Watching, tavsiyalar, Smart Downloads | Shaxsiy progress, keyingi kontentga kam bosish, offline siyosat |
| Crunchyroll | Anime list/profil, subtitle/intro oqimlari | Dub/sub afzalligi va episode continuity |
| Disney+ | Profil/parental va accessibility bo‘yicha rasmiy UX | Rating siyosatini barcha ko‘rinishlarda bir xil qo‘llash |
| Prime Video | X-Ray, Dialogue Boost, profil boshqaruvi | Mavjud audio variantini to‘g‘ri nomlash, cast metadata |
| Plex | Universal Watchlist, lists, availability notifications | Source URL’dan mustaqil media kutubxonasi |

Har bir bandning aniq rasmiy yoki commitga bog‘langan manbasi yuqoridagi qo‘shimcha hisobotlarda mavjud. Netflix Smart Downloads reklama rejimida mavjud emas; Plex Watch Together yangi clientlarda tugatilayotgan, web’da qolgan deb rasmiy sahifa qayd etadi. Bularni barcha qurilmalar uchun universal imkoniyat deb ko‘rsatish noto‘g‘ri.

### Ko‘r-ko‘rona ko‘chirilmasligi kerak bo‘lgan kod

- Zangetsu health kommentariyasi timeout/blocked haqida bir narsani aytadi, bajariluvchi switch esa faqat hard error’ni dead qiladi. Sozo uchun typed failure va expiry siyosati mustaqil aniqlanishi kerak.
- Mihon migration’ida eng yuqori read chapter’gacha hammasi read bo‘lishi mumkin; foydalanuvchi tashlab ketgan chapterlar shunda noto‘g‘ri belgilanadi.
- LNReader migration’i eski novel’ni keyingi chapter/settings yozuvlari tugashidan oldin olib tashlaydi. Sozo copy/verify/commit va recovery yo‘lini talab qilishi kerak.
- LNReader checkpoint failed chapter’dan keyin ham oldinga yuradi; checkpoint mavjudligi automatic failed-only retry degani emas.
- Miru yangi core’dagi `novel.go` faqat package deklaratsiyasi. Feature nomi tayyor implementatsiya dalili emas.
- Asl Dantotsu GitHub’da HTTP451 qaytargani sabab mustaqil continuation alohida belgilandi; asl upstream o‘qilgan deb ko‘rsatilmaydi.

## 3. Player: qora ekran va qizishga tegishli kod dalillari

MediaKit snapshoti `c533e446755f51cf53c7e57aea873f2aa5355f81` Android controller’ida surface size yangilangandan keyin `waitUntilFirstFrameRenderedCompleter` tugatiladi. Bu signalni ekranga haqiqiy video pikseli chizildi deb qabul qilish yetarli emas. Emulator uchun hardware decoding tanlovi ham alohida. [Android controller kodi](https://github.com/media-kit/media-kit/blob/c533e446755f51cf53c7e57aea873f2aa5355f81/media_kit_video/lib/src/video_controller/android_video_controller/real.dart#L100-L155).

AndroidX Media3 snapshoti `8c6678b657ede1e7883fc164ef73ed483c7796c3` haqiqiy `onRenderedFirstFrame` va `onDroppedVideoFrames` analytics eventlarini beradi. Renderer fallback pastroq prioritetli decoder’ga initialization failure’dan so‘ng o‘tishi mumkin; u sekinroq bo‘lishi mumkin va barcha qora ekranlarni davolaydigan switch emas. Track selector’da maksimal resolution va bitrate chegaralari mavjud. [Analytics](https://github.com/androidx/media/blob/8c6678b657ede1e7883fc164ef73ed483c7796c3/libraries/exoplayer/src/main/java/androidx/media3/exoplayer/analytics/AnalyticsListener.java#L1235-L1315), [fallback](https://github.com/androidx/media/blob/8c6678b657ede1e7883fc164ef73ed483c7796c3/libraries/exoplayer/src/main/java/androidx/media3/exoplayer/DefaultRenderersFactory.java#L205-L220), [track policy](https://github.com/androidx/media/blob/8c6678b657ede1e7883fc164ef73ed483c7796c3/libraries/exoplayer/src/main/java/androidx/media3/exoplayer/trackselection/DefaultTrackSelector.java#L1050-L1082).

**Sozo uchun taklif:** bitta playback request’da URL/headers, codec/HDR/audio, sifat, start position va subtitle afzalligi saqlansin. Auto/Balanced/Battery/Maximum kabi siyosatlar faqat o‘lchangan capability asosida ishlasin. Fallback sababini ko‘rsatsin, pozitsiyani saqlasin, cheksiz takrorlanmasin. Renderer signalini ko‘ra olmaydigan engine’da bu cheklov diagnostikada ochiq bo‘lsin; position/dimensions yolg‘iz muvaffaqiyat dalili bo‘lmasin.

S22 Ultra uchun keyingi tekshiruv matritsasi: bir xil stream’ning H.264/HEVC, SDR/HDR, 720p/1080p/yuqori variantlari mavjud bo‘lsa; cold/warm start; native/MediaKit; resume va mirror switch; uzoqroq playback. First-frame latency, dropped frames, buffer ratio, CPU/memory va thermal holat o‘lchanadi. Emulator natijasi real telefon dalili o‘rnini bosmaydi. Hozir barcha quality’ni pasaytirish yoki engine’ni majburiy almashtirish uchun yetarli sabab aniqlangani da’vo qilinmaydi.

## 4. Ustuvor backlog va qabul mezonlari

P0 — asosiy foydalanish/data ishonchliligi; P1 — mavjud imkoniyatni tugallash; P2 — keyingi mahsulot kengayishi. S/M/L nisbiy murakkablik bahosi, muddat va’dasi emas.

| Navbat | Ish | Hozirgi bo‘shliq yoki taklif | Tayyorlik mezoni | Hajm |
|---|---|---|---|---|
| P0 | Source UX | Tanlash/install/browse/runtime atamalari og‘ir | Media turi → til → mos source; aniq installed/selected holat; immediate chip feedback | M |
| P0 | Playback recovery | Qora ekran real qurilmada hal qilingani isbotlanmagan | First-frame/dropped-frame dalili; bounded retry; progress/track saqlanishi; S22 sinovi | L |
| P0 | Backup coverage | Native repo SharedPreferences oltita Hive export’iga kirmaydi | Versioned manifest; section validation; toza fixture’da restore; skipped hisobot | M |
| P0 | Tracker outbox | Player once-per-episode guard; failure jim qoladi | Tracker/account/media bo‘yicha durable pending; retry/dedup; visible failure | M |
| P0 | Source diagnostika | Barcha runtime/provider teng ishlamaydi | Search/detail/stream/pages alohida health; empty ≠ dead; blocked/timeout sababli action | M |
| P1 | Migration | Alternate source service bor; to‘liq data migration alohida | Match preview; chapter/episode mapping; unmatched saqlanadi; copy/verify/commit | L |
| P1 | Smart downloads | Wi-Fi/cooldown bor; automation to‘liq emas | Opt-in next N; source budget; joy limiti; waiting reason; qo‘lda saqlangan fayl himoyasi | M |
| P1 | Manga samaradorligi | Device bo‘yicha o‘lchash kerak | Bounded decoded image cache/prefetch; headers/cookies; chapter switch cancellation | M |
| P1 | Novel TTS | Qidirilgan kodda topilmadi | Play/pause/next; paragraph anchor; sleep; chiqishda stop; til/voice mavjudligi | M |
| P1 | Source katalog cache | Repository ataylab app cache ishlatmaydi | Last-known sana; offline label; eskirgan health’ni fresh deb ko‘rsatmaslik | S |
| P1 | Trakt | AniList/MAL bor, Trakt client topilmadi | App/OAuth shartlari; movie/episode identity; outbox; account switch isolation | L |
| P2 | Jellyfin | First-class adapter topilmadi | Server login/library/PlaybackInfo; direct/transcode capability; resume | L |
| P2 | Household profiles | Account profile bor, alohida household scope yo‘q | History/list/settings/download scope; parental policy search/offline’da ham | L |
| P2 | Named lists | Watch Later/Watched fixed kinds bor | Nomlangan list; privacy/share; keyin collaboration | M |
| P2 | Watch party mustahkamligi | Chat/reactions bor | Ready/buffering/reconnect; duration/content mismatch; history talabi aniq | M |
| P2 | Recap | Daily/provider stats bor | Data boshlanish sanasi ochiq; haqiqiy total; mavjud bo‘lmagan tarixni yaratmaslik | M |
| P2 | Accessibility | Subtitle/track boshqaruvi bor | SDH/forced/AD farqi; TalkBack/focus; reduced motion; contrast | M |
| P2 | Cast kengayishi | Chromecast bor | AirPlay/DLNA uchun alohida platforma va header/DRM sinovi | L |

Tracker topilmasi aniqlashtirildi: `anilist_service.dart`dagi `reportProgress()` xatoda `false` qaytaradi; player bu delivery natijasiga durable retry biriktirmaydi. Servislardagi `pendingChanges()` esa **manual title link/unlink** sync’i; episode progress outbox borligini isbotlamaydi. Boshqa barcha retry tizimlari yo‘q deb umumlashtirilmaydi.

Trakt’ning rasmiy [OAuth](https://docs.trakt.tv/reference/auth) va [scrobble](https://docs.trakt.tv/reference/about-scrobble) kontraktlari integratsiya uchun asos. App yaratish, limit va joriy hisob shartlari implementatsiya oldidan tekshiriladi. Letterboxd’da [request-only API](https://letterboxd.com/api-beta/) va [write scope’lar](https://api-docs.letterboxd.com/) bor; “API umuman yo‘q” noto‘g‘ri. Ruxsatsiz to‘liq sync va’da qilinmasin; import/export alohida baholansin.

## 5. Source ekranining tavsiya etilgan oqimi

**O‘rnatilgan manbalar:** Watch / Manga / Novels tablari asosiy navigatsiya. Qidiruv va category qatori scroll bilan mos yig‘iladi; sarlavhani ulkan expanded qilish talab qilinmaydi. Tab va tegishli category sticky bo‘lishi, kontent ustiga yopilmasligi tekshiriladi. Bosilgan chip darhol selected bo‘ladi; natijalar yangilanishi alohida loading holati. Eski request natijasi yangi tanlovni bosib ketmasin.

**Source qo‘shish:** media turi va til boshlang‘ich filtr; kartada source nomi, til, qo‘llaydigan content va qurilmaga moslik. Cloudstream/Aniyomi kabi texnik kelib chiqish ikkilamchi tafsilot. Tugma holatlari “Qo‘shish → Yuklanmoqda → O‘rnatildi → Ochish”; source tanlashni install tugmasiga yashirmaslik. Mos kelmasa sabab va mumkin bo‘lgan keyingi amal ko‘rinadi.

**Source ishlamasa:** “Bu source ishlamaydi” o‘rniga bosqich: qidiruv, detail, episode resolve yoki page fetch. “Qayta urinish”, kerak bo‘lsa “Saytni ochish”, “Boshqa source’da topish”. Bir title xatosi butun source’ni doimiy bloklamasin. Alternativga o‘tishdan oldin progress/chapter mosligi preview ko‘rsatiladi.

**Source migration:** eski manba va tarix saqlanadi → yangi title/chapters olinadi → moslik tekshiriladi → foydalanuvchi match’ni tuzatadi → yangi holat yoziladi → eski nusxani almashtirish faqat yakunda. Chapter nomi yoki raqami yetarli bo‘lmasa taxminiy match ochiq belgilanadi.

## 6. Yetkazish ketma-ketligi va o‘lchovlar

1. Backup coverage va diagnostika asosini qurish; keyingi xatolarni data yo‘qotmasdan tekshirish.
2. Source UI feedback hamda playback readiness/recovery; real telefon va emulator natijalarini alohida yozish.
3. Durable tracker sync va migration; offline/restart/account switch holatlari.
4. Smart queue va manga/novel resource budget; keyin TTS/Trakt kabi yangi foyda.
5. Jellyfin, profillar, lists va recap’ni foydalanuvchi ehtiyoji asosida tanlash.

O‘lchovlar: source o‘rnatishdan birinchi muvaffaqiyatli ochishgacha bosishlar; chip feedback kechikishi; search cancellation’dan keyingi active jobs; first-frame p50/p95; stall/drop; o‘qishda frame time va decoded image memory; restore coverage; pending tracker update yoshi; partial download recovery. Avval baseline, keyin maqsad belgilanadi; ushbu tadqiqot hech qanday benchmark sonini o‘lchangan deb bermaydi.

Netflix’dagi AI yoki Prime’dagi scene metadata’ni qo‘shish uchun kerakli data/track mavjudligi alohida baholanadi. Oddiy EQ’ni Dialogue Boost deb, cast ro‘yxatini scene-aware X-Ray deb atamaslik kerak. Source katalogi, chat va EPUB kabi mavjud funksiyalarni yangidan taklif qilishdan saqlanish uchun inventar roadmap bilan birga yangilanadi.

## 7. Litsenziya va yakuniy chegaralar

GitHub hisobotida har repo LICENSE’iga havola mavjud: Cloudstream/Zangetsu GPLv3, Aniyomi/Mihon Apache2, Stremio/LNReader MIT, Miru AGPLv3, Jellyfin repo fayllari GPLv2; tekshirilgan Dantotsu continuation custom shartlarga ega. [MediaKit MIT](https://github.com/media-kit/media-kit/blob/c533e446755f51cf53c7e57aea873f2aa5355f81/LICENSE), [Media3 Apache2](https://github.com/androidx/media/blob/8c6678b657ede1e7883fc164ef73ed483c7796c3/LICENSE). Bu ro‘yxat avtomatik litsenziya mosligi xulosasi emas; kod/assets import qilinsa tegishli fayl va dependency shartlari tekshiriladi. Ushbu tadqiqot implementatsiya g‘oyalarini tavsiya qiladi, tashqi kodni Sozo’ga ko‘chirmaydi.

Aniq aniqlangan statik bo‘shliqlar: backup coverage, player tracker delivery holati, runtime/platform chegaralari, katalog offline cache yo‘qligi. Takliflar: xavfsiz migration, capability-based playback, smart automation, TTS, Trakt, personal server/profillar. Runtime isboti talab qiladigan masalalar: S22 qora ekran/qizish, barcha source’lar, novel/manga haqiqiy sayt javoblari, notification/cast va release sifati.

## 8. Eng oxirgi holat qayta tekshirildi: HEAD `1196278`

Foydalanuvchining keyingi so‘roviga ko‘ra mobil kod yana o‘qildi. Bu tekshiruvda tracked fayllar clean; yuqoridagi dastlabki inventardagi commit qilinmagan o‘zgarishlar haqidagi izoh o‘sha tekshiruv vaqtiga tegishli. Research fayllari va oldindan mavjud transcript/probe fayllari untracked. Remote bilan tenglik tekshirilmadi.

Aniqlashtirishlar:

- `sources_hub_page.dart:543` dan `_hub()` oddiy Column ichida AppTabBar, hint, search, AnimatedSize/SourceScopeMenu va Expanded/TabBarView ishlatadi. Haqiqiy swipe bor. Umumiy header scroll bilan collapse qilinmaydi; foydalanuvchi so‘ragan tab/category coordinator harakati shu joyda hali alohida ish.
- Source qidiruvida 200 ms debounce va tab cache bor. `source_catalog_page.dart:359` type tanlovini request’dan oldin `setState` qiladi. `_generation` eski natijani rad qiladi. Shuning uchun “selected style network javobini kutadi” deb hozirgi kodga tashxis qo‘yish noto‘g‘ri; sezilayotgan sekinlik frame profiling bilan tekshiriladi.
- `search/data/source_health_store.dart`da lokal/remote health, TTL, slow/broken budget va muvaffaqiyatli play bo‘yicha ranking mavjud. Yangi health tizimini noldan qo‘shish kerak emas; operation-specific sabablar va foydalanuvchiga recovery ko‘rsatishni shu tizimga ulash kerak.
- `media_controller.dart:565–654` readiness timeout/surface yo‘qligida Android native fallback qiladi va headers’ni uzatadi. Emulator routing ham mavjud. Qolgan muammo: surface signalining haqiqiy rendered pixels kafolati emasligi. Fallback umuman yo‘q deyilmaydi.
- `theme_controller.dart` Material You palitrasini olib, accent’ni saqlaydi; appearance accent qatori yangilangan. Home uchun alohida genres sahifasi mavjud.
- `watch_services_bloc.dart` qurilma locale country’sidan region oladi va bo‘sh lineup uchun fallback qiladi. Bu haqiqiy jismoniy joylashuv yoki foydalanuvchining obuna mamlakatini kafolatlamaydi. Streaming service katalogi Netflix akkauntidagi videoni bevosita o‘ynatish integratsiyasi emas.
- `chapter_groups.dart` volume yoki chapter range bo‘yicha original indekslarni saqlab guruhlaydi; reader chapter filter’i mavjud. Group/search’ni yangi funksiya deb taklif qilish kerak emas.
- Player’da start-paused va mahalliy subtitle tanlash, download’da cooldown amalda bor.
- Backup olti Hive box bilan cheklanganicha; player tracker dispatch shared once-per-episode va fire-and-forget holatida. Bu ikkala ustuvor topilma qayta tasdiqlandi.
- Trakt, household profile va TTS implementatsiyasi qidirilgan lib daraxtida topilmadi. Jellyfin nomi default repo description’da borligi first-class server adapter mavjudligini isbotlamaydi.

Qayta tekshiruvdan keyingi tartib: (1) source header/selection UX va profiling; (2) haqiqiy qurilmada playback reliability; (3) backup/outbox; (4) xavfsiz manga/novel migration va offline recovery; (5) mavjud queue ustida smart automation; (6) TTS/Trakt; (7) Jellyfin/profillar/recap. Bu navbat implementatsiya rejasi, bajarilgan fixlar ro‘yxati emas.
