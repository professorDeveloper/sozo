# Sozo — tarqatish bo'yicha ish ro'yxati

Sozo texnik jihatdan kuchli: torrent, Chromecast, watch party, live TV, shorts,
DRM, shaderlar, olti platforma. Bu hujjat kod haqida emas — **loyihani odamlar
qanday topishi** haqida, chunki bugun eng zaif bo'g'in shu.

Raqamlar GitHub API dan o'lchangan (hujjat oxirida takrorlash buyrug'i bor).

---

## 1. Reliz chastotasi

Bugungi holat: **111 kunda 4 ta reliz**, median oraliq 40 kun.

Nima uchun bu yulduzga to'sqinlik qiladi:

- **Reliz = signal.** Har bir reliz Watch qilganlarga xabar, "Recently updated"
  ro'yxatlariga chiqish va Telegram/Discord'ga yuboriladigan yangilik. Oyiga
  bir marta reliz — oyiga bitta signal.
- **Tirik loyiha ko'rinishi.** Yangi kelgan odam birinchi Releases sahifasini
  ochadi. "Oxirgi reliz: 5 kun oldin" bilan "6 hafta oldin" — bu ikki xil
  qaror. Ikkinchisida loyiha tashlab qo'yilganga o'xshaydi.
- **Yuklab olish o'zi tarqaladi.** Har bir yuklab olgan odam potensial yulduz,
  Telegram a'zosi va do'stiga aytuvchi.

**Nishon: haftada bir reliz.** Katta feature kutilmaydi — bitta xato tuzatilsa
ham reliz. Versiya `3.1.1`, `3.1.2` bo'lib ketaversin.

Bu endi arzon: reliz workflow'i GitHub Release'ni **avtomatik** cheradi
(`.github/workflows/release.yml` → `publish` job). Ilgari qo'lda edi, va
shuning uchun 4 relizdan 3 tasi fayl biriktirilmagan holda qolgan.

---

## 2. Reliz izohlari

Commit ro'yxati emas, foydalanuvchi tilida. Farqi:

❌ `Refactored MediaController, fixed audio track probing`
✅ **Video 38 soniya kutdirardi — endi darrov boshlanadi.** Sabab: hech kim
so'ramagan audio yo'llarni tekshirib turgan.

Qoidalar:
1. **Foydalanuvchi tilida**, kod tilida emas
2. **Aniq raqam.** "Tezlashtirildi" ishonchsiz; "38 soniyadan" ishonarli
3. **Oldin/keyin.** Nima buzuq edi va endi qanday
4. **Guruhlangan:** Yangi / Yaxshilandi / Tuzatildi
5. Boshida **bir jumlalik xulosa** — relizni bir qatorda sotadi

Bunday izoh Reddit va Telegram'ga o'zi ko'chiriladi. "Bug fixes and
improvements" hech qayerga ko'chirilmaydi.

Workflow `notes` inputini oladi va Release body'ning tepasiga qo'yadi.

---

## 3. Repo metadata — 2 daqiqa, eng katta ROI

Repo'ning `description` va `topics` maydonlari **bo'sh**. Ya'ni Sozo GitHub
qidiruvida `anime app`, `flutter streaming`, `android tv` kabi so'rovlarda
**umuman chiqmaydi**.

```bash
gh repo edit professorDeveloper/sozo \
  --description "Free, open-source app for movies, series, anime, manga and light novels — Android, Android TV, iOS, Windows, Linux and macOS." \
  --homepage "https://sozo.framer.website/" \
  --add-topic anime --add-topic anime-app --add-topic manga \
  --add-topic light-novel --add-topic movies --add-topic streaming \
  --add-topic flutter --add-topic flutter-app --add-topic android-tv \
  --add-topic dart --add-topic cross-platform --add-topic media-player
```

---

## 4. Ikkiga bo'lingan repo

Ikkita tirik repo bor:

| Repo | Yulduz |
|---|---:|
| `professorDeveloper/sozo` | 57 |
| `Sozo-app/sozo` | 16 |

73 yulduz ikkiga bo'lingan — GitHub trendingda 57 va 73 juda boshqa narsa. Va
yangi kelgan odam qaysi biri haqiqiy ekanini bilmaydi.

**Qilinadigan ish:** bittasini kanonik deb tanlash. Tashkilot repo'si uzoq
muddatga to'g'riroq — brend shaxsdan ajraladi, keyinchalik hamkorlar qo'shish
oson. Ikkinchisining README'sini bitta qatorga qisqartirib, kanonikka
yo'naltirish va **arxivlash** (o'chirish emas — eski havolalar ishlab tursin).

> README'dagi "Star The Project" tugmasi noto'g'ri repoga ishora qilardi —
> tuzatildi. Qaysi repo kanonik bo'lishiga qarab bittadan almashtirish kerak.

---

## 5. Bajarilganlar

| Ish | Holat |
|---|---|
| LICENSE (GPL-3.0) | ✅ |
| README qayta yozildi + Disclaimer | ✅ |
| CONTRIBUTING / CLA / AI_POLICY | ✅ |
| Issue shablonlari (4 ta, jumladan "manba ishlamayapti") | ✅ |
| PR shabloni, FUNDING | ✅ |
| GitHub Release avtomatlashtirildi — `Sozo-v3.1.0-arm64-v8a.apk`, universal, TV, SHA256SUMS | ✅ |
| CI (analyze + test + tarjima + Android build) | ✅ |
| Provider health CI — kunlik, yiqilsa issue ochadi | ✅ |
| Repo description + topics | ⬜ §3 |
| Kanonik repo tanlash | ⬜ §4 |
| Haftalik reliz ritmi | ⬜ §1 |
| Reddit'da bo'lish (`r/animepiracy`, `r/androidapps`, `r/FlutterDev`) | ⬜ |

`r/FlutterDev` alohida qiziq: bitta kodda olti platforma, headless WebView JS
dvigateli, ikkita pleyer dvigateli — bu o'sha subreddit uchun mos post mavzusi
va **hissa qo'sha oladigan** odamlarni olib keladi.

---

## Raqamlarni o'lchash

```bash
curl -s "https://api.github.com/repos/professorDeveloper/sozo/releases?per_page=100" | python3 -c "
import sys,json,datetime
r=json.load(sys.stdin)
ds=sorted(datetime.date.fromisoformat(x['published_at'][:10]) for x in r)
gaps=[(ds[i+1]-ds[i]).days for i in range(len(ds)-1)]
print(len(r),'reliz | median',sorted(gaps)[len(gaps)//2],'kun | yuklab olish',
      sum(sum(a['download_count'] for a in x['assets']) for x in r))"
```
