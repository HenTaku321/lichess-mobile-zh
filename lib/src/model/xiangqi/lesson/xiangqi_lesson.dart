import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/xiangqi/online/xiangqi_com_protocol.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_move.dart';
import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position.dart';

part 'xiangqi_lesson.freezed.dart';

/// One course topic, from `GET /api/lessons/levels`.
@freezed
sealed class const XiangqiTopic._() with _$XiangqiTopic {
  const factory({
    /// The id the topic's own page and its lessons are asked for by. A short opaque string, not a
    /// number.
    required String id,

    required String title,

    /// The level it belongs to, as the server numbers and names it.
    int? levelId,
    String? levelTitle,

    String? description,

    /// The picture the server draws the topic with.
    ///
    /// **The URL is nested**: it is `https://api.xiangqi.com/api/media/` followed by a complete S3
    /// URL, measured on 2026-10-16. This app does not draw it — see [XiangqiTopic.imageUrl], which
    /// keeps the wire value whole rather than pretending it is an image address.
    String? imageUrl,

    required int totalLessons,
    required int completeLessons,
  }) = _XiangqiTopic;

  /// Whether every lesson in the topic has been done.
  bool get isComplete => totalLessons > 0 && completeLessons >= totalLessons;
}

/// One lesson of a topic, from `GET /api/lessons/topic/<id>`.
@freezed
sealed class const XiangqiLesson._() with _$XiangqiLesson {
  const factory({
    required String id,
    required String title,
    String? description,
    String? imageUrl,
    required int order,
    required int totalChapters,
    required int completeChapters,
  }) = _XiangqiLesson;

  /// Whether every chapter of the lesson has been done.
  bool get isComplete => totalChapters > 0 && completeChapters >= totalChapters;
}

/// A topic with its lessons, from `GET /api/lessons/topic/<id>`.
@freezed
sealed class const XiangqiTopicDetail._() with _$XiangqiTopicDetail {
  const factory({required XiangqiTopic topic, required IList<XiangqiLesson> lessons}) =
      _XiangqiTopicDetail;
}

/// One chapter of a lesson, from `GET /api/lessons/lesson/<id>/chapters`.
///
/// ## What a chapter is
///
/// A position and a **script**: the moves the lesson wants played, in order, with the hints that go
/// with them. It is not a game — see [XiangqiChapter.position], which is where the position is read,
/// and `xiangqi-com-re/docs/lesson.md`, which records what the script is and what about it is not
/// pinned.
@freezed
sealed class const XiangqiChapter._() with _$XiangqiChapter {
  const factory({
    required String id,

    /// Where it sits in its lesson, counted from one.
    required int order,

    /// What the chapter is teaching, in the reader's language — the server sends it translated.
    String? description,

    /// The position the chapter starts from, or null when this app cannot read it.
    ///
    /// **Nullable, and it is the reason this app has no lesson player.** A chapter's `initial_fen`
    /// is written in xiangqi.com's own spelling, which is not the one this app's position model
    /// reads: its side letter is `r` rather than `w`, and its general is `j` rather than `k` — and
    /// `j` is not in the site's own piece set either (`pcrnbak` in its bundle), so what it stands
    /// for is inferred rather than measured. A chapter whose position cannot be read is a chapter
    /// this app shows the description of and nothing more.
    XiangqiPosition? position,

    /// The moves the chapter wants played, in order, in this repo's ICCS.
    ///
    /// The server's own list is one longer than this and starts with a placeholder — see
    /// [xiangqiChapterMovesOf] — so this is the moves themselves, with the placeholder dropped.
    required IList<XiangqiMove> moves,

    /// Whether this account has already done the chapter.
    required bool isCompleted,
  }) = _XiangqiChapter;
}

/// The topics of `GET /api/lessons/levels`, in the order the server lists them.
IList<XiangqiTopic> xiangqiTopicsFromJson(Object? json) {
  final rows = _map(json)?['topics'];
  if (rows is! List) return const IListConst<XiangqiTopic>([]);
  final topics = <XiangqiTopic>[];
  for (final row in rows) {
    final map = _map(row);
    if (map == null) continue;
    final id = _string(map['encrypted_id']);
    final title = _string(map['topic_title']);
    if (id == null || title == null) continue;
    topics.add(
      XiangqiTopic(
        id: id,
        title: title,
        levelId: _int(map['level_id']),
        levelTitle: _string(map['level_title']),
        description: _string(map['description']),
        imageUrl: _string(map['image_url']),
        totalLessons: _int(map['total_lessons']) ?? 0,
        completeLessons: _int(map['complete_lessons']) ?? 0,
      ),
    );
  }
  return topics.lock;
}

/// The topic and its lessons, from a `lessons/topic/<id>` body.
XiangqiTopicDetail? xiangqiTopicDetailFromJson(Object? json) {
  final map = _map(json);
  if (map == null) return null;
  final id = _string(map['encrypted_id']);
  final title = _string(map['topic_title']);
  if (id == null || title == null) return null;

  final lessons = <XiangqiLesson>[];
  final rows = map['lessons'];
  if (rows is List) {
    for (final row in rows) {
      final lesson = _map(row);
      if (lesson == null) continue;
      final lessonId = _string(lesson['encrypted_id']);
      final lessonTitle = _string(lesson['title']);
      if (lessonId == null || lessonTitle == null) continue;
      lessons.add(
        XiangqiLesson(
          id: lessonId,
          title: lessonTitle,
          description: _string(lesson['description']),
          imageUrl: _string(lesson['image_url']),
          order: _int(lesson['order']) ?? 0,
          totalChapters: _int(lesson['total_chaps']) ?? 0,
          completeChapters: _int(lesson['comp_chaps']) ?? 0,
        ),
      );
    }
  }

  return XiangqiTopicDetail(
    topic: XiangqiTopic(
      id: id,
      title: title,
      levelId: _int(map['level_id']),
      levelTitle: _string(map['level_title']),
      description: _string(map['description']),
      imageUrl: _string(map['image_url']),
      totalLessons: _int(map['total_lessons']) ?? lessons.length,
      completeLessons: _int(map['complete_lessons']) ?? 0,
    ),
    lessons: lessons.lock,
  );
}

/// The chapters of a lesson, from a `lessons/lesson/<id>/chapters` body.
IList<XiangqiChapter> xiangqiChaptersFromJson(Object? json) {
  final rows = _map(json)?['chapters'];
  if (rows is! List) return const IListConst<XiangqiChapter>([]);
  final chapters = <XiangqiChapter>[];
  for (final row in rows) {
    final map = _map(row);
    if (map == null) continue;
    final id = _string(map['encrypted_id']);
    if (id == null) continue;
    chapters.add(
      XiangqiChapter(
        id: id,
        order: _int(map['order']) ?? 0,
        description: _string(map['description']),
        position: xiangqiChapterPositionOf(_string(map['initial_fen'])),
        moves: xiangqiChapterMovesOf(map['moves']),
        isCompleted: map['completed'] == true,
      ),
    );
  }
  return chapters.lock;
}

/// The position a chapter's `initial_fen` names, or null when this app cannot read it.
///
/// Two translations, and both are measured:
///
/// * **The side letter is `r`, not `w`.** The site spells a red-to-move position `r` and this app
///   spells it `w`; the shipped client makes the same substitution before it hands a lesson FEN to
///   its own board (`ze.replace(" r ", " w ")` in its bundle).
/// * **The general is `j`, not `k`.** The site's own piece set is `pcrnbak` and does not contain a
///   `j` at all, so this is read as the black general because it is the only piece the lesson
///   positions are missing and the only letter they use that the set does not have. **That is an
///   inference, not a measurement** — see `xiangqi-com-re/docs/lesson.md`.
XiangqiPosition? xiangqiChapterPositionOf(String? fen) {
  if (fen == null) return null;
  final translated = fen.replaceAll(' r ', ' w ').replaceAll('j', 'k');
  try {
    return XiangqiPosition.fromFen(translated);
  } catch (_) {
    return null;
  }
}

/// The moves a chapter's script wants played, in this repo's ICCS.
///
/// **The server's list is one longer than the moves and starts with a placeholder.** Measured on
/// 2026-10-16: every chapter's first entry carries an empty `uci` and the hints for the position,
/// and the moves themselves are the entries after it — so a chapter whose script is one move long
/// has a two-entry list. The placeholder is dropped here and its hints are not read: this app has no
/// lesson player to draw them on.
IList<XiangqiMove> xiangqiChapterMovesOf(Object? rows) {
  if (rows is! List) return const IListConst<XiangqiMove>([]);
  final moves = <XiangqiMove>[];
  for (var index = 1; index < rows.length; index++) {
    final row = _map(rows[index]);
    if (row == null) continue;
    final move = xiangqiMoveFromComUci(_string(row['uci']) ?? '');
    if (move == null) continue;
    moves.add(move);
  }
  return moves.lock;
}

Map<String, dynamic>? _map(Object? value) => value is Map<String, dynamic> ? value : null;

String? _string(Object? value) {
  if (value is String) return value.isEmpty ? null : value;
  if (value is num) return value.toString();
  return null;
}

int? _int(Object? value) => value is num ? value.toInt() : null;
