import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/profile/xiangqi_profile.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_link.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/message/contacts_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_chat_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_leaderboard_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_lessons_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_notifications_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_online_game_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_profile_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_tournaments_screen.dart';
import 'package:lichess_mobile/src/view/xiangqi/xiangqi_watch_screen.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/rich_link_text.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

final _logger = Logger('XiangqiLinks');

final xiangqiLinksServiceProvider = Provider<XiangqiLinksService>(XiangqiLinksService.new);

/// Shared navigation for xiangqi notifications and chat content. Route recognition is conservative:
/// a supported path with unsupported parameters still opens its complete original web URL.
class XiangqiLinksService(final Ref ref) {
  final Set<(NavigatorState, Uri)> _opening = {};

  Future<void> openContentLink(
    BuildContext context,
    String value, {
    int? expectedAccountGeneration,
  }) async {
    if (!context.mounted || !ref.mounted) return;
    final account = ref.read(xiangqiAccountGenerationProvider);
    final visible = _routeVisibility(context);
    bool current() =>
        context.mounted &&
        ref.mounted &&
        account == ref.read(xiangqiAccountGenerationProvider) &&
        visible();
    if ((expectedAccountGeneration != null && expectedAccountGeneration != account) || !current()) {
      return;
    }
    final uri = xiangqiContentUri(value);
    if (uri == null) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    final key = (navigator, uri);
    if (!_opening.add(key)) return;
    try {
      final route = _route(context, uri);
      if (route != null) {
        await navigator.push(route);
      } else if (!await launchUrl(uri) && current()) {
        if (!context.mounted) return;
        showSnackBar(context, context.l10n.mobileSomethingWentWrong, type: SnackBarType.error);
      }
    } on Object catch (error, stackTrace) {
      _logger.warning('Could not open a xiangqi content link', error, stackTrace);
      if (current()) {
        if (!context.mounted) return;
        showSnackBar(context, context.l10n.mobileSomethingWentWrong, type: SnackBarType.error);
      }
    } finally {
      _opening.remove(key);
    }
  }

  Future<void> openProfile(
    BuildContext context,
    String username, {
    int? expectedAccountGeneration,
  }) async {
    if (!isXiangqiProfileName(username)) return;
    final uri = Uri.https(kXiangqiWebHost, '/').replace(pathSegments: ['@', username]);
    await openContentLink(
      context,
      uri.toString(),
      expectedAccountGeneration: expectedAccountGeneration,
    );
  }

  Future<void> onLinkifyOpen(
    BuildContext context,
    LinkableElement link, {
    int? expectedAccountGeneration,
  }) async {
    if (link is EmailElement) {
      if (!context.mounted || !ref.mounted) return;
      if (!_routeVisibility(context)()) return;
      if (expectedAccountGeneration != null &&
          expectedAccountGeneration != ref.read(xiangqiAccountGenerationProvider)) {
        return;
      }
      try {
        await launchUrl(Uri(scheme: 'mailto', path: link.emailAddress));
      } on Object catch (error, stackTrace) {
        _logger.warning('Could not open an email link', error, stackTrace);
      }
    } else {
      await openContentLink(
        context,
        link.url,
        expectedAccountGeneration: expectedAccountGeneration,
      );
    }
  }

  /// A tab's nested navigator can have a current route while the root route is covered. Capture
  /// the complete route chain and tab offstage elements before any async gap; checking just the
  /// nearest ModalRoute permits callbacks from a page the user can no longer see.
  bool Function() _routeVisibility(BuildContext context) {
    final route = ModalRoute.of(context);
    final routes = <ModalRoute<dynamic>>{if (route != null) route};
    final offstage = <Element>[];
    context.visitAncestorElements((element) {
      if (element.widget is Navigator) {
        final parent = ModalRoute.of(element);
        if (parent != null) routes.add(parent);
      }
      if (element.widget is Offstage) offstage.add(element);
      return true;
    });
    return () =>
        context.mounted &&
        routes.every((route) => route.isActive && route.isCurrent) &&
        offstage.every((element) => !(element.widget as Offstage).offstage);
  }

  Route<dynamic>? _route(BuildContext context, Uri uri) {
    if (!isXiangqiWebUri(uri) || uri.hasQuery || uri.hasFragment) return null;
    final path = uri.pathSegments;
    final segments = path.isNotEmpty && path.last.isEmpty ? path.sublist(0, path.length - 1) : path;
    switch (segments) {
      case ['@', final username] when isXiangqiProfileName(username):
        return XiangqiProfileScreen.buildRoute(username);
      case ['profile']:
        final session = ref.read(xiangqiAuthControllerProvider);
        return session != null && !session.isGuest && isXiangqiProfileName(session.name)
            ? XiangqiProfileScreen.buildRoute(session.name)
            : null;
      case ['game', final id] when id != 'create' && isXiangqiRouteId(id):
        return XiangqiOnlineGameScreen.buildRoute(id);
      case ['lessons']:
        return XiangqiLessonsScreen.buildRoute();
      case ['lessons', 'topic', final id] when isXiangqiRouteId(id):
        return XiangqiTopicScreen.buildRoute(id);
      case ['leaders']:
        return XiangqiLeaderboardScreen.buildRoute();
      case ['leaders', final mode]:
        final rating = _rating(mode);
        return rating == null ? null : XiangqiLeaderboardScreen.buildRoute(initialMode: rating);
      case ['leaders', final mode, final country] when RegExp(r'^[A-Za-z]{2}$').hasMatch(country):
        final rating = _rating(mode);
        return rating == null
            ? null
            : XiangqiLeaderboardScreen.buildRoute(
                initialMode: rating,
                initialCountry: country.toUpperCase(),
              );
      case ['watch']:
        return XiangqiWatchScreen.buildRoute();
      case ['notifications']:
        return XiangqiNotificationsScreen.buildRoute();
      case ['inbox']:
        return ContactsScreen.buildRoute();
      case ['chat']:
        return XiangqiChatScreen.buildRoute();
      case ['tournaments']:
        return XiangqiTournamentsScreen.buildRoute();
      case _:
        // A direct inbox link does not include a peer identity, so do not fabricate one. Nested
        // puzzle/review/chat routes and editor URLs need their own proven handoff contracts.
        return null;
    }
  }

  XiangqiRatingType? _rating(String mode) => switch (mode) {
    'rapid' => .rapid,
    'bullet' => .bullet,
    'daily' => .daily,
    'puzzle' => .puzzle,
    _ => null,
  };
}
