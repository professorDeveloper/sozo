# Streaming xizmatlari: Sozo uchun UX va funksiyalar tadqiqoti

Tekshiruv: **2026-09-23**. Qamrov: Netflix, Crunchyroll, Disney+, Prime Video, Plex va Jellyfin. Faqat rasmiy yordam markazlari, mahsulot e’lonlari va SDK hujjatlari ishlatildi. Ilovalarga kirib jonli QA yoki hududiy obuna sinovi bajarilmadi.

**Dalil bilan tasdiqlangan** degani xizmatning rasmiy hujjatida yozilgan; barcha mamlakat/qurilmada sinovdan o‘tgan degani emas. **Sozo taklifi** — quyidagi dalillardan chiqarilgan mahsulot tavsiyasi. Bu fayl Sozo kodini audit qilmaydi va biror funksiya Sozo’da yo‘q deb da’vo qilmaydi. Implementatsiya ustuvorligi mavjud kod auditi bilan solishtirilishi kerak.

Ba’zi Crunchyroll maqolalari ochilganda yordam markazi bosh sahifasiga yo‘naltirdi; ularga oid xulosalar rasmiy domenning qidiruv indeksida qaytgan matni bilan cheklangan. Disney+ sahifalarining hududiy variantlari turlicha; UK va US cheklovlari quyida alohida belgilangan. Tarixiy e’lon sanasi funksiyaning ayni paytdagi barcha platformalarda mavjudligini isbotlamaydi.

## 1. Netflix: shaxsiy kashfiyot va davom ettirish

| Tasdiqlangan imkoniyat | Cheklov yoki muhim tafsilot | Sozo uchun taklif |
|---|---|---|
| Tavsiyalar ko‘rilgan kontent, baholar, janr/aktyor kabi metadata, afzal til va foydalanish signallaridan shakllanadi. Home’da qatorning o‘zi, undagi kontent va tartibi shaxsiylashtiriladi. Boshlang‘ich yoqtirilgan filmlarni tanlash ixtiyoriy. | Bu Netflix modeli haqidagi hujjat; aynan shu algoritm yoki ma’lumotlar Sozo uchun mavjud emas. [Rasmiy tavsiyalar izohi](https://help.netflix.com/en/node/100639). | Avval tushunarli qatorlar: davom ettirish, saqlanganlar, kuzatilayotgan serialning yangi epizodi, tanlangan tilga mos kontent. Tavsiya sababini ko‘rsatish; murakkab AI’dan oldin toza metadata. |
| Continue Watching qatoridan kontentni olib tashlash mumkin. | Qurilmaga mos boshqaruv yo‘li bor. [Yordam](https://help.netflix.com/en/node/115312). | “Davom ettirishdan yashirish”, “boshidan boshlash”, “ko‘rilgan deb belgilash” amallarini aniq ajratish; yashirish tarixni o‘chirish bilan teng bo‘lmasin. |
| Bitta hisobda beshtagacha profil; har birining til, subtitle ko‘rinishi, playback sozlamasi, tarix, tavsiya va My List ma’lumotlari alohida. | Extra member hisobida bitta profil; 2013-yilgacha bo‘lgan qurilmalarda profil cheklovi bor. [Profil hujjati](https://help.netflix.com/hi/node/10421). | Profil chegarasini faqat avatar emas, progress va sozlamalar identifikatori sifatida ko‘rish. |
| Smart Downloads ko‘rilgan epizodni o‘chirib keyingisini yuklaydi; Downloads for You tavsiya qilingan kontentni avtomatik yuklaydi. | Reklamali rejada Smart Downloads mavjud emas. [Smart Downloads](https://help.netflix.com/en/node/122916). | Ixtiyoriy “keyingi N epizod”, Wi-Fi/joy limiti, qo‘lda saqlangan faylni avtomatik o‘chirmaslik. Bu cheklovlar Sozo taklifi, Netflix kafolati emas. |
| Preview autoplay profil sozlamasida o‘chiriladi. | iPad va ayrim eski TV qurilmalarida qo‘llanmaydi. [Autoplay boshqaruvi](https://help.netflix.com/en/node/2102). | Home videopreview’ini foydalanuvchi nazorat qilsin; harakatni kamaytirish rejimi va mobil resurs sarfini hisobga olish. |

Accessibility alohida track va kashfiyot muammosi hamdir: Netflix audio-description mavjudligini detail badge orqali ko‘rsatadi va til bo‘yicha qidirish imkonini beradi; barcha mavsum/epizodda shu track bo‘lishi shart emas. Sozo uchun taklif: oddiy subtitle, SDH/CC, forced subtitle va audio description’ni bir xil “English” yozuvi ostida yo‘qotmaslik; mavjudlikni epizod darajasida ko‘rsatish. [Audio Description](https://help.netflix.com/en/node/25079).

## 2. Crunchyroll: anime oqimini soddalashtirish

Rasmiy yordam Watchlist va Crunchylist’ni alohida kontent saqlash yo‘llari sifatida ko‘rsatadi. Premium foydalanuvchilar bir nechta profil ochishi mumkin. Website qo‘llanmasi individual tavsiyalar, progress, parental controls, keyboard playback shortcuts va subtitle sozlashni tushuntiradi; subtitle tillari serialga qarab o‘zgaradi. [Watchlist/Crunchylist](https://help.crunchyroll.com/hc/en-us/articles/18184740052628-How-do-I-add-shows-to-my-Watchlist-Crunchylist), [profillar](https://help.crunchyroll.com/hc/en-us/articles/25082900277780-Creating-multiple-profiles), [website qo‘llanmasi](https://help.crunchyroll.com/hc/en-us/articles/22728708616852-Getting-started-on-Crunchyroll-website).

Skip Intro opening boshlanganda paydo bo‘ladi. Rasmiy indekslangan hujjat web, iOS, Android, PS4, PS5 va Xbox’ni sanaydi; bundan barcha Smart TV yoki barcha epizodda marker bor degan xulosa chiqmaydi. Sozo taklifi: aniq timing bo‘lsa skip tugmasi; timing yo‘q bo‘lsa oddiy seek. Har bir epizodga taxminiy 90 soniya tashlab ketish tavsiya etilmaydi. [Skip Intro](https://help.crunchyroll.com/hc/en-us/articles/20369940738708-What-is-the-Skip-Intro-feature), [platformalar sanalgan rasmiy variant](https://help.crunchyroll.com/hc/de/articles/20369940738708-Was-ist-die-Funktion-Opening-%C3%BCberspringen).

Offline viewing Mega Fan va Ultimate Fan uchun rasmiy yordamda qayd etilgan. Mahalliy paket nomlari va katalogni umumlashtirmaslik kerak: rasmiy Delta taklif hujjati kontent, subtitr va dub mamlakatga qarab farqlanishini aytadi. Yuklamaning aniq 7/30 kun yoki 48 soat muddati ushbu tekshiruvda ishonchli joriy yordam sahifasi bilan tasdiqlanmadi, shu sabab keltirilmaydi. [Offline rejalari](https://help.crunchyroll.com/hc/en-us/articles/22843839604500-Funimation-End-of-Services), [hudud va til cheklovlari](https://help.crunchyroll.com/hc/en-us/articles/43225989818132-Crunchyroll-Free-Trial-on-Delta-Sync-Wi-Fi).

**Sozo taklifi:** anime detail sahifasida original/dub/sub mavjudligini, mavsum va epizod tartibini ko‘rsatish; tanlangan audio/subtitle afzalligi keyingi epizodga o‘tsin, mavjud bo‘lmasa foydalanuvchiga tushunarli fallback ko‘rsatilsin. Bu UX tavsiyasi; Crunchyroll’dagi barcha til marshrutlari jonli tekshirilmagan.

## 3. Disney+: watchlist, progress va oilaviy boshqaruvni ajratish

Disney+ Watchlist qo‘lda saqlangan kontentdir; tugallanmaganlar Continue Watching’da, avval ko‘rilganlar Watch Again’da bo‘ladi. Watchlist qurilmalar orasida yangilanadi; UK hujjatida uni maxsus guruhlash yoki tartiblash mavjud emasligi aytilgan. **Sozo taklifi:** rejalashtirilgan, boshlangan va tugatilgan kontentni bitta noaniq ro‘yxatga qo‘shmaslik. [Watchlist hujjati](https://help.disneyplus.com/en-GB/article/disneyplus-en-lc-managing-watchlist).

Player’da restart, next episode, 10 soniyalik seek, audio/subtitle va mavjud bo‘lsa audio-description tanlash bor. Continue Watching’dan olib tashlash ham mavjud, lekin barcha mobile/TV qurilmalarda emas; live kontent boshqaruvlari ham cheklangan. Bu “platforma qo‘llaydi” va “shu media qo‘llaydi” farqining amaliy namunasi. [Player controls, 2026-08-24](https://help.disneyplus.com/tr/article/disneyplus-player-controls).

UK hujjatida yettitagacha profil, Junior Mode, kontent reytingi, PIN va yangi profil yaratishni cheklash tasdiqlangan. Reytingdan yuqori kontent browse/search’da yashiriladi, lekin xizmat ichidagi reklama-promolarga bir xil qoida tatbiq etilmasligi aytilgan. **Sozo taklifi:** parental filter faqat detail sahifasida emas, qidiruv, tavsiya va offline kutubxonada ham yagona siyosatga ega bo‘lsin; noma’lum reyting uchun alohida qoida kerak. [Profillar](https://help.disneyplus.com/en-GB/article/disneyplus-en-sk-profiles), [parental controls](https://help.disneyplus.com/en-GB/article/disneyplus-en-lc-parental-controls).

Offline’da sifat va bo‘sh joy ko‘rsatiladi, ommaviy o‘chirish bor. **UK:** Standard/Premium yuklaydi, Standard with Ads yuklamaydi. **US:** Premium va sanab o‘tilgan mos bundle’lar talab qilinadi; TV/computer’da download yo‘q. Ayrim titullar yuklanmaydi; qayta onlayn tekshiruv va obuna holati muhim. Sozo uchun olinadigan tamoyil: “tayyor”, “yarim”, “xato”, “qayta tekshirish kerak” holatlarini ajratish; DRM muddatlarini o‘zboshimchalik bilan nusxalamaslik. [UK downloads](https://help.disneyplus.com/en-GB/article/disneyplus-en-dk-downloads), [US downloads](https://help.disneyplus.com/article/disneyplus-en-mt-downloads), [UK offline muammolari](https://help.disneyplus.com/en-GB/article/disneyplus-en-tw-download-issues).

## 4. Prime Video: kontentga bog‘liq qo‘shimcha ma’lumot va audio qulayligi

X-Ray tanlangan titullarda aktyorlar, musiqa, trivia va bonus kontentni playback yonida beradi. 2018-yilgi e’lon tarixiy ta’rifdir; 2026-09-10 rasmiy e’lon ham X-Ray’dagi Cast/Trivia/Music bo‘limlarini qayd etadi. Undagi yangi Shop funksiyasi US’dagi qo‘llab-quvvatlangan qurilmalar bilan chegaralangan. **Sozo taklifi:** player’dan chiqmasdan qisqa cast/character paneli; faqat mavjud metadata. Sahna vaqtiga bog‘langan trivia mavjud bo‘lmasa uni taxmin qilmaslik. [X-Ray ta’rifi](https://www.aboutamazon.com/news/entertainment/behind-the-scenes-with-x-ray), [2026-yilgi joriy e’lon](https://press.aboutamazon.com/prime-video/2026/9/the-prime-video-shop-the-show-experience-introduces-new-features-and-expands-across-thousands-of-titles).

Dialogue Boost dialogni musiqa/effektga nisbatan kuchaytiruvchi audio variantidir, oddiy umumiy volume emas. 2023-yil e’loni tanlangan Amazon Originals va Medium/High tracklarini tasvirlaydi; keyingi rasmiy izoh ingliz, ispan, fransuz, italyan, nemis, portugal va hind tillarini sanaydi. Bu har bir titulda mavjud degani emas. **Sozo taklifi:** mavjud enhanced-dialogue trackini tushunarli belgilash. Lokal EQ yoki volume gain’ni “Prime Video bilan bir xil AI Dialogue Boost” deb atamaslik. [Ishlash va titul cheklovi](https://www.aboutamazon.com/news/entertainment/prime-video-dialogue-boost), [tillar haqidagi keyingi izoh](https://www.aboutamazon.com/news/entertainment/artificial-intelligence-prime-video-streaming).

Prime Video rasmiy yordamida oltitagacha profil va profil PIN/lock boshqaruvi bor. Bu umumiy sozlamalardan shaxsiy sozlamalarni ajratish uchun yana bir dalil. [Profil boshqaruvi](https://www.primevideo.com/-/id/help?csTools=&nodeId=GYKZXYTPAKNP7UU4). Prime’ning barcha offline yoki ijtimoiy funksiyalari bu tadqiqotda to‘liq tasdiqlanmadi; feature yo‘qligi haqida xulosa chiqarilmaydi.

## 5. Plex: turli manbalarni bitta kutubxona identifikatori ostida ko‘rish

Universal Watchlist turli xizmatlar va Plex serveridagi filmlar/seriallarni yagona ro‘yxatga yig‘adi; detail’da qayerdan ko‘rish mumkinligi, Home’da mavjud saqlangan titullar qatori bor. Server metadata’si Plex Movie/TV Series agentlari bilan moslangan bo‘lishi kerak. Boshqa xizmatda tomosha qilingan kontent avtomatik o‘chadi deb kafolat yo‘q; ayrim clientlar boshqa xizmat ilovasini to‘g‘ridan-to‘g‘ri ocholmaydi. **Sozo taklifi:** canonical media ID va provider havolasini alohida saqlash, mirror almashtirilganda progressni asrash, “mavjud manbalar”ni ko‘rsatish. [Universal Watchlist](https://support.plex.tv/articles/universal-watchlist/).

Plex’da saqlangan titul keyinchalik streaming’da paydo bo‘lsa bildirishnoma turi bor. Lists esa tartiblangan/tartiblanmagan, shaxsiy ko‘rinish sozlamali kolleksiyalar beradi; joriy yordam Android/iOS 2026.4.1+, Roku 9.4.11+ va web Lists sahifasini sanaydi. Managed users uchun Lists yo‘q, ma’lumot Plex cloud’da saqlanadi. **Sozo taklifi:** ixtiyoriy yangi epizod/mavjudlik bildirishnomasi hamda maxfiylik holati aniq ko‘rsatilgan ulashiladigan ro‘yxat. [Notifications](https://support.plex.tv/articles/push-notifications/), [Lists](https://support.plex.tv/articles/lists/).

**Eskirgan taqqoslashdan ehtiyot bo‘lish:** Watch Together sahifasining 2025-02-25 eslatmasi funksiya yangi Plex tajribasiga o‘tayotgan aksar platformalarda tugatilishini, web’da hozircha qolishini aytadi. Pastdagi eski platformalar ro‘yxatini bu eslatmadan ajratib o‘qish noto‘g‘ri. Room/lobby va umumiy seek/play/pause dizayni tarixiy/jarayon namunasi sifatida foydali, barcha joriy ilovalarda feature-parity dalili emas. [Watch Together holati](https://support.plex.tv/articles/watch-together/).

## 6. Jellyfin: moslikni ochiq ko‘rsatish va boshqariladigan birga tomosha

Jellyfin’ning rasmiy codec hujjati container, video, audio va subtitle mos bo‘lsa Direct Play, ayrim nomosliklarda remux/Direct Stream, video nomosligida transcode yo‘lini tushuntiradi. Subtitle burn-in qimmat ish; HDR va codec qo‘llovi client/OS/hardware’ga bog‘liq. **Sozo taklifi:** avtomatik sifat tanlashda faqat “1080p” emas, codec/HDR/audio mosligini ko‘rish; qora ekran yoki fallback sababini diagnostikada ko‘rsatish. Bu Jellyfin serveri bor degan taxmin emas: server transcoding’i Sozo’ga bepul kelmaydi. [Codec support](https://jellyfin.org/docs/general/clients/codec-support/).

Jellyfin 10.10 rasmiy e’loni media segment metadata’si va optional keyframe trickplay generation’ni tasvirlaydi. **Sozo taklifi:** manbada tayyor storyboard/VTT thumbnail bo‘lsa undan foydalanish; yo‘q bo‘lsa demand-driven, cheklangan preview. Telefon playback’i yonida doimiy ikkinchi decoder kerakligi bu manbadan kelib chiqmaydi. [10.10 release](https://jellyfin.org/posts/jellyfin-release-10.10.0/).

SyncPlay joriy sayt va SDK’da mavjud: API group yaratish/join/leave, pause/seek, ping, buffering, ready va ignore-wait amallarini ajratadi. API mavjudligi barcha client UI’da teng qo‘llov degani emas. **Sozo taklifi:** oddiy “hamma bir payt play bossin”dan ko‘ra ready/buffering/reconnect va room boshqaruvini alohida holatlar qilish; manba/epizod identifikatori hamda duration mos kelmasa ogohlantirish. [Jellyfin](https://jellyfin.org/), [SyncPlay SDK](https://kotlin-sdk.jellyfin.org/dokka/jellyfin-api/org.jellyfin.sdk.api.operations/-sync-play-api/index.html).

## 7. Jellyfin rasmiy GitHub kodi: uchta tekshirilgan oqim

Bu bo‘lim README xulosasi emas: quyidagi commitlardagi raw source fayllari o‘qildi. `master` development snapshot bo‘lgani uchun bu kod har bir stable client/server versiyasiga allaqachon chiqqan deb hisoblanmaydi. Kod bajarilmadi yoki build qilinmadi.

- Server: `jellyfin/jellyfin`, SHA `208c278b75abd897aefa1e1175126eac5e4dbfaa`.
- Web client: `jellyfin/jellyfin-web`, SHA `ea73c8bb0fc92628e8baeb5b7c3b0a057def701a`.
- Ikkala repository `LICENSE` fayli GNU GPL Version 2 matnini beradi: [server license](https://github.com/jellyfin/jellyfin/blob/208c278b75abd897aefa1e1175126eac5e4dbfaa/LICENSE), [web license](https://github.com/jellyfin/jellyfin-web/blob/ea73c8bb0fc92628e8baeb5b7c3b0a057def701a/LICENSE). Bu tadqiqot kodni Sozo’ga ko‘chirmadi; litsenziya tavsifi kodga berilgan ruxsatlarni permissive MIT/Apache deb talqin qilish uchun asos emas.

### 7.1 PlaybackInfo: URL’dan oldin capability kelishuvi

Web `getPlaybackInfo` odatiy server yo‘lida `UserId`, `StartTimeTicks`, audio/subtitle index, direct-play/direct-stream ruxsatlari, bitrate va `DeviceProfile`’ni yuborib `getPostedPlaybackInfo` chaqiradi. Local/preset va ayrim audio yo‘llari alohida bo‘lgani uchun “barcha playback shu endpoint’dan o‘tadi” deyilmaydi. Server `POST Items/{itemId}/PlaybackInfo`’da DTO yoki device capability’dan profil oladi, boshlang‘ich pozitsiya va stream ruxsatlarini o‘qiydi. [Web:419–505](https://github.com/jellyfin/jellyfin-web/blob/ea73c8bb0fc92628e8baeb5b7c3b0a057def701a/src/components/playback/playbackmanager.js#L419-L505), [server:116–177](https://github.com/jellyfin/jellyfin/blob/208c278b75abd897aefa1e1175126eac5e4dbfaa/Jellyfin.Api/Controllers/MediaInfoController.cs#L116-L177).

**Sozo uchun xulosa:** stream URL, boshlang‘ich pozitsiya, tanlangan track va decoder capability bir playback request’ning aniq qismlari bo‘lsin. URL topilganini video ko‘rsatildi deb hisoblamaslik. Bu server/client kontraktidan chiqarilgan taklif.

### 7.2 Direct Play → fallback: versiya tanlovi va pozitsiyani asrash

Server `MediaInfoHelper` optimal stream builder natijasidan `SupportsDirectPlay`, `SupportsDirectStream`, `SupportsTranscoding`’ni hosil qiladi, user permission’larini qo‘llaydi va kerak bo‘lsa transcode URL tuzadi. Snapshot’da oddiy HTTP DirectStream uchun maxsus cheklov ham bor; shu sabab umumiy codec jadvali ichki barcha branchlarni to‘liq tasvirlamaydi. [Server helper:227–335](https://github.com/jellyfin/jellyfin/blob/208c278b75abd897aefa1e1175126eac5e4dbfaa/Jellyfin.Api/Helpers/MediaInfoHelper.cs#L227-L335).

Web avval aynan tanlangan item’ning o‘z source’ini yaroqli bo‘lsa saqlaydi; aks holda direct play, direct stream, transcoding tartibida variant izlaydi. Playback xatosida transcode imkoni va avvalgi stream-copy holatini tekshiradi, joriy tick yoki start pozitsiyasidan `changeStream` chaqiradi; direct play o‘chiriladi. Bu cheksiz “o‘sha URL’ni yana ochish” modeli emas. [Source tanlovi:508–541](https://github.com/jellyfin/jellyfin-web/blob/ea73c8bb0fc92628e8baeb5b7c3b0a057def701a/src/components/playback/playbackmanager.js#L508-L541), [retry:3484–3525](https://github.com/jellyfin/jellyfin-web/blob/ea73c8bb0fc92628e8baeb5b7c3b0a057def701a/src/components/playback/playbackmanager.js#L3484-L3525).

**Sozo uchun xulosa:** fallback oldingi xatodan farqli shart bilan bajarilsin va pozitsiyani asrasin. Jellyfin transcoding backend’i mavjud bo‘lmagan provider uchun Sozo “transcode bilan tuzataman” deb va’da bermasligi kerak; mos mirror/codec yoki tushunarli xato kerak.

### 7.3 Progress → resume/completed: faqat millisekund yozish emas

Web progressni stream boshlangan va tugamagan bo‘lsa serverga bildiradi. Server user+item ma’lumotini olib pozitsiya hamda playback settings’ni yangilaydi va `PlaybackProgress` sababi bilan saqlaydi. Stop’da `playbackFailed` bo‘lsa completion hisoblanmaydi. [Web progress:3772–3786](https://github.com/jellyfin/jellyfin-web/blob/ea73c8bb0fc92628e8baeb5b7c3b0a057def701a/src/components/playback/playbackmanager.js#L3772-L3786), [server progress:965–987](https://github.com/jellyfin/jellyfin/blob/208c278b75abd897aefa1e1175126eac5e4dbfaa/Emby.Server.Implementations/Session/SessionManager.cs#L965-L987), [stop:1165–1187](https://github.com/jellyfin/jellyfin/blob/208c278b75abd897aefa1e1175126eac5e4dbfaa/Emby.Server.Implementations/Session/SessionManager.cs#L1165-L1187).

`UserDataManager.UpdatePlayState` minimal resume foizi, maksimal resume foizi va minimal davomiylikdan foydalanadi; yakunlangan deb topilgan holatda resume pozitsiyasini tozalaydi va played holatini yangilaydi. Bu chegaralarning konfiguratsiya qiymatlari shu fayldan universal konstanta sifatida olinmaydi. [Resume siyosati:439–510](https://github.com/jellyfin/jellyfin/blob/208c278b75abd897aefa1e1175126eac5e4dbfaa/Emby.Server.Implementations/Library/UserDataManager.cs#L439-L510).

**Sozo uchun xulosa:** accidental start, resume, completed va failed playback farqli holatlar. Client yopilishi bilan yakunlandi deb qo‘ymaslik; epizod almashishi yoki mirror almashtirish oldingi item progressini buzmasin.

**Yopiq xizmatlar chegarasi:** Netflix, Crunchyroll, Disney+ va Prime Video’ning xususiy production app source kodi tekshirilmagan va unga kirish da’vo qilinmaydi. Ular bo‘yicha yuqoridagi dalil rasmiy public UX/help hujjatlaridir. Plex production kodi ham bu tadqiqotda inspect qilinmadi. Jellyfin’dagi algoritmni boshqa xizmatlarning ichki implementatsiyasi deb ko‘rsatish mumkin emas.

## 8. Sozo kodi auditi bilan solishtirish uchun ustuvor takliflar

Quyidagi tartib — mahsulot bo‘yicha xulosa, xizmatlarda o‘lchangan biznes natijasi yoki Sozo’da aniqlangan yetishmovchilik emas.

| Ustuvorlik | Tekshiriladigan foydalanuvchi natijasi | Qabul mezoni taklifi |
|---|---|---|
| P0 | Ishonchli davom ettirish | Bir titulning manbasi/mirrori almashsa progress yo‘qolmasin; resume, restart, hidden va completed holatlari aralashmasin. |
| P0 | Tushunarli playback va accessibility | Audio/subtitle til, SDH/forced/AD turi bilan ajralsin; codec fallback va mavjud bo‘lmagan variantlar aniq tushuntirilsin; screen reader va TV focus yo‘li tekshirilsin. |
| P0 | Ishonchli offline kutubxona | Yuklama holati, sifat, hajm/bo‘sh joy, retry/cancel va alohida o‘chirish ishlasin; internet uzilganda tayyor kontentni ochish mumkin bo‘lsin. |
| P1 | Anime uchun kamroq takroriy bosish | Next episode til afzalligini saqlasin; Skip Intro faqat ishonchli markerda; autoplay foydalanuvchi boshqaruvida. |
| P1 | Manbalar orasida yagona media kutubxonasi | Canonical ID/provider ID ajratilsin; saqlangan titulning ishlaydigan variantlari ko‘rinsin; noto‘g‘ri match’ni tuzatish mumkin bo‘lsin. |
| P1 | Yengil kashfiyot | Continue/Watchlist/New Episodes qatorlari, til filtri va ixtiyoriy bildirishnoma; avtomatik preview resurs sarfi cheklansin. |
| P2 | Profillar va oilaviy foydalanish | Progress, til, ro‘yxat va kontent cheklovi alohida; offline/search/recommendation’da bir xil siyosat. |
| P2 | Ijtimoiy qatlam | Avval aniq privacy’li ro‘yxat ulashish; SyncPlay keyinroq, ready/buffering/reconnect holatlari va bir xil kontent tekshiruvi bilan. |

AI recap, avtomatik dubbing, commerce overlay yoki sahna bo‘yicha AI metadata bu dalillardan kelib chiqib birinchi navbatga qo‘yilmaydi: ularga kontent huquqi, mavjud data va alohida sifat sinovi kerak. UI’ni nusxalashdan oldin progress, identifikatsiya, capability va download holatlari to‘g‘ri bo‘lishi yuqoridagi tavsiyalarning asosiy bog‘liqligidir.
