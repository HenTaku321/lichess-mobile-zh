/// Content originates on the playing site, not on the API or the marketing homepage.
const kXiangqiWebHost = 'play.xiangqi.com';

/// Resolve a server-written relative URL without treating its query and fragment as path text.
/// Only web URLs are supported; content must not invoke arbitrary platform protocols.
Uri? xiangqiContentUri(String value) {
  final text = value.trim();
  if (text.isEmpty) return null;
  final parsed = Uri.tryParse(text);
  if (parsed == null) return null;
  final uri = parsed.hasScheme ? parsed : Uri.https(kXiangqiWebHost, '/').resolveUri(parsed);
  if ((uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) return null;
  return uri;
}

/// Compare the parsed origin, never a URL prefix or an arbitrary subdomain.
bool isXiangqiWebUri(Uri uri) =>
    (uri.scheme == 'http' || uri.scheme == 'https') &&
    uri.host == kXiangqiWebHost &&
    uri.userInfo.isEmpty &&
    uri.port == (uri.scheme == 'https' ? 443 : 80);

/// Check a single username segment. Callers must separately preserve whether the server exposes
/// that username; syntax is not proof that a numeric id or hidden-name placeholder is a name.
bool isXiangqiProfileName(String value) =>
    value.isNotEmpty &&
    value != '.' &&
    value != '..' &&
    !RegExp(r'[\s/\\?#\x00-\x1f\x7f]').hasMatch(value);

/// Opaque route identifiers in the captured site routes use URL-safe characters.
bool isXiangqiRouteId(String value) => RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);
