/// Which board game a feature is about.
///
/// The two games share the app, their settings and most of their screens, but not their rules,
/// their boards or their servers. This enum is the small common vocabulary the navigation and new
/// shared UI use; it deliberately does not try to describe a position or a move.
enum GameFamily() {
  chess,
  xiangqi;

  bool get isXiangqi => this == GameFamily.xiangqi;
}
