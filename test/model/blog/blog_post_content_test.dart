import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/blog/blog_post_content.dart';

void main() {
  test('parses a translated post', () {
    final content = BlogPostContent.fromServerJson({
      'title': '本月最佳对局',
      'description': '长长的斜线为白王铺平了道路',
      'image': 'https://image.lichess1.org/display?fmt=webp&w=880',
      'markdown': '正文第一段。\n\n## 如何投稿\n\n* 仅限标准对局\n',
      'translated': true,
    });

    expect(content.title, '本月最佳对局');
    expect(content.description, '长长的斜线为白王铺平了道路');
    expect(content.imageUrl, Uri.parse('https://image.lichess1.org/display?fmt=webp&w=880'));
    expect(content.markdown, contains('## 如何投稿'));
    expect(content.translated, isTrue);
  });

  // The proxy omits description and image for a post that has neither (Go's
  // omitempty), and reports translated=false when it has no translation backend.
  // Neither may throw: a post with no lead image is still readable.
  test('parses an untranslated post with no description or image', () {
    final content = BlogPostContent.fromServerJson({
      'title': 'Post',
      'markdown': 'Body.',
      'translated': false,
    });

    expect(content.title, 'Post');
    expect(content.description, isNull);
    expect(content.imageUrl, isNull);
    expect(content.translated, isFalse);
  });

  // An older proxy omits the flag entirely. The default must be the honest one:
  // the UI offers the original in a browser when this is false, so defaulting to
  // true would present English as if it were a translation.
  test('translated defaults to false when the flag is absent', () {
    final content = BlogPostContent.fromServerJson({'title': 'Post', 'markdown': 'Body.'});

    expect(content.translated, isFalse);
  });
}
