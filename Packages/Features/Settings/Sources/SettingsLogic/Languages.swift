import Foundation

/// The language metadata the language settings screen needs.
///
/// Port of `src/locale/languages.ts`. Two tables:
///
/// - ``appLanguages`` - the UI translation languages the picker offers, from
///   `APP_LANGUAGES`. Each carries the `AppLanguage` code (`en-GB`, `pt-BR`,
///   `zh-Hans-CN`) and the label RN renders.
/// - ``languages`` - the ISO-639 table from `LANGUAGES`, used for content and
///   post languages. RN's language dialog dedupes it by `code2` keeping the
///   first occurrence, so this table has exactly one entry per `code2`.
///
/// Both tables are transcribed from the TS source rather than derived at
/// runtime, because RN localizes the name through `Intl.DisplayNames`, whose
/// availability and results differ across platforms. The English names baked in
/// here are the same fallback RN itself falls back to when `Intl.DisplayNames`
/// is unavailable (`languageName` in `src/locale/helpers.ts`).

/// One language entry: `Language` in `src/locale/languages.ts`.
public struct Language: Sendable, Equatable, Hashable {
  /// The ISO-639-2 three-letter code.
  public let code3: String
  /// The ISO-639-1 two-letter code, or a locale tag for the app languages.
  public let code2: String
  /// The English display name.
  public let name: String

  public init(code3: String, code2: String, name: String) {
    self.code3 = code3
    self.code2 = code2
    self.name = name
  }
}

/// One UI language: `AppLanguageConfig` in `src/locale/languages.ts`.
public struct AppLanguageConfig: Sendable, Equatable, Hashable {
  /// The `AppLanguage` enum value, e.g. `en`, `en-GB`, `zh-Hans-CN`.
  public let code2: String
  /// The label the picker renders.
  public let name: String

  public init(code2: String, name: String) {
    self.code2 = code2
    self.name = name
  }
}

/// The language tables and the helpers over them.
public enum Languages {

  /// `APP_LANGUAGES`: the UI translation languages, in source order.
  public static let appLanguages: [AppLanguageConfig] = [
    AppLanguageConfig(code2: "en", name: "English"),
    AppLanguageConfig(code2: "an", name: "aragonés – Aragonese"),
    AppLanguageConfig(code2: "ast", name: "asturianu – Asturian"),
    AppLanguageConfig(code2: "ca", name: "català – Catalan"),
    AppLanguageConfig(code2: "cs", name: "čeština – Czech"),
    AppLanguageConfig(code2: "cy", name: "Cymraeg – Welsh"),
    AppLanguageConfig(code2: "da", name: "dansk – Danish"),
    AppLanguageConfig(code2: "de", name: "Deutsch – German"),
    AppLanguageConfig(code2: "el", name: "Ελληνικά – Greek"),
    AppLanguageConfig(code2: "en-GB", name: "British English"),
    AppLanguageConfig(code2: "eo", name: "Esperanto"),
    AppLanguageConfig(code2: "es", name: "español – Spanish"),
    AppLanguageConfig(code2: "eu", name: "euskara – Basque"),
    AppLanguageConfig(code2: "fi", name: "suomi – Finnish"),
    AppLanguageConfig(code2: "fr", name: "français – French"),
    AppLanguageConfig(code2: "fy", name: "Frysk – Western Frisian"),
    AppLanguageConfig(code2: "ga", name: "Gaeilge – Irish"),
    AppLanguageConfig(code2: "gd", name: "Gàidhlig – Scottish Gaelic"),
    AppLanguageConfig(code2: "gl", name: "galego – Galician"),
    AppLanguageConfig(code2: "hi", name: "हिंदी – Hindi"),
    AppLanguageConfig(code2: "hu", name: "magyar – Hungarian"),
    AppLanguageConfig(code2: "ia", name: "Interlingua"),
    AppLanguageConfig(code2: "id", name: "Bahasa Indonesia – Indonesian"),
    AppLanguageConfig(code2: "it", name: "italiano – Italian"),
    AppLanguageConfig(code2: "ja", name: "日本語 – Japanese"),
    AppLanguageConfig(code2: "km", name: "ភាសាខ្មែរ – Khmer"),
    AppLanguageConfig(code2: "ko", name: "한국어 – Korean"),
    AppLanguageConfig(code2: "ne", name: "नेपाली – Nepali"),
    AppLanguageConfig(code2: "nl", name: "Nederlands – Dutch"),
    AppLanguageConfig(code2: "pl", name: "polski – Polish"),
    AppLanguageConfig(code2: "pt-BR", name: "português do Brasil – Brazilian Portuguese"),
    AppLanguageConfig(code2: "pt-PT", name: "português europeu – European Portuguese"),
    AppLanguageConfig(code2: "ro", name: "română – Romanian"),
    AppLanguageConfig(code2: "ru", name: "русский – Russian"),
    AppLanguageConfig(code2: "sv", name: "svenska – Swedish"),
    AppLanguageConfig(code2: "th", name: "ภาษาไทย – Thai"),
    AppLanguageConfig(code2: "tr", name: "Türkçe – Turkish"),
    AppLanguageConfig(code2: "uk", name: "українська – Ukrainian"),
    AppLanguageConfig(code2: "vi", name: "Tiếng Việt – Vietnamese"),
    AppLanguageConfig(code2: "zh-Hans-CN", name: "简体中文 – Simplified Chinese"),
    AppLanguageConfig(code2: "zh-Hant-TW", name: "繁體中文 – Traditional Chinese"),
    AppLanguageConfig(code2: "zh-Hant-HK", name: "粵文 – Cantonese"),
  ]

  /// `LANGUAGES`: the ISO-639 table, deduped by `code2` exactly as the RN
  /// language dialog does.
  public static let languages: [Language] = [
    Language(code3: "aar", code2: "aa", name: "Afar"),
    Language(code3: "abk", code2: "ab", name: "Abkhazian"),
    Language(code3: "afr", code2: "af", name: "Afrikaans"),
    Language(code3: "aka", code2: "ak", name: "Akan"),
    Language(code3: "alb", code2: "sq", name: "Albanian"),
    Language(code3: "amh", code2: "am", name: "Amharic"),
    Language(code3: "ara", code2: "ar", name: "Arabic"),
    Language(code3: "arg", code2: "an", name: "Aragonese"),
    Language(code3: "arm", code2: "hy", name: "Armenian"),
    Language(code3: "asm", code2: "as", name: "Assamese"),
    Language(code3: "ava", code2: "av", name: "Avaric"),
    Language(code3: "ave", code2: "ae", name: "Avestan"),
    Language(code3: "aym", code2: "ay", name: "Aymara"),
    Language(code3: "aze", code2: "az", name: "Azerbaijani"),
    Language(code3: "bak", code2: "ba", name: "Bashkir"),
    Language(code3: "bam", code2: "bm", name: "Bambara"),
    Language(code3: "baq", code2: "eu", name: "Basque"),
    Language(code3: "bel", code2: "be", name: "Belarusian"),
    Language(code3: "ben", code2: "bn", name: "Bangla"),
    Language(code3: "bih", code2: "bh", name: "Bhojpuri"),
    Language(code3: "bis", code2: "bi", name: "Bislama"),
    Language(code3: "bod", code2: "bo", name: "Tibetan"),
    Language(code3: "bos", code2: "bs", name: "Bosnian"),
    Language(code3: "bre", code2: "br", name: "Breton"),
    Language(code3: "bul", code2: "bg", name: "Bulgarian"),
    Language(code3: "bur", code2: "my", name: "Burmese"),
    Language(code3: "cat", code2: "ca", name: "Catalan"),
    Language(code3: "ces", code2: "cs", name: "Czech"),
    Language(code3: "cha", code2: "ch", name: "Chamorro"),
    Language(code3: "che", code2: "ce", name: "Chechen"),
    Language(code3: "chi", code2: "zh", name: "Chinese"),
    Language(code3: "chu", code2: "cu", name: "Church Slavic"),
    Language(code3: "chv", code2: "cv", name: "Chuvash"),
    Language(code3: "cor", code2: "kw", name: "Cornish"),
    Language(code3: "cos", code2: "co", name: "Corsican"),
    Language(code3: "cre", code2: "cr", name: "Cree"),
    Language(code3: "cym", code2: "cy", name: "Welsh"),
    Language(code3: "dan", code2: "da", name: "Danish"),
    Language(code3: "deu", code2: "de", name: "German"),
    Language(code3: "div", code2: "dv", name: "Divehi"),
    Language(code3: "dut", code2: "nl", name: "Dutch"),
    Language(code3: "dzo", code2: "dz", name: "Dzongkha"),
    Language(code3: "ell", code2: "el", name: "Greek"),
    Language(code3: "eng", code2: "en", name: "English"),
    Language(code3: "epo", code2: "eo", name: "Esperanto"),
    Language(code3: "est", code2: "et", name: "Estonian"),
    Language(code3: "ewe", code2: "ee", name: "Ewe"),
    Language(code3: "fao", code2: "fo", name: "Faroese"),
    Language(code3: "fas", code2: "fa", name: "Persian"),
    Language(code3: "fij", code2: "fj", name: "Fijian"),
    Language(code3: "fin", code2: "fi", name: "Finnish"),
    Language(code3: "fra", code2: "fr", name: "French"),
    Language(code3: "fry", code2: "fy", name: "Western Frisian"),
    Language(code3: "ful", code2: "ff", name: "Fulah"),
    Language(code3: "geo", code2: "ka", name: "Georgian"),
    Language(code3: "gla", code2: "gd", name: "Scottish Gaelic"),
    Language(code3: "gle", code2: "ga", name: "Irish"),
    Language(code3: "glg", code2: "gl", name: "Galician"),
    Language(code3: "glv", code2: "gv", name: "Manx"),
    Language(code3: "grn", code2: "gn", name: "Guarani"),
    Language(code3: "guj", code2: "gu", name: "Gujarati"),
    Language(code3: "hat", code2: "ht", name: "Haitian Creole"),
    Language(code3: "hau", code2: "ha", name: "Hausa"),
    Language(code3: "heb", code2: "he", name: "Hebrew"),
    Language(code3: "her", code2: "hz", name: "Herero"),
    Language(code3: "hin", code2: "hi", name: "Hindi"),
    Language(code3: "hmo", code2: "ho", name: "Hiri Motu"),
    Language(code3: "hrv", code2: "hr", name: "Croatian"),
    Language(code3: "hun", code2: "hu", name: "Hungarian"),
    Language(code3: "ibo", code2: "ig", name: "Igbo"),
    Language(code3: "ice", code2: "is", name: "Icelandic"),
    Language(code3: "ido", code2: "io", name: "Ido"),
    Language(code3: "iii", code2: "ii", name: "Sichuan Yi; Nuosu"),
    Language(code3: "iku", code2: "iu", name: "Inuktitut"),
    Language(code3: "ile", code2: "ie", name: "Interlingue"),
    Language(code3: "ina", code2: "ia", name: "Interlingua"),
    Language(code3: "ind", code2: "id", name: "Indonesian"),
    Language(code3: "ipk", code2: "ik", name: "Inupiaq"),
    Language(code3: "ita", code2: "it", name: "Italian"),
    Language(code3: "jav", code2: "jv", name: "Javanese"),
    Language(code3: "jpn", code2: "ja", name: "Japanese"),
    Language(code3: "kal", code2: "kl", name: "Kalaallisut"),
    Language(code3: "kan", code2: "kn", name: "Kannada"),
    Language(code3: "kas", code2: "ks", name: "Kashmiri"),
    Language(code3: "kau", code2: "kr", name: "Kanuri"),
    Language(code3: "kaz", code2: "kk", name: "Kazakh"),
    Language(code3: "khm", code2: "km", name: "Khmer"),
    Language(code3: "kik", code2: "ki", name: "Kikuyu; Gikuyu"),
    Language(code3: "kin", code2: "rw", name: "Kinyarwanda"),
    Language(code3: "kir", code2: "ky", name: "Kyrgyz"),
    Language(code3: "kom", code2: "kv", name: "Komi"),
    Language(code3: "kon", code2: "kg", name: "Kongo"),
    Language(code3: "kor", code2: "ko", name: "Korean"),
    Language(code3: "kua", code2: "kj", name: "Kuanyama; Kwanyama"),
    Language(code3: "kur", code2: "ku", name: "Kurdish"),
    Language(code3: "lao", code2: "lo", name: "Lao"),
    Language(code3: "lat", code2: "la", name: "Latin"),
    Language(code3: "lav", code2: "lv", name: "Latvian"),
    Language(code3: "lim", code2: "li", name: "Limburgish"),
    Language(code3: "lin", code2: "ln", name: "Lingala"),
    Language(code3: "lit", code2: "lt", name: "Lithuanian"),
    Language(code3: "ltz", code2: "lb", name: "Luxembourgish"),
    Language(code3: "lub", code2: "lu", name: "Luba-Katanga"),
    Language(code3: "lug", code2: "lg", name: "Ganda"),
    Language(code3: "mac", code2: "mk", name: "Macedonian"),
    Language(code3: "mah", code2: "mh", name: "Marshallese"),
    Language(code3: "mal", code2: "ml", name: "Malayalam"),
    Language(code3: "mao", code2: "mi", name: "Māori"),
    Language(code3: "mar", code2: "mr", name: "Marathi"),
    Language(code3: "may", code2: "ms", name: "Malay"),
    Language(code3: "mlg", code2: "mg", name: "Malagasy"),
    Language(code3: "mlt", code2: "mt", name: "Maltese"),
    Language(code3: "mon", code2: "mn", name: "Mongolian"),
    Language(code3: "nau", code2: "na", name: "Nauru"),
    Language(code3: "nav", code2: "nv", name: "Navajo"),
    Language(code3: "nbl", code2: "nr", name: "South Ndebele"),
    Language(code3: "nde", code2: "nd", name: "North Ndebele"),
    Language(code3: "ndo", code2: "ng", name: "Ndonga"),
    Language(code3: "nep", code2: "ne", name: "Nepali"),
    Language(code3: "nno", code2: "nn", name: "Norwegian Nynorsk"),
    Language(code3: "nob", code2: "nb", name: "Norwegian Bokmål"),
    Language(code3: "nor", code2: "no", name: "Norwegian"),
    Language(code3: "nya", code2: "ny", name: "Nyanja"),
    Language(code3: "oci", code2: "oc", name: "Occitan"),
    Language(code3: "oji", code2: "oj", name: "Ojibwa"),
    Language(code3: "ori", code2: "or", name: "Odia"),
    Language(code3: "orm", code2: "om", name: "Oromo"),
    Language(code3: "oss", code2: "os", name: "Ossetic"),
    Language(code3: "pan", code2: "pa", name: "Punjabi"),
    Language(code3: "pli", code2: "pi", name: "Pali"),
    Language(code3: "pol", code2: "pl", name: "Polish"),
    Language(code3: "por", code2: "pt", name: "Portuguese"),
    Language(code3: "pus", code2: "ps", name: "Pashto"),
    Language(code3: "que", code2: "qu", name: "Quechua"),
    Language(code3: "roh", code2: "rm", name: "Romansh"),
    Language(code3: "rum", code2: "ro", name: "Romanian"),
    Language(code3: "run", code2: "rn", name: "Rundi"),
    Language(code3: "rus", code2: "ru", name: "Russian"),
    Language(code3: "sag", code2: "sg", name: "Sango"),
    Language(code3: "san", code2: "sa", name: "Sanskrit"),
    Language(code3: "sin", code2: "si", name: "Sinhala"),
    Language(code3: "slo", code2: "sk", name: "Slovak"),
    Language(code3: "slv", code2: "sl", name: "Slovenian"),
    Language(code3: "sme", code2: "se", name: "Northern Sami"),
    Language(code3: "smo", code2: "sm", name: "Samoan"),
    Language(code3: "sna", code2: "sn", name: "Shona"),
    Language(code3: "snd", code2: "sd", name: "Sindhi"),
    Language(code3: "som", code2: "so", name: "Somali"),
    Language(code3: "sot", code2: "st", name: "Southern Sotho"),
    Language(code3: "spa", code2: "es", name: "Spanish"),
    Language(code3: "srd", code2: "sc", name: "Sardinian"),
    Language(code3: "srp", code2: "sr", name: "Serbian"),
    Language(code3: "ssw", code2: "ss", name: "Swati"),
    Language(code3: "sun", code2: "su", name: "Sundanese"),
    Language(code3: "swa", code2: "sw", name: "Swahili"),
    Language(code3: "swe", code2: "sv", name: "Swedish"),
    Language(code3: "tah", code2: "ty", name: "Tahitian"),
    Language(code3: "tam", code2: "ta", name: "Tamil"),
    Language(code3: "tat", code2: "tt", name: "Tatar"),
    Language(code3: "tel", code2: "te", name: "Telugu"),
    Language(code3: "tgk", code2: "tg", name: "Tajik"),
    Language(code3: "tgl", code2: "tl", name: "Filipino"),
    Language(code3: "tha", code2: "th", name: "Thai"),
    Language(code3: "tir", code2: "ti", name: "Tigrinya"),
    Language(code3: "ton", code2: "to", name: "Tongan"),
    Language(code3: "tsn", code2: "tn", name: "Tswana"),
    Language(code3: "tso", code2: "ts", name: "Tsonga"),
    Language(code3: "tuk", code2: "tk", name: "Turkmen"),
    Language(code3: "tur", code2: "tr", name: "Turkish"),
    Language(code3: "twi", code2: "tw", name: "Akan"),
    Language(code3: "uig", code2: "ug", name: "Uyghur"),
    Language(code3: "ukr", code2: "uk", name: "Ukrainian"),
    Language(code3: "urd", code2: "ur", name: "Urdu"),
    Language(code3: "uzb", code2: "uz", name: "Uzbek"),
    Language(code3: "ven", code2: "ve", name: "Venda"),
    Language(code3: "vie", code2: "vi", name: "Vietnamese"),
    Language(code3: "vol", code2: "vo", name: "Volapük"),
    Language(code3: "wln", code2: "wa", name: "Walloon"),
    Language(code3: "wol", code2: "wo", name: "Wolof"),
    Language(code3: "xho", code2: "xh", name: "Xhosa"),
    Language(code3: "yid", code2: "yi", name: "Yiddish"),
    Language(code3: "yor", code2: "yo", name: "Yoruba"),
    Language(code3: "zha", code2: "za", name: "Zhuang; Chuang"),
    Language(code3: "zul", code2: "zu", name: "Zulu"),
  ]

  /// A `code2` to `Language` index, matching `LANGUAGES_MAP_CODE2`.
  public static let byCode2: [String: Language] = {
    var map: [String: Language] = [:]
    for language in languages where map[language.code2] == nil {
      map[language.code2] = language
    }
    return map
  }()

  /// A `code3` to `Language` index, matching `LANGUAGES_MAP_CODE3`.
  public static let byCode3: [String: Language] = {
    var map: [String: Language] = [:]
    for language in languages where map[language.code3] == nil {
      map[language.code3] = language
    }
    return map
  }()

  /// `code3ToCode2`: a three-letter code becomes its two-letter code, or is
  /// returned unchanged when it is already two letters or unknown.
  public static func code3ToCode2(_ code: String) -> String {
    guard code.count == 3 else { return code }
    return byCode3[code]?.code2 ?? code
  }

  /// `code2ToCode3`: a two-letter code becomes its three-letter code, or is
  /// returned unchanged.
  public static func code2ToCode3(_ code: String) -> String {
    guard code.count == 2 else { return code }
    return byCode2[code]?.code3 ?? code
  }

  /// The English name for a language code, the way `codeToLanguageName` falls
  /// back when `Intl.DisplayNames` is unavailable.
  public static func name(forCode code: String) -> String {
    let code2 = code3ToCode2(code)
    return byCode2[code2]?.name ?? code2
  }

  /// The UI language for a code, or nil when the app does not ship it.
  public static func appLanguage(for code: String) -> AppLanguageConfig? {
    appLanguages.first { $0.code2 == code }
  }

  /// `fixLegacyLanguageCode`: Java-era codes the app still has stored.
  ///
  /// `in` is Indonesian, `iw` is Hebrew. Both were renamed in the ISO table;
  /// Android devices wrote the old spellings.
  public static func fixLegacyLanguageCode(_ code: String) -> String {
    switch code {
    case "in": return "id"
    case "iw": return "he"
    default: return code
    }
  }
}
