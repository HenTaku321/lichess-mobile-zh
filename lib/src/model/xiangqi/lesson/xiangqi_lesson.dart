import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
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

/// One step of a chapter's script: the move to play, and what to draw while it is being asked for.
///
/// **The first entry of a chapter's `moves` is a placeholder**, and this is why the type exists
/// rather than a bare list of moves: that entry carries no move at all and the hints for the opening
/// position, and every later entry carries the move and the hints for the position it is played in.
/// See [xiangqiChapterStepsOf].
@immutable
final class const XiangqiChapterStep({
  /// The move this step wants played, or null for the opening placeholder.
  final XiangqiMove? move,

  /// The side to move after this step, as the wire spells it (`"b"` for black), or null when the
  /// step does not say.
  ///
  /// **This is what tells the player whether the chapter plays the next step itself.** Read off the
  /// site's own player on 2026-10-19, across all 418 chapters of its thirteen topics: a step whose
  /// `next_move` names the reader's own side is a step the chapter played for the reader — after it,
  /// it is the reader's turn again — and a step that does not say at all means the reader plays the
  /// whole line by hand. See [XiangqiChapter.startSide] and
  /// [XiangqiChapterController], which is where the rule is applied.
  final String? nextMove,

  /// Arrows the chapter draws on the board for this step.
  final IList<XiangqiChapterArrow> arrows = const IListConst<XiangqiChapterArrow>([]),

  /// Points the chapter highlights for this step.
  final IList<XiangqiSquare> intersections = const IListConst<XiangqiSquare>([]),
}) {
  /// [nextMove] read as a side, or null when the step does not name one this app knows.
  ///
  /// The wire writes the two sides `"r"` and `"b"` — the same two letters a chapter's own position
  /// is written with — and the site's player reads anything else as red. Here anything else is
  /// nothing at all: a step that does not clearly say whose move comes next is a step whose next
  /// move the reader plays, which is the safe half of the two.
  XiangqiSide? get nextSide => switch (nextMove) {
    'r' => XiangqiSide.red,
    'b' => XiangqiSide.black,
    _ => null,
  };
}

/// One arrow of a chapter step: two points and the colour the chapter draws it in.
@immutable
final class const XiangqiChapterArrow({
  required final XiangqiSquare from,
  required final XiangqiSquare to,

  /// The colour the wire asks for, as `#RRGGBB`, or null when it does not name one.
  final String? color,
});

/// How a chapter decides whether a move is the one it wanted.
///
/// Two values, and the difference is not cosmetic: `single` compares the move with the script, and
/// `multi` asks the engine whether the move is good enough. See [XiangqiChapter.answerType].
enum XiangqiChapterAnswerType() {
  /// The move must be exactly the one the script names.
  single,

  /// The move is judged by the engine against the script's own line.
  multi,
}

/// One chapter of a lesson, from `GET /api/lessons/lesson/<id>/chapters`.
///
/// ## What a chapter is
///
/// A position and a **script**: the moves the lesson wants played, in order, with the hints that go
/// with them. It is not a game, and it does not have to be one — measured on 2026-10-16, a chapter's
/// script can have two red moves in a row, because it is a line being demonstrated rather than a
/// game being played. The player walks it: it plays the opponent's moves itself, and it waits for
/// the reader on the reader's own.
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
    /// A chapter's `initial_fen` is written in xiangqi.com's own spelling, which is not the one this
    /// app's position model reads: its side letter is `r` rather than `w`, and its general is `j`
    /// rather than `k`. Both are translated by [xiangqiChapterPositionOf], which is where the
    /// measurement behind them is written down. A chapter whose position still cannot be read is a
    /// chapter this app shows the description of and nothing more.
    XiangqiPosition? position,

    /// The script, the opening placeholder first — see [XiangqiChapterStep].
    required IList<XiangqiChapterStep> steps,

    /// How a move is judged.
    @Default(XiangqiChapterAnswerType.single) XiangqiChapterAnswerType answerType,

    /// Whether finishing a chapter moves on to the next one by itself.
    @Default(false) bool autoTransition,

    /// Whether the chapter wants the board turned around.
    @Default(false) bool flipBoard,

    /// The puzzle kind the chapter is filed under, when it is one.
    String? puzzleType,

    /// Whether this account has already done the chapter.
    required bool isCompleted,
  }) = _XiangqiChapter;

  /// The moves the script wants played, the placeholder dropped.
  IList<XiangqiMove> get moves => [for (final step in steps) ?step.move].lock;

  /// The side the reader plays: whoever is to move in the chapter's own position.
  ///
  /// A chapter starts with the reader to move — measured on 2026-10-19, every one of the site's
  /// chapters does — and the site's player reads the reader's side out of the position the same way
  /// (`initial_fen.includes(" r ") ? red : black` in its bundle). A chapter whose position this app
  /// cannot read has no side of its own, and red is the answer that keeps the board facing the way
  /// every other chapter's does.
  XiangqiSide get startSide => position?.turn ?? XiangqiSide.red;
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
        steps: xiangqiChapterStepsOf(map['moves']),
        answerType: switch (_string(map['answer_type'])) {
          'multi' => XiangqiChapterAnswerType.multi,
          _ => XiangqiChapterAnswerType.single,
        },
        autoTransition: map['auto_transition'] == true,
        flipBoard: map['flip_board'] == true,
        puzzleType: _string(map['puzzle_type']),
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

/// The script of a chapter, from the `moves` of a `lessons/lesson/<id>/chapters` body.
///
/// **The server's list is one longer than the moves and starts with a placeholder.** Measured on
/// 2026-10-16: every chapter's first entry carries an empty `uci` and the hints for the opening
/// position, and the moves themselves are the entries after it — so a chapter whose script is one
/// move long has a two-entry list. The placeholder is kept here, because the hints on it are the
/// ones the board draws before the first move is played; [XiangqiChapter.moves] is what drops it.
IList<XiangqiChapterStep> xiangqiChapterStepsOf(Object? rows) {
  if (rows is! List) return const IListConst<XiangqiChapterStep>([]);
  final steps = <XiangqiChapterStep>[];
  for (final row in rows) {
    final map = _map(row);
    if (map == null) continue;
    steps.add(
      XiangqiChapterStep(
        move: xiangqiMoveFromComUci(_string(map['uci']) ?? ''),
        nextMove: _string(map['next_move']),
        arrows: _arrowsOf(map['arrows']),
        intersections: _squaresOf(map['intersections']),
      ),
    );
  }
  return steps.lock;
}

/// The arrows of one step.
///
/// A point is written `{c: "i", r: 10}` — a file letter and a rank counted from **one**, the same
/// spelling the moves use — and an arrow whose ends are not both on the board is dropped rather than
/// drawn at a point that does not exist.
IList<XiangqiChapterArrow> _arrowsOf(Object? rows) {
  if (rows is! List) return const IListConst<XiangqiChapterArrow>([]);
  final arrows = <XiangqiChapterArrow>[];
  for (final row in rows) {
    final map = _map(row);
    if (map == null) continue;
    final from = _pointOf(map['c1'], map['r1']);
    final to = _pointOf(map['c2'], map['r2']);
    if (from == null || to == null) continue;
    final type = _map(map['type']);
    arrows.add(XiangqiChapterArrow(from: from, to: to, color: _string(type?['color'])));
  }
  return arrows.lock;
}

/// The highlighted points of one step, in the same `{c, r}` spelling the arrows use.
IList<XiangqiSquare> _squaresOf(Object? rows) {
  if (rows is! List) return const IListConst<XiangqiSquare>([]);
  final squares = <XiangqiSquare>[];
  for (final row in rows) {
    final map = _map(row);
    if (map == null) continue;
    final square = _pointOf(map['c'], map['r']);
    if (square != null) squares.add(square);
  }
  return squares.lock;
}

/// The point a `(file letter, rank from one)` pair names, or null when it is not one.
XiangqiSquare? _pointOf(Object? file, Object? rank) {
  final letter = _string(file);
  final number = rank is num ? rank.toInt() : null;
  if (letter == null || letter.length != 1 || number == null) return null;
  final index = letter.codeUnitAt(0) - 0x61;
  if (index < 0 || index > 8 || number < 1 || number > 10) return null;
  return XiangqiSquare.at(index, number - 1);
}

Map<String, dynamic>? _map(Object? value) => value is Map<String, dynamic> ? value : null;

String? _string(Object? value) {
  if (value is String) return value.isEmpty ? null : value;
  if (value is num) return value.toString();
  return null;
}

int? _int(Object? value) => value is num ? value.toInt() : null;
