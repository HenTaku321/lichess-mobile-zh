import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_country_names.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_locale.dart';

void main() {
  test('Chinese app locales ask xiangqi.com for its Chinese source text', () {
    for (final locale in const [
      Locale('zh'),
      Locale('zh', 'CN'),
      Locale('zh', 'HK'),
      Locale('zh', 'TW'),
    ]) {
      expect(xiangqiLocaleOf(locale), 'zh_Hans', reason: '$locale');
    }
  });

  test('a measured localised language keeps its code', () {
    expect(xiangqiLocaleOf(const Locale('vi')), 'vi');
  });

  test('anything xiangqi.com does not localise asks for English', () {
    expect(xiangqiLocaleOf(const Locale('en')), 'en');
    expect(xiangqiLocaleOf(const Locale('fr')), 'en');
  });

  test('country names follow the app language, including the API spellings', () {
    const zh = Locale('zh');
    expect(xiangqiLocalizedCountryName(zh, code: 'HK'), '中国香港');
    expect(xiangqiLocalizedCountryName(zh, englishName: 'Viet Nam'), '越南');
    expect(xiangqiLocalizedCountryName(zh, englishName: 'Hong Kong, China'), '中国香港');
    expect(xiangqiLocalizedCountryName(const Locale('en'), code: 'HK'), 'Hong Kong SAR China');
    expect(xiangqiLocalizedCountryName(zh, code: 'ZZ'), 'ZZ');
  });
}
