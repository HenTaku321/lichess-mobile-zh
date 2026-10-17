import 'dart:ui' show Locale;

/// The `locale` spelling xiangqi.com's localised REST endpoints accept.
///
/// The server does not follow BCP-47 language tags: measured on 2026-10-17, `zh_Hans` returned
/// Chinese course text while `zh`, `zh_CN`, `zh-CN`, `zh_TW` and `zh-Hant` all returned English.
/// `vi` is the other localised course language this project measured. Everything else falls back to
/// the endpoint's own English source text.
///
/// This is deliberately one function rather than a string literal in each screen: a locale that
/// works for chapters but not for the topic list is the bug this file exists to prevent.
String xiangqiLocaleOf(Locale locale) => switch (locale.languageCode) {
  'zh' => 'zh_Hans',
  'vi' => 'vi',
  _ => 'en',
};
