# Sozo'ga hissa qo'shish

Rahmat 🎬 — Sozo ochiq loyiha va har qanday hissa qadrlanadi: kod, tarjima,
dizayn, xato hisoboti yoki shunchaki g'oya.

## Tez boshlash

```bash
git clone https://github.com/professorDeveloper/sozo.git
cd sozo
cp .env.example .env      # .env pubspec asset — busiz build yiqiladi
flutter pub get
flutter run
```

**Talab:** Flutter SDK (Dart `^3.11.1`), Android SDK 34+, JDK 17.
Desktop uchun qo'shimcha: Windows'da Visual Studio C++ workload, Linux'da
`libmpv-dev`, macOS'da Xcode.

`.env` dagi barcha kalitlar **ixtiyoriy** — bo'sh qoldirilsa tegishli
imkoniyat o'chadi, ilova baribir ishga tushadi.

## Arxitektura

Feature-first + clean architecture:

```
lib/
  core/                 # Butun ilova bo'ylab ishlatiladigan narsalar
    player/  js/  storage/  network/  theme/  di/  …
  features/
    <feature>/
      data/             # Model, repository implementatsiyasi, servislar
      domain/           # Entity, repository interfeysi, usecase
      presentation/     # Bloc/Cubit, sahifalar, vidjetlar
```

Qoidalar:

- **`presentation` hech qachon `data` ga to'g'ridan-to'g'ri murojaat qilmaydi.** Faqat `domain` orqali.
- Yangi bog'liqlik `core/di/injection.dart` da ro'yxatdan o'tadi.
- State — `flutter_bloc`. Yangi ekran uchun yangi Bloc/Cubit, `setState` emas.
- Navigatsiya — `go_router`, marshrut `core/router/app_router.dart` da.
- Matn to'g'ridan-to'g'ri yozilmaydi — `assets/translations/*.json` ga kalit
  qo'shiladi va `.tr()` orqali ishlatiladi.

## Kod uslubi

Bu repoda **izoh nima qilinayotganini emas, nega qilinganini** tushuntiradi.
Kod nima qilishini o'zi aytadi; nega aynan shunday qilinganini faqat izoh
aytadi. Mavjud fayllardagi uslubga qarang — masalan `pubspec.yaml` dagi har
bir paket izohi yoki `core/js/js_runtime_service.dart` boshidagi blok.

Yomon:
```dart
// Ro'yxatni saralaymiz
items.sort(...);
```

Yaxshi:
```dart
// Eng yangi epizod tepada bo'lishi kerak: foydalanuvchi seriyani ochganda
// deyarli har doim oxirgi ko'rgan joyidan davom etadi, birinchisidan emas.
items.sort(...);
```

Yuborishdan oldin:

```bash
flutter analyze     # toza o'tishi shart
flutter test
dart format lib/
```

## Commit va PR

- Bitta PR — bitta maqsad. "Xato tuzatildi + yangi ekran + refactor" uchta PR.
- Commit xabari nima o'zgarganini aytsin: `fix(player): mkv oqimida audio yo'l almashmasligi`
- PR shabloni to'ldirilsin, ayniqsa **qanday tekshirilgani**.
- Draft PR ochish mutlaqo normal — yarim yo'ldagi ish haqida maslahat so'rash uchun.

## Yangi manba (provider) qo'shish

Manbalar ilovada emas, **backend'da** turadi:
[`sozo-backend`](https://github.com/professorDeveloper/sozo-backend) →
`src/providers/`. U yerda harness bor, ilovani build qilmasdan sinash mumkin:

```bash
node tools/provider-harness/run.js <provider-id>
```

## Tarjima

`assets/translations/` da `en.json`, `ru.json`, `uz.json`, `ar.json` bor.
Yangi til qo'shish uchun `en.json` ni nusxalang, tarjima qiling va
`lib/main.dart` dagi `supportedLocales` ga qo'shing.

Kalit yo'qolib qolmasligi uchun:

```bash
dart run tool/check_translations.dart
```

## Litsenziya va CLA

Sozo **GPL-3.0** ostida. Hissa qo'shish orqali kodingiz ham shu litsenziya
ostida tarqatilishiga rozilik bildirasiz — [CLA.md](CLA.md).

Sun'iy intellekt yordamida yozilgan kod uchun — [AI_POLICY.md](AI_POLICY.md).

## Savol bormi

[Telegram](https://telegram.me/sozoapp) yoki
[Discord](https://discord.gg/n22URhYvMR) — ikkalasida ham tez javob beriladi.
