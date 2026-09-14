# Sozo source, manga va novella UX auditi

**Tuzatishlar holati:** [FIXES.md](FIXES.md). Quyidagi ro‘yxat dastlabki auditdagi holatni tasvirlaydi.

Sana: **2026-09-14, Asia/Tashkent**. Tekshirilgan: `sozo`, source katalogiga xizmat qiluvchi `sozo-backend`, qo‘shimcha `sozo-tv`.

## Natija

Source o‘qilmasligi faqat tashqi sayt yoki extension eskirganidan emas. Sozo’ning o‘zida **source topish/o‘rnatish**, **ro‘yxat va platforma holati**, **rasm/matnni readerga uzatish**, **o‘qish boshqaruvi**, **update va tiklash** bosqichlarida alohida muammolar bor. Eng katta foydalanuvchi ta’siri — mavjud manga/novellani topolmaslik, boshqa indeksni o‘rnatish, noto‘g‘ri bobga o‘tish va o‘qish joyini yo‘qotish.

Bu hisobotda **27 ta asosiy nosozlik**, **2 ta alohida UX kamchiligi**, TV bo‘yicha qo‘shimcha topilmalar yozilgan. Bir xil ildiz sababdan chiqqan yaqin alomatlar birlashtirildi. Har bir topilmaning isbot darajasi ko‘rsatilgan; barcha tashqi source’lar ishlamasligi yoki hamma qurilmada bir xil natija chiqishi da’vo qilinmaydi.

**Production kod o‘zgartirilmadi.** Audit fayllari, fixture testlari va loglar qo‘shildi. Sozo mobile boshlang‘ich HEAD: `964784226d7d00c37359182295cce18be9c678c6`. TV HEAD: `52b4b06ea9eb0e604c0f7591b04f05a9e46c4e96`, lekin unda oldindan mavjud uncommitted o‘zgarishlar bor; TV xulosalari tekshirilgan working tree’ga tegishli.

### Dalil belgilari

- **W** — haqiqiy Flutter widget yoki Bloc ishga tushirildi; tarmoq/settings chegaralarida fixture ishlatildi.
- **F** — production mapper/store/backend moduliga deterministik input berildi; natija tekshirildi.
- **L** — tashqi birlamchi repo indeksidan joriy read-only HTTP javobi olindi.
- **S** — aniq kod oqimi tasdiqlangan, ammo Android qurilmada shu holat qayta ijro qilinmagan.
- **UX** — ko‘rinadigan imkoniyat/yo‘l yo‘qligi; avtomatik ravishda crash yoki backend bugi deb hisoblanmaydi.

**P1** — asosiy topish/o‘rnatish/o‘qish yo‘lini bloklaydi yoki noto‘g‘ri kontentga olib boradi. **P2** — muayyan rejim, manba, update yoki tiklash holatida nosozlik/noqulaylik.

## Eng avval tuzatilishi kerak bo‘lgan zanjir

1. **Manga/novella ro‘yxatiga yetib borish:** S01, S02, S03, S04, S06.
2. **Kontentni to‘g‘ri o‘qish:** S13, S15, S16, R01, R02.
3. **O‘qilgan joy va offline va’dasini saqlash:** R03–R07.
4. **Yangilash/tiklashda eski ishlaydigan holatni yo‘qotmaslik:** S07–S12.

Bu tartib — audit xulosasi; ushbu ish doirasida tuzatish kiritilmadi.

## A. Source topish va o‘rnatish

### S01 · P1 · Manga/Novella tab tanlanadi, lekin ro‘yxat o‘zgarmaydi — W

**Qadam:** Sources sahifasida Video’dan Manga’ga o‘tish. **Natija:** Manga indikatori tanlanadi, body’da Video source qoladi. Widget testi Manga qatori ko‘rinmaganini tasdiqladi. Novella ham shu controller/body yo‘lidan foydalanadi.

**Sabab:** `AppTabBar(controller: _tabs)` chaqiruvida `onChanged` yo‘q, parent state’da tab listener ham yo‘q. Ro‘yxat `_tabs.index`ni faqat o‘zining keyingi rebuild’ida o‘qiydi. Foydalanuvchi keyin qidiruvga yozsa yoki Bloc yangilansa ro‘yxat birdan o‘zgarishi mumkin; bu source tasodifan paydo bo‘lgandek ko‘rinadi.

Kod: [SourcesHub tab wiring](/Users/azamov/Sozo-Full/sozo/lib/features/sources/presentation/pages/sources_hub_page.dart:179), [body](/Users/azamov/Sozo-Full/sozo/lib/features/sources/presentation/pages/sources_hub_page.dart:291). Test: `HUB-01`.

### S02 · P1 · Katalogdan novella tanlanganda manga indeksi o‘rnatiladi — F

**Qadam:** backend katalogidagi Mangayomi novella yoki anime source uchun Add repo bosish. **Natija:** katalog qatori source kelgan sibling indeksga emas, asosiy `index.json`ga bog‘langan. Tanlangan novella o‘rniga manga source’lari kelishi mumkin.

**Sabab:** harvester `repo.url`, `animeUrl`, `novelUrl`ni alohida o‘qiydi, lekin barcha qatorlarga `repoUrl: repo.url` yozadi. Mobile faqat shu bitta URL’ni o‘rnatadi. Bu tavsiya reposini uchala URL bilan o‘rnatadigan boshqa sahifadagi yo‘ldan farq qiladi.

Kod: [siblinglarni o‘qish](/Users/azamov/Sozo-Full/sozo-backend/src/services/catalogIngest.service.js:213), [URL’ni yo‘qotish](/Users/azamov/Sozo-Full/sozo-backend/src/services/catalogIngest.service.js:268), [mobile install](/Users/azamov/Sozo-Full/sozo/lib/features/extensions/presentation/pages/source_catalog_page.dart:197). Probe: `novel_install_targets_manga_index` — actual `index.json`, expected `novel_index.json`.

### S03 · P1 · Katalog “o‘rnatildi” deydi, picker/Sources eski holatda qoladi — W

**Qadam:** Source Catalog orqali muvaffaqiyatli repo qo‘shib, oldingi source ro‘yxatiga qaytish. **Natija:** `_install` faqat snackbar chiqaradi; `ProviderLoad` yubormaydi. O‘rnatilgan source keyingi umumiy reload/restartgacha ko‘rinmasligi mumkin. Testda install bir marta bajarildi, reload eventlari soni **0**.

Kod: [catalog install](/Users/azamov/Sozo-Full/sozo/lib/features/extensions/presentation/pages/source_catalog_page.dart:184). Taqqoslash: [Mangayomi installer reload qiladi](/Users/azamov/Sozo-Full/sozo/lib/features/extensions/presentation/pages/mangayomi_sources_page.dart:70). Test: `CAT-01`.

### S04 · P1 · Sozo backend uzilsa, mustaqil JS manga/novellalar ham yashiriladi — F

**Qadam:** internet va source sayti ishlaydi, lekin Sozo provider API javob bermaydi. **Natija:** `ProviderLoaded.offline=true` bo‘lganda `my:` source `isUsable=false`. Sources, quick picker va qidiruv ro‘yxati undan foydalanmaydi.

**Sabab:** `isServerIndependent` faqat `cs:`, `an:`, `mn:`ni taniydi. Mangayomi esa o‘z indeks/kod/saytiga bevosita boradi. Bu yerda “offline” butun internet yo‘q degani emas, Sozo backend holatidir.

Kod: [provider capability](/Users/azamov/Sozo-Full/sozo/lib/features/profile/domain/entities/provider_entity.dart:83), [usable filtering](/Users/azamov/Sozo-Full/sozo/lib/features/profile/presentation/bloc/provider_state.dart:36). Test: `OFFLINE-01` — expected true, actual false.

### S05 · P2 · Source tili Bloc’da yo‘qoladi — W

**Qadam:** til berilgan extension ro‘yxati ProviderBloc’ga keladi. **Natija:** fixture’dan `lang: fr` keldi, yakuniy ProviderEntity’da `lang: ''`. Manga, Aniyomi va Cloudstream append konstruktorlarida ham `lang` uzatilmagan.

**Ta’sir:** bir xil nomdagi turli tildagi source’larni ajratish qiyin; language filter bo‘sh tilni “hamma tilga mos” deb qabul qiladi. `ProviderModel.fromJson` tilni qo‘llashi bu yo‘lni tuzatmaydi, chunki Bloc qo‘lda konstruktor chaqiryapti.

Kod: [Mangayomi mapping](/Users/azamov/Sozo-Full/sozo/lib/features/profile/presentation/bloc/provider_bloc.dart:277), [Manga mapping](/Users/azamov/Sozo-Full/sozo/lib/features/profile/presentation/bloc/provider_bloc.dart:238), [language match](/Users/azamov/Sozo-Full/sozo/lib/core/extensions/source_language.dart:29). Test: `LANG-01`.

### S06 · P1 · Manga discovery haqiqiy protobuf katalogi o‘rniga “Outdated App” qatorlarini ko‘radi — S + L

**Qadam:** katalog harvester’i manga `index.pb` reposini o‘qiydi. **Natija:** `.pb` manzili majburan `index.min.json`ga o‘zgartiriladi. Audit paytida Keiyoushi `.pb` — HTTP 200, gzip **106364 bayt**; JSON esa ikki placeholder: “Outdated App”, “Update to Mihon 0.20.1+”. Yuzono JSON ham shunday ikki qator qaytardi, `.pb` esa 404 edi.

**Ta’sir:** qurilma parseri qo‘llaydigan manga katalogi server discovery’sida yo‘q yoki noto‘g‘ri ko‘rsatiladi. Placeholder qatorlaridagi `id=1` ham backend externalId kalitida to‘qnashadi. Barcha repo endpointlari doim shunday qoladi degan xulosa emas; sanali javoblar saqlangan.

Kod: [protobuf almashtirish](/Users/azamov/Sozo-Full/sozo-backend/src/services/catalogIngest.service.js:232). Dalil: [live javoblar](repros/backend_catalog_live.json). Birlamchi manbalar: [Keiyoushi JSON](https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json), [Keiyoushi protobuf](https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.pb).

### S07 · P1 · Bitta sibling indeks vaqtincha ishlamasa, bor source katalogdan chiqariladi — F

**Qadam:** manga sibling o‘qiladi, novella sibling HTTP xato beradi. **Natija:** harvester xatoni yutib, root repo uchun ko‘rilmagan barcha qatorlarni `dead=true` qiladi. Shunday qilib mavjud novella discovery’dan yo‘qoladi. Malformed HTTP 200 indeksda ham bo‘sh natija bilan butun repo qatorlari o‘chirilgan deb belgilanishi mumkin.

Kod: [xatoni yutish](/Users/azamov/Sozo-Full/sozo-backend/src/services/catalogIngest.service.js:221), [dead sweep](/Users/azamov/Sozo-Full/sozo-backend/src/services/catalogIngest.service.js:284). Probe: `failed_novel_index_still_marks_unseen_repo_rows_dead`, `malformed_200_index_marks_entire_catalog_repo_dead`.

## B. Runtime, update va kontent ma’lumoti

### S08 · P2 · Repo/fork almashtirilganda eski JS kod bajarilishi mumkin — F

**Qadam:** A repo’dan source kodi cache qilinadi; B repo ayni ID va versiya bilan boshqa `sourceCodeUrl` beradi. **Natija:** metadata B, executable kod esa A. Kod cache’i ID+versiyani tekshiradi, origin’ni emas. Source’ni tuzatish uchun fork o‘rnatish kutilgan natijani bermasligi mumkin.

Kod: [code cache](/Users/azamov/Sozo-Full/sozo/lib/features/extensions/data/mangayomi_repo_store.dart:190). Dalil: [runtime test](repros/mangayomi_audit_test.dart).

### S09 · P2 · Retired yoki Dart’ga o‘tgan source update’dan keyin ham qoladi — F

**Qadam:** muvaffaqiyatli yangi indeks oldingi JS source’ni olib tashlaydi yoki Dart-only qiladi. **Natija:** `addRepo` eski map’dan boshlanadi; yo‘qolgan ID o‘chmaydi, Dart entry skip bo‘lsa eski JS entry qoladi. Broken source tanlanadigan bo‘lib qoladi; oddiy Update reconciliation qilmaydi.

Kod: [merge](/Users/azamov/Sozo-Full/sozo/lib/features/extensions/data/mangayomi_repo_store.dart:119). Dalil: actual store + lokal HTTP fixture.

### S10 · P2 · Native manga repo’ni xato paytda qayta qo‘shish saqlangan source’larni o‘chiradi — S

**Qadam:** o‘rnatilgan manga repo’ni internet/index xatosi paytida qayta add qilish. **Natija:** fetch exception → bo‘sh JSONArray → o‘sha repo metadata’sini bo‘sh qiymat bilan overwrite. In-memory ro‘yxat vaqtincha qolishi mumkin, restart’dan keyin yo‘qoladi. Alohida `checkUpdates` fetch xatolarini skip qiladi; finding aynan add/re-add yo‘liga tegishli.

Kod: [fetch fallback](/Users/azamov/Sozo-Full/sozo/android/app/src/main/kotlin/com/soplay/sozo/manga/MangaRepoManager.kt:138), [persist](/Users/azamov/Sozo-Full/sozo/android/app/src/main/kotlin/com/soplay/sozo/manga/MangaRepoManager.kt:202).

### S11 · P2 · Native manga update’da yangi source ID restartdan keyin yo‘qoladi — S

**Qadam:** APK update yangi source ID chiqaradi. **Natija:** host uni xotiraga registratsiya qiladi, lekin persisted array’da faqat oldindan mavjud ID’lar almashtiriladi; yangi ID append qilinmaydi. Shu sessiyada bor source keyingi start’da yo‘q. Removed ID’lar esa metadata’da qoladi.

Kod: [update persistence](/Users/azamov/Sozo-Full/sozo/android/app/src/main/kotlin/com/soplay/sozo/manga/MangaRepoManager.kt:292).

### S12 · P2 · Native APK load muvaffaqiyatsiz bo‘lsa, ayni path uchun Retry qayta yuklamaydi — S

**Qadam:** APK load/instantiate muvaffaqiyatsiz; keyin ayni path’dagi source qayta so‘raladi. **Natija:** path load’dan oldin `loadedApks`ga yozilgan; keyingi chaqiruv load’ni skip qiladi. `evictSources` source cache’ni tozalaydi, APK markerini emas. Yangi versiya boshqa filename bersa bu shartdan chiqadi; oddiy retry/reimport doim chiqmaydi.

Kod: [runtime load marker](/Users/azamov/Sozo-Full/sozo/android/app/src/main/kotlin/com/soplay/sozo/manga/MangaRuntime.kt:79), [eviction](/Users/azamov/Sozo-Full/sozo/android/app/src/main/kotlin/com/soplay/sozo/manga/MangaRuntime.kt:49).

### S13 · P2 · Mangayomi rasm headerlari sahifalar orasida aralashadi — F

**Qadam:** extension ikki rasmga turli Authorization/headerlar beradi. **Natija:** bridge bitta umumiy map’ni qayta yozib, oxirgi sahifa headerlarini hamma sahifaga beradi. Fixture’da PAGE_1 o‘rniga PAGE_2 credential ketdi. Bundan tashqari extension `getHeaders` methodi bu yo‘lda chaqirilmaydi.

**Ta’sir:** ayrim manga rasm requestlari extension kutgan UA/Referer/credential bilan bormaydi. Bu aniq ma’lumot yo‘qolishi; barcha source’da jonli 403 kuzatilgan degani emas. Native MangaImageServer boshqa yo‘l bo‘lib, uni shu finding bilan aralashtirmaslik kerak.

Kod: [page mapper](/Users/azamov/Sozo-Full/sozo/lib/features/extensions/data/mangayomi_bridge.dart:449). Haqiqiy source shartnoma misollari va test: [runtime hisobot](MANGAYOMI_MANGA_AUDIT.md).

### S14 · P2 · Bir source’ning nomi boshqa source detail’iga tushadi — F

**Qadam:** ikki source `/series/1` kabi bir xil relative link, lekin turli nom qaytaradi; keyin birinchisining detail’i nom bermaydi. **Natija:** detail provider `my:one`, title esa ikkinchi source’dan “Novel Two”.

**Sabab:** title fallback cache faqat link bilan kalitlangan, source ID bilan emas. Cross-source qidiruvdan keyin detail/tarix noto‘g‘ri nom olishi mumkin.

Kod: [title cache](/Users/azamov/Sozo-Full/sozo/lib/features/extensions/data/mangayomi_bridge.dart:33). Dalil: actual bridge fixture replay.

### S15 · P1 · Annas Archive uchun EPUB funksiyalari yo‘q — F

**Qadam:** standart novel indeksidagi Annas Archive source’ning detail yoki bobini ochish; fixture’da mirror muvaffaqiyatli yechilgan. **Natija:** o‘zgartirilmagan source metodlari `ReferenceError: parseEpub is not defined` va `ReferenceError: parseEpubChapter is not defined` beradi.

**Sabab:** source EPUB parsing’ni hostdan kutadi, Sozo JS bridge esa bu ikki global funksiyani bermaydi. Index source’ni oddiy JS novella deb taklif qilishi uning host imkoniyatlariga mosligini tekshirmaydi. EPUB helper qo‘shilmaguncha yoki source supported deb ko‘rsatilishi cheklanmaguncha bu oqim ishlamaydi. PDF haqida shunday jonli/shartnoma finding topilmadi.

Kod: [host globals](/Users/azamov/Sozo-Full/sozo/assets/js/mangayomi_bridge.js:547), [novella dispatch](/Users/azamov/Sozo-Full/sozo/lib/features/extensions/data/mangayomi_bridge.dart:409). Birlamchi source: [annasarchive.js](https://raw.githubusercontent.com/entityJY/mangayomi-extensions-eJ/main/javascript/novel/src/all/annasarchive.js). Dalil: [o‘zgartirilmagan source replay](repros/default_novels_probe.cjs).

### S16 · P1 · Novel Updates boblar so‘rovi noto‘g‘ri body formatida yuboriladi — F

**Qadam:** standart Novel Updates source’ning `getDetail` metodi boblar uchun WordPress POST chaqiradi. U `application/x-www-form-urlencoded` va `action=nd_getchapters`, `mygrr`, `mypostid` obyektini beradi. **Natija:** Sozo bridge obyektni JSON.stringify qiladi. Form decoder’da `action=null`, chunki HTTP header form deydi, body esa JSON.

**Ta’sir:** boblarni so‘raydigan action/ID serverning form maydonlariga tushmaydi. To‘g‘ri login cookie bo‘lsa ham encoding xatosi qoladi. Test DOM/HTTP fixture bilan o‘tkazilgan; remote login yoki saytning joriy availability’si tekshirilmagan.

Kod: [object body serialization](/Users/azamov/Sozo-Full/sozo/assets/js/mangayomi_bridge.js:116), [body forwarding](/Users/azamov/Sozo-Full/sozo/lib/core/js/dart_fetch.dart:249). Birlamchi source: [novelupdates.js](https://raw.githubusercontent.com/entityJY/mangayomi-extensions-eJ/main/javascript/novel/src/en/novelupdates.js). Dalil: [request replay](repros/default_novels_probe.cjs).

## C. Manga va novella reader

### R01 · P1 · Ikki sahifali manga rejimida resume va boshqaruv buzilgan — W

**Qadam:** landscape, horizontal+spread, 9 sahifali bobni `resumePage=5` bilan ochish. **Natija:** reader cover/slot 0’da turadi, counter esa `6/9`. ArrowRight bosilganda `PageController is not attached to a PageView` assertion chiqadi. Tap zone va slider ham shu `_goToPage` yo‘lidan foydalanadi.

**Sabab:** spread view `_spreadController`ni mount qiladi, navigation/resume `_pageController`ni boshqaradi. Debug assertion butun release app albatta crash bo‘ladi degan da’vo emas; controller ulanishi noto‘g‘ri ekanligi aniq.

Kod: [controller](/Users/azamov/Sozo-Full/sozo/lib/features/manga/presentation/pages/reader_page.dart:66), [navigation](/Users/azamov/Sozo-Full/sozo/lib/features/manga/presentation/pages/reader_page.dart:322), [spread view](/Users/azamov/Sozo-Full/sozo/lib/features/manga/presentation/pages/reader_page.dart:668).

### R02 · P1 · Novellada PageDown/Space keyingi o‘qilmagan bobga sakraydi — W

**Qadam:** uzun novella bobining boshida PageDown bosish. **Natija:** matn scroll bo‘lishi o‘rniga provider chaqiruvlari `one → two`; bob almashtiriladi. Space/ArrowDown ham shu yo‘l. Horizontal preference bo‘lsa edge tap ham shu muammoga boradi.

**Sabab:** umumiy `_nextPage` rasm soniga qaraydi; novellada rasmlar 0. Novel HTML vertical scroll’da bo‘lsa ham input handler buni ajratmaydi.

Kod: [next-page](/Users/azamov/Sozo-Full/sozo/lib/features/manga/presentation/pages/reader_page.dart:334), [keyboard](/Users/azamov/Sozo-Full/sozo/lib/features/manga/presentation/pages/reader_page.dart:430).

### R03 · P2 · Novella progress’i `1/0`, seek slider ishlamaydi — W

**Qadam:** HTML bob muvaffaqiyatli ochilgan. **Natija:** pastki bar `1/0` ko‘rsatadi, slider disabled. Ichkarida `_novelPermille` bor, lekin bar faqat image page count’dan foydalanadi. O‘qish holati noto‘g‘ri ko‘rinadi va matnda tez joy tanlash yo‘q.

Kod: [bottom bar](/Users/azamov/Sozo-Full/sozo/lib/features/manga/presentation/pages/reader_page.dart:1278), [counter](/Users/azamov/Sozo-Full/sozo/lib/features/manga/presentation/pages/reader_page.dart:1341).

### R04 · P2 · Novella Download tugmasi faol, ammo hech narsa qilmaydi — W

**Qadam:** ochilgan novella bobida download ikonkasini bosish. **Natija:** enqueue soni 0, foydalanuvchiga izoh ham yo‘q. Kod `_pages.isEmpty` bo‘lsa darhol qaytadi. HTML uchun offline saqlash yo‘li bu amalda yo‘q.

Kod: [button/early return](/Users/azamov/Sozo-Full/sozo/lib/features/manga/presentation/pages/reader_page.dart:894), [download transfer](/Users/azamov/Sozo-Full/sozo/lib/features/download/data/datasources/download_transfer_data_source.dart:386).

### R05 · P2 · Diskda joy yo‘q bo‘lsa ham “download boshlandi” deyiladi — W

**Qadam:** manga download repository `EnqueueOutcome.noSpace` qaytaradi. **Natija:** UI success “download_started” xabarini chiqaradi. `refused`, `notDownloadable`, `alreadyPresent` outcome’lari ham readerda ajratilmagan.

**Sabab:** enqueue natijasi tashlab yuborilgan. Foydalanuvchi bob offline bo‘ladi deb kutadi, lekin u queue’ga olinmagan.

Kod: [enqueue va success](/Users/azamov/Sozo-Full/sozo/lib/features/manga/presentation/pages/reader_page.dart:907).

### R06 · P2 · Downloads’dan qayta ochilgan bob o‘qilgan joyga qaytmaydi — S

**Qadam:** offline bobni qisman o‘qib, Downloads yoki Home Downloads’dan yana ochish. **Natija:** ikki navigation joyi ham ReaderArgs’ga `resumePage` bermaydi; default 0. Reader o‘zi history’dan qayta izlamaydi. Oldingi progress bor bo‘lsa ham boshidan ochiladi.

Kod: [Downloads entry](/Users/azamov/Sozo-Full/sozo/lib/features/download/presentation/pages/downloads_page.dart:305), [Home Downloads entry](/Users/azamov/Sozo-Full/sozo/lib/features/home/presentation/widgets/home_downloads_section.dart:138), [default args](/Users/azamov/Sozo-Full/sozo/lib/features/manga/domain/entities/reader_args.dart:21).

### R07 · P2 · Bob almashtirish pending o‘qish progress’ini saqlash chegarasi emas — W

**Qadam:** sahifa/scroll holatini o‘zgartirib 800 ms ichida boshqa bobga o‘tish yoki keyingi bob load’i xato berishi. **Natija:** eski bob kontenti va page state saqlashdan oldin tozalanadi. Muvaffaqiyatli load debounce’ni yangilaydi; xatoda esa save uchun kontent qolmaydi. Eski bobning oxirgi joyi yo‘qolishi mumkin.

Widget replay’da birinchi bob `2/9`ga o‘tkazildi, 250 ms ichida boshqa bob tanlandi, 900 ms kutildi. Eski bob history’si baribir page 0 bo‘lib qoldi; ikkinchi bob saqlandi.

Kod: [load reset](/Users/azamov/Sozo-Full/sozo/lib/features/manga/presentation/pages/reader_page.dart:170), [debounced save](/Users/azamov/Sozo-Full/sozo/lib/features/manga/presentation/pages/reader_page.dart:290), [chapter navigation](/Users/azamov/Sozo-Full/sozo/lib/features/manga/presentation/pages/reader_page.dart:340).

Readerning batafsil triggerlari, widget natijalari va ijobiy nazoratlar: [READER_FINDINGS.md](READER_FINDINGS.md).

## D. Qolgan katalog nosozliklari

### C01 · P2 · Til filtri xatosi muvaffaqiyatli source ro‘yxatini ham yopadi — W

`/catalog/sources` muvaffaqiyatli, `/catalog/languages` xato bo‘lganda butun sahifa error holatiga o‘tadi. `Future.wait` ikki natijani majburiy bog‘lagan. Filter chiplarisiz katalogni ishlatish mumkin bo‘lgan holatda ham foydalanuvchi hech narsa tanlay olmaydi.

Kod: [parallel load](/Users/azamov/Sozo-Full/sozo/lib/features/extensions/presentation/pages/source_catalog_page.dart:114). Test: `CAT-02`.

### C02 · P2 · Keyingi sahifa xatosidan keyin tugamaydigan spinner — W

Page 2 fetch’i xato bilan tugaydi, `_loadingMore=false`, lekin `_hasMore=true` qoladi va oxirgi row doim spinner chizadi. Retry/error holati yo‘q. Foydalanuvchi server hali javob berishini kutadi, aslida request tugagan.

Kod: [catch](/Users/azamov/Sozo-Full/sozo/lib/features/extensions/presentation/pages/source_catalog_page.dart:165), [footer](/Users/azamov/Sozo-Full/sozo/lib/features/extensions/presentation/pages/source_catalog_page.dart:309). Test: `CAT-03`.

### C03 · P2 · Cloudstream discovery va qurilma parseri bir xil indekslarni tushunmaydi — F

Backend faqat `pluginLists` obyektidan yuradi; native qo‘llaydigan direct plugin array’dan 0 qator oladi. Backend author `status=0` qilgan pluginni ham katalogga chiqaradi, qurilma parseri esa bunday pluginni filtrlaydi. O‘rnatilishi kutilgan qator keyingi bosqichda kelmasligi mumkin.

Kod: [Cloudstream ingest](/Users/azamov/Sozo-Full/sozo-backend/src/services/catalogIngest.service.js:160). Probelar: `cloudstream_direct_plugin_array_ignored`, `cloudstream_status_down_listed`.

### C04 · P2 · Eski Mangayomi indeksining JS belgisi server va mobile’da turlicha talqin qilinadi — F

`sourceCodeLanguage` bo‘lmagan entry mobile’da JS deb qabul qilinadi, serverda `jsRuntime=false`. Katalog install tugmasini o‘chirishi mumkin, bevosita repo install esa qabul qiladi. Bu supported input shaklidagi moslik farqi; qancha jonli source ta’sirlangani o‘lchanmadi.

Kod: [server](/Users/azamov/Sozo-Full/sozo-backend/src/services/catalogIngest.service.js:108), [mobile](/Users/azamov/Sozo-Full/sozo/lib/features/extensions/domain/entities/mangayomi_source.dart:127).

## E. Sof UX kamchiliklari

### U01 · Source ichida qidirish va katalogni davom ettirish yo‘li yetishmaydi — UX

Sources’dan ochilgan source view faqat birinchi home rail’larini ko‘rsatadi. Source-specific search, pagination yoki View all action yo‘q. Kerakli manga birinchi ro‘yxatda bo‘lmasa, source’ni global “Use source” qilish va boshqa qidiruv sahifasiga o‘tish kerak. Bu inline browse va’dasini to‘liq bajarmaydi.

Kod: [SourceBrowseView](/Users/azamov/Sozo-Full/sozo/lib/features/sources/presentation/pages/sources_hub_page.dart:449), [rail](/Users/azamov/Sozo-Full/sozo/lib/features/sources/presentation/pages/sources_hub_page.dart:523).

### U02 · Bo‘sh Manga tab foydalanuvchini native manga katalogiga olib bormaydi — UX

Manga va Novella empty-state Add source ikkalasi Mangayomi sahifasiga yo‘naltiriladi. Android’dagi native Manga/Mihon katalogi alohida umumiy Sources sozlamasi ostida qoladi. Keng manga ekotizimini izlagan foydalanuvchi kamroq JS variantlarini butun taklif deb tushunishi mumkin. Novella uchun JS yo‘li to‘g‘ri; ikkala rejimni bir xil yo‘naltirish manga uchun tanlovni yashiradi.

Kod: [empty installer routing](/Users/azamov/Sozo-Full/sozo/lib/features/sources/presentation/pages/sources_hub_page.dart:129), [native manga entry](/Users/azamov/Sozo-Full/sozo/lib/features/profile/presentation/pages/sources_page.dart:69).

## F. TV va video ekotizimlari

TV uchun [alohida qo‘shimcha](TV_FINDINGS.md) bor. Muhimlari: Aniyomi Update APK kodini yangilamaydi; offline refresh saved source’larni bo‘shatadi; buzilgan Cloudstream update oldingi ishlaydigan versiyani yo‘qotishi mumkin; Cloudstream settings/login entry yo‘q; search failure “hech narsa topilmadi” bilan aralashadi. Bular Android playback testi emas, static oqim tekshiruvi sifatida belgilangan.

Oldingi arxitektura tekshiruvida mobile Cloudstream tashqi `audioTracks`ni native JSON’da bersa ham Dart video modeli saqlamasligi va remote bridge methodlari native bilan teng emasligi ham topilgan. Bu auditda ularning yangidan jonli playback reproduksiyasi bajarilmadi: [oldingi hisobot](../../../architecture/CLOUDSTREAM_ZANGETSU_ANIYOMI_RESEARCH.md).

## Tekshiruvni qayta bajarish

`sozo` papkasidan:

```sh
flutter test --no-pub docs/audits/2026-09-14/source-reader/repros/source_hub_catalog_audit_test.dart --reporter expanded
flutter test --no-pub docs/audits/2026-09-14/source-reader/repros/reader_audit_test.dart --reporter expanded
flutter test --no-pub docs/audits/2026-09-14/source-reader/repros/mangayomi_audit_test.dart --reporter expanded
node docs/audits/2026-09-14/source-reader/repros/backend_catalog_audit.cjs
node docs/audits/2026-09-14/source-reader/repros/default_novels_probe.cjs
```

- **source_hub_catalog:** 6 kutilgan xulq assertion’i qizil — buglar qayta ko‘rindi. Test compile bo‘ladi; xatolar aynan expected/actual farqi.
- **reader:** 6 characterization test o‘tdi. Ular mavjud noto‘g‘ri xulqni tasdiqlaydi; yashil bo‘lishi feature tuzaldi degani emas. Oddiy swipe uchun ijobiy nazorat ham bor.
- **mangayomi:** 5 test — 4 noto‘g‘ri xulq reproduksiyasi va 1 ishlaydigan novel routing nazorati.
- **backend:** production modul ustida 6 isolated probe; fixture DB/network, production DB’ga yozilmaydi.
- **default novels:** 5 ta standart script haqiqiy Sozo JS shim’da instantiate qilindi; Annas Archive va Novel Updates shartnoma xatolari qayta olindi. HTTP/DOM fixture, production saytga login qilinmadi.
- Mavjud `novel_text`, `spread_slots`, `content_mode`, `source_language`, `source_failure` fayllaridagi **54 test o‘tdi**; log [existing_checks.log](repros/existing_checks.log). Ular kichik helperlar to‘g‘riligini tekshiradi, yuqoridagi widget/adapter bog‘lanishlarini to‘liq qamramaydi.

Dalillar: [hub/catalog log](repros/source_hub_catalog_run.txt), [reader log](repros/reader_audit_test.log), [backend probe natijalari](repros/backend_catalog_audit.json), [birlamchi HTTP natijalari](repros/backend_catalog_live.json).

Haqiqiy ReaderPage fixture screenshot’i: [novella matni ochilgan, pastda 1/0](screenshots/novel-zero-pages.png). Bu emulator build’i emas, Flutter widget rendering’i.

## Bug deb hisoblanmagan holatlar va qolgan chegaralar

- `itemType=2 → getHtmlContent` va HTML string-array birlashtirish ishladi. “Sozo umuman novella matnini ochmaydi” degan xulosa noto‘g‘ri.
- Oddiy horizontal manga swipe ishladi; ustidagi tap detector uni bloklaydi degan taxmin rad etildi.
- Reader stale chapter response’larini load token bilan tekshiradi; eski response yangi bobni bosib ketadi degan finding qo‘shilmadi.
- Native manga proxy extension HTTP/cookie yo‘lini saqlaydi. Hamma native rasmda cookie yo‘qoladi degan finding yo‘q.
- Mangayomi Dart extensionlari ushbu runtime’da qo‘llanmasligi — ma’lum capability chegarasi, avtomatik JS parse bugi emas.
- Live indeks mavjudligi kontent/rasm/stream ijrosi ishlashini isbotlamaydi. Real APK’lar bo‘yicha har bir source/site/country holati va barcha Android/iOS/Windows qurilmalarida QA hali qilinmagan.
- TV manga/novella reader ekotizimi bilan mobile darajasida teng emas; anime APK’ni manga reader sifatida yuklash va’dasi bu kodda yo‘q.
