import 'package:deep_pick/deep_pick.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'blog_post_content.freezed.dart';

/// The body of a blog post, as served by this fork's translation proxy.
///
/// Lichess has no content API for blog posts, so the proxy reaches the post page
/// with content negotiation, then translates the prose. It is a fork-only
/// endpoint, hence the `/api/zh/` path in the blog repository.
///
/// [translated] is false when the proxy has no translation backend configured,
/// or when translating the post failed. The post is then the original English
/// text, and the UI says so rather than passing it off as a translation.
@freezed
sealed class BlogPostContent with _$BlogPostContent {
  const factory({
    required String title,
    required String markdown,
    String? description,
    Uri? imageUrl,
    @Default(false) bool translated,
  }) = _BlogPostContent;

  factory fromServerJson(Map<String, dynamic> json) {
    return _blogPostContentFromPick(pick(json).required());
  }
}

BlogPostContent _blogPostContentFromPick(RequiredPick pick) {
  return BlogPostContent(
    title: pick('title').asStringOrThrow(),
    markdown: pick('markdown').asStringOrThrow(),
    description: pick('description').asStringOrNull(),
    imageUrl: pick('image').letOrNull((p) => Uri.tryParse(p.asStringOrThrow())),
    translated: pick('translated').asBoolOrNull() ?? false,
  );
}
