import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/blog/blog.dart';
import 'package:lichess_mobile/src/model/blog/blog_post_content.dart';
import 'package:lichess_mobile/src/model/blog/blog_repository.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/widgets/network_image.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// A blog post, read in the app and translated into the app's language.
///
/// The body comes from this fork's translation proxy rather than from lichess: lichess exposes
/// neither markdown nor JSON for a post, so the proxy negotiates markdown from the post page itself
/// and translates the prose. When it cannot — no translation backend configured, or the request
/// failed — the post is shown in its original language with a notice saying so, and the app bar
/// offers the original on lichess.org.
class const BlogPostScreen({required final BlogPost post, super.key}) extends ConsumerWidget {
  static Route<dynamic> buildRoute(BlogPost post) {
    return buildScreenRoute(screen: BlogPostScreen(post: post));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ref.watch(blogPostProvider(post));
    return PlatformScaffold(
      appBar: PlatformAppBar(
        // Prefer the title that came with the body: the carousel and the post are translated
        // independently, and this one belongs to the text below it.
        title: Text(
          content.value?.title ?? post.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: context.l10n.mobileOpenInBrowser,
            onPressed: () => launchUrl(lichessUri(post.url.toString())),
            icon: const Icon(Icons.open_in_new),
          ),
        ],
      ),
      body: switch (content) {
        AsyncData(:final value) => _BlogPostBody(content: value),
        AsyncError() => Center(
          child: Padding(
            padding: Styles.bodyPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.l10n.mobileBlogLoadFailed,
                  style: Styles.sectionTitle,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16.0),
                FilledButton.tonal(
                  onPressed: () => ref.invalidate(blogPostProvider(post)),
                  child: Text(context.l10n.retry),
                ),
              ],
            ),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator.adaptive()),
      },
    );
  }
}

class const _BlogPostBody({required final BlogPostContent content}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final imageUrl = content.imageUrl;
    return SingleChildScrollView(
      padding: Styles.bodyPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (imageUrl != null) ...[
            ClipRRect(
              borderRadius: Styles.cardBorderRadius,
              child: HttpNetworkImageWidget(imageUrl.toString()),
            ),
            const SizedBox(height: 16.0),
          ],
          if (!content.translated) ...[
            Text(
              context.l10n.mobileBlogNotTranslated,
              style: TextStyle(color: textShade(context, Styles.subtitleOpacity)),
            ),
            const SizedBox(height: 16.0),
          ],
          MarkdownBody(
            data: content.markdown,
            softLineBreak: true,
            onTapLink: (text, url, title) {
              if (url == null) return;
              launchUrl(Uri.https('lichess.org').resolve(url));
            },
          ),
        ],
      ),
    );
  }
}
