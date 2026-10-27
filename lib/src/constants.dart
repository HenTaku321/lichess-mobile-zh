import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

const kLichessHost = String.fromEnvironment('LICHESS_HOST', defaultValue: 'lichess.dev');

const kLichessWSHost = String.fromEnvironment(
  'LICHESS_WS_HOST',
  defaultValue: 'socket.lichess.dev',
);

const kLichessWSSecret = String.fromEnvironment(
  'LICHESS_WS_SECRET',
  defaultValue: 'somethingElseInProd',
);

/// The extractable client gate this build presents to the translation proxy at [kLichessHost].
/// It is not a secret or a user identity: server-side concurrency/rate limits protect LLM spend.
///
/// Empty means "send nothing", which is the right request for a debug build, and
/// for any build that talks to the real lichess server. Release builds bake in
/// the fixed-length placeholder below, which the packaging step replaces byte for
/// byte — the same mechanism, and for the same reason, as [kLichessWSSecret]: the
/// packaging keeps the operator's value out of source; any installed client can still reveal it.
const kZhProxyToken = String.fromEnvironment('ZH_PROXY_TOKEN', defaultValue: '');

/// The header the proxy reads [kZhProxyToken] from. It has to match the proxy's
/// `zhTokenHeader`; the two are one contract with two ends.
const kZhProxyTokenHeader = 'X-Zh-Token';

const kLichessCDNHost = String.fromEnvironment(
  'LICHESS_CDN_HOST',
  defaultValue: 'https://lichess1.org',
);

const kLichessOpeningExplorerHost = String.fromEnvironment(
  'LICHESS_OPENING_EXPLORER_HOST',
  defaultValue: 'explorer.lichess.org',
);

const kLichessTablebaseHost = String.fromEnvironment(
  'LICHESS_TABLEBASE_HOST',
  defaultValue: 'tablebase.lichess.org',
);

const kLichessCustomUriSchemeName = 'org.lichess.mobile';

const kLichessClientId = 'lichess_mobile';

const kSRIStorageKey = 'socket_random_identifier';

const kFideRatingsUrl = 'https://ratings.fide.com/profile/';

// lichess
// https://github.com/lichess-org/lila/blob/4562a83cdb263c3ebf7e148c0f666f0ff92b91c7/modules/rating/src/main/Glicko.scala#L71
const kProvisionalDeviation = 110;
const kClueLessDeviation = 230;

const kMaintenanceDrawingAuthorUrl = 'https://www.pixiv.net/member.php?id=34624';
const kLichessMastodonUrl = 'https://mastodon.online/@lichess';
const kLichessBlueskyUrl = 'https://bsky.app/profile/lichess.org';
const kLichessDiscordUrl = 'https://discord.gg/lichess';

// UI
const double kCupertinoBarBlurSigma = 30.0;
const double kCupertinoBarOpacity = 0.8;

const kGoldenRatio = 1.61803398875;

/// Use same box shadows as material widgets with elevation 1.
final List<BoxShadow> boardShadows = defaultTargetPlatform == TargetPlatform.iOS
    ? <BoxShadow>[]
    : kElevationToShadow[1]!;

const kMaxClockTextScaleFactor = 1.94;
const kEmptyWidget = SizedBox.shrink();
const kTabletBoardTableSidePadding = 16.0;

const kBottomBarHeight = 56.0;
const kMaterialPopupMenuMaxWidth = 500.0;

/// The threshold to detect screens with a small remaining height minus board.
const kSmallHeightMinusBoard = 200;
