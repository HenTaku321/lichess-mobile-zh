import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_link.dart';

void main() {
  test('relative web links preserve encoded query parameters and fragments', () {
    final uri = xiangqiContentUri('/leaders?note=a%2Fb&return=%2Fplay#weekly')!;
    expect(uri.toString(), 'https://play.xiangqi.com/leaders?note=a%2Fb&return=%2Fplay#weekly');
    expect(uri.queryParameters, {'note': 'a/b', 'return': '/play'});
    expect(uri.fragment, 'weekly');
    expect(xiangqiContentUri('leaders')!.path, '/leaders');
    expect(xiangqiContentUri('//example.invalid/article?x=1')!.host, 'example.invalid');
  });

  test('content is never an arbitrary platform protocol or a URL with no host', () {
    for (final value in [
      '',
      ' ',
      'file:///project.txt',
      'javascript:alert(1)',
      'data:text/plain,x',
      'https:leaders',
    ]) {
      expect(xiangqiContentUri(value), isNull, reason: value);
    }
  });

  test('native route recognition requires the exact playing-site origin', () {
    expect(isXiangqiWebUri(Uri.parse('https://play.xiangqi.com/leaders')), isTrue);
    expect(isXiangqiWebUri(Uri.parse('http://play.xiangqi.com/leaders')), isTrue);
    for (final url in [
      'https://play.xiangqi.com.example.invalid/leaders',
      'https://play.xiangqi.com@other.invalid/leaders',
      'https://user@play.xiangqi.com/leaders',
      'https://play.xiangqi.com:8443/leaders',
      'https://api.xiangqi.com/api/leaders',
      'https://xiangqi.com/leaders',
    ]) {
      expect(isXiangqiWebUri(Uri.parse(url)), isFalse, reason: url);
    }
  });

  test('profile names are single visible segments, not API paths', () {
    expect(isXiangqiProfileName('棋友乙'), isTrue);
    expect(isXiangqiProfileName('riverbend'), isTrue);
    for (final value in ['', '.', '..', 'a/b', r'a\b', 'a?b', 'a#b', 'a b', 'a\n']) {
      expect(isXiangqiProfileName(value), isFalse, reason: value);
    }
  });
}
