import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/blog/blog.dart';
import 'package:lichess_mobile/src/model/blog/blog_post_content.dart';
import 'package:lichess_mobile/src/network/aggregator.dart';
import 'package:lichess_mobile/src/network/http.dart';

final blogCarouselProvider = FutureProvider.autoDispose<IList<BlogPost>>((ref) {
  return ref.read(blogRepositoryProvider).getCarousel();
}, name: 'BlogCarouselProvider');

/// A single post's body, keyed by post so that two posts open in a row do not
/// evict each other.
final blogPostProvider = FutureProvider.autoDispose.family<BlogPostContent, BlogPost>((ref, post) {
  return ref.read(blogRepositoryProvider).getPost(post);
}, name: 'BlogPostProvider');

final blogRepositoryProvider = Provider<BlogRepository>((ref) {
  final client = ref.watch(lichessClientProvider);
  final aggregator = ref.watch(aggregatorProvider);
  return BlogRepository(client, aggregator);
}, name: 'BlogRepositoryProvider');

class BlogRepository(final LichessClient client, final Aggregator aggregator) {
  Future<IList<BlogPost>> getCarousel() {
    return client.readJsonList(Uri(path: '/api/blog/carousel'), mapper: BlogPost.fromServerJson);
  }

  /// Fetches a post body through this fork's translation proxy.
  ///
  /// Only the path is sent, not the whole URL: the proxy concatenates it onto
  /// the lichess origin itself and rejects anything that could smuggle in a
  /// different host.
  Future<BlogPostContent> getPost(BlogPost post) {
    return client.readJson(
      Uri(path: '/api/zh/blog', queryParameters: {'url': post.url.path}),
      mapper: BlogPostContent.fromServerJson,
    );
  }
}
