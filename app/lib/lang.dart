/// The languages a caregiver can tell Dayby they speak.
///
/// The server transcribes without being told a locale, which is what lets someone switch
/// mid-sentence — but left entirely open it will also hear Chinese in a Korean sentence
/// muttered over a crying baby. Naming the handful of languages that are even possible
/// closes that off without taking the freedom away.
///
/// Personal, not shared: one parent's shorter list is a tighter constraint, and so a
/// better one, than the household's union.
const kLanguages = <String, String>{
  'ko': 'Korean',
  'en': 'English',
  'ja': 'Japanese',
  'zh': 'Chinese',
  'es': 'Spanish',
  'fr': 'French',
  'de': 'German',
};

const kDefaultLanguages = <String>['ko', 'en'];

String languageName(String code) => kLanguages[code] ?? code;
