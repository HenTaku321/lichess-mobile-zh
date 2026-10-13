/// The host of the xiangqi.com REST API.
const _xiangqiApiHost = 'api.xiangqi.com';

/// Builds a URL on the xiangqi.com REST API. Base is `https://api.xiangqi.com/api/`.
///
/// [unencodedPath] is relative to that base: `xiangqiUri('games')` yields
/// `https://api.xiangqi.com/api/games`. The scheme is always HTTPS — unlike the
/// lichess helper, this backend is never served over plain HTTP for a local
/// development host.
Uri xiangqiUri(String unencodedPath, [Map<String, dynamic>? queryParameters]) =>
    Uri.https(_xiangqiApiHost, '/api/$unencodedPath', queryParameters);
