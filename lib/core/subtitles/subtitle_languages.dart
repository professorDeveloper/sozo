/// Target languages the subtitle translator offers.
///
/// What the backend's provider waterfall can produce BETWEEN THEM — not what
/// any one provider can. Three are registered (Azure, DeepL, Google) and the
/// waterfall skips any whose key is unset, so which of these actually work
/// depends on the deployment's configuration.
///
/// This used to say DeepL supported all of them, which was wrong in the one
/// place it mattered most: DeepL has no Uzbek, and Uzbek is the first entry
/// here and the app's own language. The provider does not check the target
/// either — it posts `target_lang: UZ` and takes DeepL's rejection — so on a
/// deployment holding only a DeepL key, the primary language fails and the
/// comment said it could not.
///
/// Kazakh, Kyrgyz and Tajik are still left out: Google covers them, but they
/// would only work where a Google key is set, and a list that offers a language
/// which sometimes cannot be produced is worse than one that does not offer it.
///
/// Each entry is (code, native name).
const List<(String, String)> kSubtitleTranslateLanguages = [
  ('uz', "O'zbekcha"),
  ('ru', 'Русский'),
  ('en', 'English'),
  ('tr', 'Türkçe'),
  ('ar', 'العربية'),
  ('de', 'Deutsch'),
  ('fr', 'Français'),
  ('es', 'Español'),
  ('it', 'Italiano'),
  ('pt', 'Português'),
  ('nl', 'Nederlands'),
  ('pl', 'Polski'),
  ('uk', 'Українська'),
  ('id', 'Bahasa Indonesia'),
  ('ja', '日本語'),
  ('ko', '한국어'),
  ('zh', '中文'),
];
