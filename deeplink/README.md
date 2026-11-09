# Deeplink fayllari — joylash

Hozir `sozo.azamov.me/detail?url=...` ochilganda **GitHub Pages 404** chiqyapti
chunki:
1. `.well-known/assetlinks.json` (Android) yo'q — Android App Links tasdiqlanmaydi
2. `.well-known/apple-app-site-association` (iOS) yo'q — iOS Universal Links ham
3. `/detail` URL'iga hech qanday HTML yo'q — brauzer 404 ko'rsatadi

Tuzatish uchun ushbu papkadagi 3 ta faylni `sozo.azamov.me` hostiga
joylash kerak.

## Variant A — GitHub Pages repo'siga qo'shish (eng tezi)

`sozo.azamov.me` qaysi GitHub repo'siga ulangan bo'lsa, shu repo'ning **root**
papkasiga quyidagi tartibda qo'ying:

```
your-repo/
  .well-known/
    assetlinks.json
    apple-app-site-association
  detail/
    index.html        ← ushbu papkadagi detail.html nusxasi
  play/
    index.html        ← bir xil mazmunda
```

`detail/index.html` `?url=...` parametrini o'qib, mavjud bo'lsa ilovani
`sozo://detail?url=...` orqali ochishga harakat qiladi. Ilova
o'rnatilmagan bo'lsa, foydalanuvchi tugmalar orqali do'konga o'tadi.

**Diqqat:** `apple-app-site-association` faylining nomida `.json` kengaytma
**bo'lmasligi** kerak (Apple shu qoidaga ega). GitHub Pages'da `Content-Type`
avtomatik `application/octet-stream` qo'yiladi — ishlaydi. Agar muammo
bo'lsa, repo root'da `_headers` (Netlify) yoki `vercel.json` qo'shing.

Push qilganingizdan keyin:
```
curl -s https://sozo.azamov.me/.well-known/assetlinks.json
curl -s https://sozo.azamov.me/.well-known/apple-app-site-association
```
Ikkalasi ham JSON qaytarishi kerak.

## Variant B — Backend nginx orqali (DNS o'zgartirish kerak)

Sozo backend'iga statik fayllar serverini qo'shing:

`nginx/nginx.conf` ichidagi `server { ... }` blokiga (boshqa `location`
qatorlari yonida) qo'shing:

```nginx
location = /.well-known/assetlinks.json {
    default_type application/json;
    return 200 '<bu yerda assetlinks.json mazmuni bir qator qilib>';
}

location = /.well-known/apple-app-site-association {
    default_type application/json;
    return 200 '<bu yerda fayl mazmuni bir qator qilib>';
}

location ~ ^/(detail|play)(/.*)?$ {
    default_type text/html;
    return 200 '<detail.html mazmuni>';
}
```

So'ng `sozo.azamov.me` DNS yozuvini backend'ning IP'siga yo'naltirish kerak
(GitHub Pages dan olib tashlash).

## Mobil tomonni qayta sinash

1. Yangi APK o'rnatilgandan keyin Android quyidagini avtomatik tekshiradi:
   `https://sozo.azamov.me/.well-known/assetlinks.json`. Agar JSON to'g'ri
   bo'lsa, link tap qilinganda darhol ilova ochiladi.
2. iOS uchun: `apple-app-site-association` tasdiqlanishi uchun ilova
   qayta o'rnatilishi yoki qurilma qayta yuklanishi kerak.
3. Telegram'da `https://sozo.azamov.me/detail?url=...` linkini yuborib,
   tap qiling. Endi GitHub Pages 404 emas, **Sozo ilovasi** ochilishi
   kerak.
4. Agar ilova o'rnatilmagan bo'lsa, fallback HTML (`detail.html`)
   "Sozo'da ochish" tugmasini va do'kon linklarini ko'rsatadi.

## App Store link

`detail.html` ichida iOS App Store URL'i hozircha `id0000000000` —
haqiqiy `id...` ni ilova chiqqach almashtiring.

## `/play` links (for sozo-web)

The app now reads these parameters on `/play` (and `/detail`):

| Param | Meaning |
|---|---|
| `url` | content URL (required) |
| `provider` | source id; used for this navigation only, never saved as the current source |
| `ep` | episode number as shown to the viewer (1-based), `/play` only |
| `t` | start position in seconds (`95`, `1:35` and `1m35s` are all accepted), `/play` only |

Example: `https://sozo.azamov.me/play?url=…&provider=hdrezka&ep=12&t=754`

The web fallback page for `/play` (and `/detail`) must forward the **whole**
query string to `sozo://play…`, not only `url`. `detail.html` in this folder
does that now; the copy deployed by the sozo-web repo needs the same change.
`apple-app-site-association` already lists `/play` and `/play/*`.
