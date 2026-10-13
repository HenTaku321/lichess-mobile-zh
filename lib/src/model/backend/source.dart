/// Which online backend a piece of data came from.
///
/// The app talks to two independent services — lichess.org for chess and
/// xiangqi.com for xiangqi. They are separate accounts, separate rating pools
/// and separate game models, so this distinction belongs to the model layer
/// only: it must never be imported by `view/` or `widgets/`. A widget that
/// needed to branch on the backend would be branching on where data came from,
/// not on what to show.
enum BackendSource() {
  /// lichess.org, the origin of the chess side of the app.
  lichess,

  /// xiangqi.com, the origin of the xiangqi side.
  xiangqiCom,
}
