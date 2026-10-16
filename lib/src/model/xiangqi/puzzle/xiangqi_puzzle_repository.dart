import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' show Client, Response;
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_auth_controller.dart';
import 'package:lichess_mobile/src/model/xiangqi/puzzle/xiangqi_puzzle.dart';
import 'package:lichess_mobile/src/model/xiangqi/quota/xiangqi_quota.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/network/http.dart' show ServerException;
import 'package:lichess_mobile/src/network/xiangqi_http.dart';
import 'package:lichess_mobile/src/network/xiangqi_uri.dart';

/// What `POST /api/puzzle/search` is asked for.
///
/// A record rather than a class because it is a family key and nothing else: the puzzle screen holds
/// one of these to say which queue it is drawing from, and two of them are the same queue exactly
/// when their fields are. The names are the wire's own, so the body is built from them without a
/// second vocabulary in between.
typedef XiangqiPuzzleSearchQuery = ({
  /// `previously_failed`: only puzzles this account has got wrong before.
  bool previouslyFailed,

  /// `previously_played`: only puzzles this account has already seen.
  bool previouslyPlayed,

  /// `rating_range`, as `[low, high]`.
  int minRating,
  int maxRating,

  /// `themes`: the theme numbers to draw from, empty for any.
  IList<int> themes,

  /// `tags`: the tag ids to draw from, empty for any.
  IList<int> tags,
});

/// The queue the puzzle screen opens on: every theme, any rating, nothing played before.
///
/// The same four answers the shipped web client opens on — see `xiangqi-com-re/docs/puzzle.md`,
/// where the `search` body it sends is written down — with the rating range widened to the whole
/// scale rather than left to a default this app has not measured.
const xiangqiDefaultPuzzleSearch = (
  previouslyFailed: false,
  previouslyPlayed: false,
  minRating: 0,
  maxRating: 3000,
  themes: IListConst<int>([]),
  tags: IListConst<int>([]),
);

/// A provider for [XiangqiPuzzleRepository].
final xiangqiPuzzleRepositoryProvider = Provider<XiangqiPuzzleRepository>((Ref ref) {
  return XiangqiPuzzleRepository(ref.read(xiangqiClientProvider));
}, name: 'XiangqiPuzzleRepositoryProvider');

/// The puzzle `id` names, from `GET /api/puzzle/P/<id>`.
///
/// ## The one endpoint in this app that charges
///
/// This is the call that spends a puzzle from the day's allowance. It is not `search`, which finds a
/// puzzle and costs nothing, and it is not `complete`, which submits an attempt and also costs
/// nothing: the charge lands here, on the first fetch of a given id, and a second fetch of the same
/// id is free. Measured on 2026-10-16 (`xiangqi-com-re/docs/quota.md`).
///
/// ## The 429 that is not a failure
///
/// Once the allowance is spent the server answers `429` — and **the body still holds the whole
/// puzzle**, with `model_answer` struck out to null. That is a position that can be looked at and
/// not solved, which is a state the screen draws; it is not an error, and this provider does not
/// turn it into one. [xiangqiPuzzleFromJson] reads it exactly as it reads a `200`, and the puzzle
/// comes back with a null [XiangqiPuzzle.solution].
///
/// A `429` **without** a puzzle in it is the other shape the server sends — `start_puzzle_race`
/// answers that way — and that one is a real refusal, so it is a [XiangqiQuotaExceededException].
///
/// **No session, no request.** The endpoint needs a token, and a device that has never signed in to
/// xiangqi.com has none; the screen offers the way in rather than this provider inventing a guest
/// account behind the user's back.
final xiangqiPuzzleProvider = FutureProvider.autoDispose.family<XiangqiPuzzle, String>((
  Ref ref,
  String id,
) {
  if (ref.watch(xiangqiAuthControllerProvider) == null) {
    throw StateError('No xiangqi.com session; not asking for puzzle $id.');
  }
  if (!ref.watch(isDeviceOnlineProvider)) {
    throw StateError('The device is offline; not asking xiangqi.com for puzzle $id.');
  }
  return ref.read(xiangqiPuzzleRepositoryProvider).fetch(id);
}, name: 'XiangqiPuzzleProvider');

/// The id of the next puzzle to solve, from `POST /api/puzzle/search`.
///
/// Null when there is none, which is what the server says with a `200` and a message rather than an
/// error: `{"message": "There's no next puzzle available"}`. A queue with nothing in it is an empty
/// queue, not a failure, and the screen says so in words.
///
/// This call does **not** spend an allowance. See [xiangqiPuzzleProvider] for where the charge is.
final xiangqiPuzzleSearchProvider = FutureProvider.autoDispose
    .family<String?, XiangqiPuzzleSearchQuery>((Ref ref, XiangqiPuzzleSearchQuery query) {
      if (ref.watch(xiangqiAuthControllerProvider) == null) {
        throw StateError('No xiangqi.com session; not asking for a puzzle.');
      }
      if (!ref.watch(isDeviceOnlineProvider)) {
        throw StateError('The device is offline; not asking xiangqi.com for a puzzle.');
      }
      return ref.read(xiangqiPuzzleRepositoryProvider).search(query);
    }, name: 'XiangqiPuzzleSearchProvider');

/// Thrown when xiangqi.com refuses a request because a daily allowance is spent.
///
/// Only for the refusals that carry nothing usable: a puzzle fetch that comes back `429` **with** a
/// puzzle in the body is a successful read and not this — see [xiangqiPuzzleProvider].
///
/// **A [ServerException], deliberately.** It is a response the server really sent, and
/// `lichessProviderRetry` does not retry one: the whole back-off would be spent re-asking a question
/// whose answer is a date. The status is the `429` it was, so a caller that only wants to know
/// "the server said no" reads it the same way it reads every other refusal.
///
/// The three fields are what the refusal carries over and above the status: `feature` is the
/// allowance that ran out, as the server names it, `remaining` is what is left of it — which the
/// server reports as zero — and `reason` is why, `"exhausted"` or `"subscription_required"`.
final class XiangqiQuotaExceededException(
  final String feature,
  final int? remaining,
  final String? reason,
  Uri url,
) extends ServerException {
  this : super(429, 'xiangqi.com refused the request: the daily allowance is spent', url, null);
}

/// The puzzle endpoints, as calls.
///
/// Reads are providers on top of this ([xiangqiPuzzleProvider], [xiangqiPuzzleSearchProvider]);
/// the calls that *change* something — submitting an attempt — are methods, because they are
/// actions a controller runs rather than values a screen watches.
class const XiangqiPuzzleRepository(final Client _client) {
  /// The puzzle [id] names.
  Future<XiangqiPuzzle> fetch(String id) async {
    final uri = xiangqiUri('puzzle/P/$id');
    final response = await _client.get(uri, headers: const {'Accept': 'application/json'});

    if (response.statusCode == 429) {
      // The one refusal that is not one. See the provider's doc comment.
      final Object? body;
      try {
        body = jsonDecode(_bodyText(response));
      } catch (_) {
        throw XiangqiQuotaExceededException(kXiangqiQuotaPuzzles, null, null, uri);
      }
      if (body is Map<String, dynamic>) {
        final puzzle = body['puzzle'];
        if (puzzle is Map<String, dynamic>) {
          final parsed = xiangqiPuzzleFromJson(puzzle);
          if (parsed != null) return parsed;
        }
        throw XiangqiQuotaExceededException(
          body['feature'] is String ? body['feature'] as String : kXiangqiQuotaPuzzles,
          _int(body['remaining']),
          body['reason'] is String ? body['reason'] as String : null,
          uri,
        );
      }
      throw XiangqiQuotaExceededException(kXiangqiQuotaPuzzles, null, null, uri);
    }

    _check(response, uri, 'xiangqi.com puzzle lookup failed.');
    final puzzle = xiangqiPuzzleFromJson(_decodeObject(_bodyText(response)));
    if (puzzle == null) {
      throw FormatException('xiangqi.com answered with a puzzle this app cannot read: $id');
    }
    return puzzle;
  }

  /// The id of the next puzzle to solve, or null when there is none.
  Future<String?> search(XiangqiPuzzleSearchQuery query) async {
    final uri = xiangqiUri('puzzle/search');
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode({
        'previously_failed': query.previouslyFailed,
        'previously_played': query.previouslyPlayed,
        'rating_range': [query.minRating, query.maxRating],
        'themes': query.themes.toList(),
        'tags': query.tags.toList(),
      }),
    );
    _check(response, uri, 'xiangqi.com puzzle search failed.');
    final json = _decodeObject(_bodyText(response));
    return _string(json['puzzle_id']);
  }

  /// Submits an attempt at [id] and reports how the server recorded it.
  ///
  /// `status` is deliberately not sent: the server recomputes it from [mistakes] and [hintsUsed],
  /// and sending one is a `400` (measured on 2026-10-16). The mode is sent because it is required,
  /// and it is [XiangqiPuzzleAttemptMode.practice] on every attempt this app makes — the challenge
  /// queue's own submit path answers `500` on the server, which is a bug on their side and not
  /// something to route around here. See `xiangqi-com-re/docs/puzzle.md`.
  Future<XiangqiPuzzleCompleteResult> complete(
    String id, {
    required int mistakes,
    required int hintsUsed,
    required XiangqiPuzzleAttemptMode mode,
  }) async {
    final uri = xiangqiUri('puzzle/$id/complete');
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode({
        'mistakes': mistakes,
        'hints_used': hintsUsed,
        'attempt_mode': mode.wireName,
      }),
    );
    _check(response, uri, 'xiangqi.com puzzle submission failed.');
    final json = _decodeObject(_bodyText(response));
    return XiangqiPuzzleCompleteResult(
      puzzleRating: _int(json['p_rating']),
      status: XiangqiPuzzleAttemptStatus.fromValue(json['status']),
    );
  }
}

/// Throws a [ServerException] unless [response] is a success.
void _check(Response response, Uri uri, String message) {
  if (response.statusCode < 400) return;
  throw ServerException(response.statusCode, message, uri, null);
}

/// The response body as text, decoded as UTF-8 whatever the headers claim.
String _bodyText(Response response) => utf8.decode(response.bodyBytes);

/// The JSON object [body] holds, or a [FormatException] if it holds anything else.
Map<String, dynamic> _decodeObject(String body) {
  final Object? json;
  try {
    json = jsonDecode(body);
  } catch (_) {
    throw const FormatException('xiangqi.com answered with something that is not JSON.');
  }
  if (json is! Map<String, dynamic>) {
    throw const FormatException('xiangqi.com answered with JSON that is not an object.');
  }
  return json;
}

/// [value] as a non-empty string, or null.
String? _string(Object? value) => value is String && value.isNotEmpty ? value : null;

/// [value] as an integer, or null. A JSON number may arrive as a double, so both are accepted.
int? _int(Object? value) => value is num ? value.toInt() : null;
