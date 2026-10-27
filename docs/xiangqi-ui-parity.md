# 象棋 UI 与 Lichess 的源码对照记录

## 基准、边界与当前进度

- 基准为当前工作区 Lichess App 与已解析依赖 `chessground-10.3.0`，不是 xiangqi.com 网页。
- 本文记录第一、第二批源码整改和最终交接边界。**不是全量 UI 已一致的验收报告**。
- 本机只执行 Dart 分析、格式和 diff 检查；不运行编译、Widget 测试、Go 测试或 codegen。
- 原有未提交改动保留；棋子厚边、渐变、高光材质不是本次新增，不属于应当删除的差异。
- 所有“已改”均指源码修改；新增测试未执行，也未做像素截图或真机声音/触觉验收。

## 已落实的源码差异

| 项目 | 基准证据 | 象棋整改 |
|---|---|---|
| 走子方式 | `BoardPrefs.toBoardSettings`、chessground `board.dart` | `XiangqiBoardSettings.fromPreferences` 集中映射点选/拖拽、松手走子、标注与高亮；编辑器使用独立编辑/拖动模式 |
| 点击提交时机 | 默认在目标 pointer down 提交；`moveOnRelease` 在 pointer up 提交 | 使用 `Listener`，区分选择、拖动、松手目标，不再统一等 tap up |
| 拖动阈值/鼠标 | chessground 3px 阈值；触控放大 2 倍并上移一格；鼠标不放大、目标为方框 | 对齐以上参数；多指取消走子；按可移动方拒绝拖起对方棋子 |
| 拖动提交 | chessground 的单次 `onMove(...viaDragAndDrop)` | 游戏、在线局、分析、课程与谜题改用直接 move 接口，不再两次 `tapSquare`；修正重复点选取消 |
| 高亮 | `GameLayout._gameDataFor` 将 check 置于 `boardHighlights` 之下 | 关闭高亮时不再绘制将军光晕；保留 `lastMove` 作为动画输入；选择与拖起重合时不重复叠加底色 |
| 已确认的拖动 | chessground `recordDropMove`；GameController 的拖动反馈不等动画 | 本地拖动不再重复平移动画；在线局只在确认帧后反馈，附带 `viaDragAndDrop`；快照仍不反馈 |
| 手绘标注 | chessground 空格一指锁定、第二指绘制，200ms 双击清除 | 新增本地圆圈/箭头；与课程/引擎标记分离，使用现有颜色偏好，不改变协议 |
| 预走 | chessground 几何目标 + 执行时重新验证 | 在线每局独立队列；只在对手增量确认后重新验证合法性与起点棋子，消耗队列后发送一次普通走子；快照/断线/结束/离开实时位置/身份变化清理 |
| 横屏棋盘 | `GameLayout` 的可用高度、250px 侧栏阈值、黄金比例回退 | 替换无条件黄金比例上限；计入评估条占宽，尺寸非负；竖屏预留空间按文字缩放增加 |
| 圆角与边距 | `GameLayout` 实际只给平板圆角/阴影，横屏手机也不加 | 保留该逻辑，纠正原来声称“所有横屏都加圆角”的注释；仍复用 `MoveList`/`BottomBar` |
| 评估条 | `EngineGauge` 的 800ms `Curves.ease`、字号、黑白字、缓存分数 | 新增 tween、结束局面输入、disabled 外观；沿用 `ExternalEval.evalString` 保留负 mate 符号；语义区分 label/value |
| 玩家行/时钟 | `GamePlayer` 的 7:3 空间、名字 tooltip、clockPosition；共享 `Clock` | 接入左右时钟位置、限制时钟占宽、名字/等级省略；在线保留亚秒余量并读取 clockTenths 偏好 |
| 房间聊天 | `ChatScreen` 的 0.9 宽度、secondary/surfaceContainerHigh、16px 圆角、输入框 | 对齐气泡/输入框，复用长按复制与链接文字；发送按钮随输入变化、发送中禁用；保留草稿 |
| 私信 | `ConversationScreen` 的 0.85 宽度、16/4px 连续消息圆角、时间占位 | 增加同日连续发送者分组、时间占位防覆盖、长按复制与链接；发送结果返回 bool，失败保留草稿并提示，不同帧双发受限 |
| 空列表刷新 | 共享 RefreshIndicator/ListView 行为 | 观战/通知空列表仍可下拉刷新；课程、赛事、保存、聊天列表不足一屏也可刷新 |

### 预走的合理例外

同机双人 OTB 没有固定“我的一方”，对应 Lichess 的 `PlayerSide.both`；不引入一个可能替另一位玩家自动走棋的队列。预走仅用于在线固定身份实战。分析、课程、谜题、复盘和编辑器不启用预走。

九路十行、宫线、河界、红黑棋子与象棋走法保留。课程允许脚本连续走同一方，直接 move 校验使用课程已有 `pieceMoves`，而不是强行采用实战 turn 规则。

## 全页面源码覆盖与验收边界

这里区分源码接线、回归用例和实际视觉验收。下表不是截图对照结果，也不表示每个
页面的所有字号、状态颜色、间距和系统交互均已获得逐项运行验证。

| 页面组 | 对照对象 | 源码落实与保留边界 |
|---|---|---|
| 人机/同机双人/在线对局 | offline_computer、over_the_board、game | 共享棋盘、直接走子、结果弹窗、低时间阈值/提示音、face-to-face 棋子朝向已接线；真实声音、触觉和截图仍待运行验收 |
| 分析/复盘/数据库棋谱 | analysis、explorer | 已使用独立 `XiangqiAnalysisLayout` 对齐 header/footer、引擎行、评估条与下方分区；真实像素仍待运行验收 |
| 谜题/课程播放 | puzzle、practice、learn | 已区分提交中/已记录/未记录，自动下一题共用 Lichess 设置并等待新题成功；课程保存失败可重试，声音/动画仍待运行验收 |
| 棋盘编辑器/过滤器 | board_editor | 已支持调色盘拖入、棋盘外拖出删除、幂等替换和互斥编辑模式；拖动 overlay 裁切仍待运行验收 |
| 房间聊天/私信 | chat、message | 已对齐气泡、输入、复制、链接与草稿；补失败回滚、退出清草稿、订阅重建和账号代际用例，尚未执行 |
| 观战/进行中预览 | watch、home 预览 | 空列表刷新、缩略棋盘设置和 BOT 名称已改；列表/卡片的细分视觉 token 未作全量运行对照 |
| 新建棋局 | play | 复用 PlaySetupButton；表单按账号代际重建，旧取消匹配不作用于新账号，picker 检查 mounted；键盘/路由过渡待运行验收 |
| 好友/通知 | relation、消息 hub | 已覆盖搜索条件缓存失效、接受好友同步刷新、空列表刷新、错误行重试和长名字省略 |
| 资料/编辑资料/排行榜 | user、account | 资料编辑保留草稿、保存时禁用输入、归属绑定账号 id/代际且只绑定一次；账号删除确认防重复，排行榜可刷新且国家选择取消不清筛选；细分视觉 token 待运行验收 |
| 保存/文件夹 | study、列表/编辑对话框 | 已补确认删除、非空名称校验、保存中/失败状态、账号代际保护和整棵 family 缓存刷新 |
| 课程目录/主题/章节 | learn、practice | 复用 ListSection；主题/章节支持刷新与错误重试，保存成功后才刷新课程进度；进度图标/标题层级尚无运行对照记录 |
| 赛事列表/详情 | tournament | 复用 ListSection；不足一屏可刷新，详情补刷新/错误重试；名次/配对行尚无运行对照记录，不猜测未确认的报名协议 |
| 登录/注册 | auth | 保留既有会话和防重复提交修复，列表拖动隐藏键盘；多步表单、键盘、安全区和错误态仍待运行验收 |

## 跨层契约

- xiangqi REST 使用 `XiangqiClient` 直连 `api.xiangqi.com`，Socket 使用独立 Socket.IO transport。Lichess 翻译代理不在这条路径上。
- `X-Zh-Token` 只是可提取的客户端门禁，不是身份或预算安全边界；已纠正客户端常量注释。
- 本次未重写上一轮 HTTP/session/socket 的加固，不修改 wire shape、secure-storage JSON 或生成模型。
- 新增 `proxy/ui_contract_test.go`，约束认证/限流/上游错误的状态、body、Retry-After 与认证头不被翻译，且未知 xiangqi/socket 路径不进入翻译器；测试未执行。

## 第二批已落实的源码整改

- 新增 `XiangqiAnalysisLayout`，分析、复盘、数据库棋谱改用分析型响应式布局；采用 26px header/footer 并计入文字缩放，接入小棋盘/棋盘左右偏好、引擎行和横竖屏评估条；单面板不画 TabBar，象棋分析的 MoveList 不再嵌套 Card。
- 分数显示复用 `ExternalEval.evalString`，PV 和评估条都保留负 mate 的符号；复盘使用紧凑玩家行，数据库玩家信息采用单行，避免被 header 高度裁切。
- 新增 `XiangqiResultDialog`；三类对局结果共用 Lichess 风格的 `Dialog` 宽度、分数和说明。在线按钮等待 1 秒后激活并采用 400ms 过渡，弹出和反馈定时器检查页面焦点、路由及当前局面。
- OTB 接入已有 `overTheBoardPreferencesProvider` 的翻转/盲棋语义，禁用手绘标注与预走，并让棋子、玩家行和棋盘朝向同步。
- 编辑器支持调色盘 `Draggable<XiangqiPiece>`、棋盘外拖出删除、外部放置替换；新增幂等 `placePiece`，不会把相同棋子误删。
- 低时间阈值抽为 `xiangqiEmergencyThreshold` 与 `XiangqiLowTimeWarning`：初始秒数的 12.5%，限制在 10～60 秒，20 秒冷却，恢复至阈值的 1.5 倍后重新 armed。人机/在线仅提示正在实战的我方；在线初始控制不确定时保留 30 秒 fallback，OTB 不新增提示音。
- 谜题回复延迟改为 500ms；提交中不可点下一题。共享 `puzzlePreferencesProvider.autoNext`，只在服务端返回纯 `solved` 后自动推进一次；搜索、取题和非空 solution 均成功后才换棋盘，失败/空队列/quota 保留完成棋盘供手动重试，同 id 新题也使用独立 attempt。
- 课程保存增加 `XiangqiLessonSaveState` sidecar，区分本地完成、保存中、保存失败和已保存；失败可重试且不撤棋，撤销忽略旧回包。自动跳转同时等待独立 2 秒阅读暂停与保存成功，晚保存不重新计时；离页、撤销、换章节或换号取消自动跳转。
- 新增 `accountGeneration`：恢复账号、换账号/游客身份和退出重登录改变代际；token 轮换和改名不改变。课程、保存、好友和可编辑资料读取观察代际，新建棋局/私信草稿不跨账号复用。
- 私信 build 在第一次 await 前观察身份，收到消息和异步回包检查 build 代际；dispose 只取消本次局部订阅。仓库与联系人列表不因同账号 token 轮换重建/重载，退出登录仍清空会话界面。
- 资料编辑页仅首次绑定账号 id/代际，同名新账号与同账号退出重登录均不能接管旧表单；改名等待存储时维持原归属，保存异步边界再次检查 mounted/代际。
- 好友接受/删除和保存文件夹操作失效整个 family 缓存。文件夹补删除确认、名称非空验证、busy/失败留草稿、嵌套新建和空目录刷新；资料编辑错误本地化，排行榜国家选择取消保留筛选。

## 已新增或补充的回归用例（未执行）

以下路径以 `mobile/` 为根；仅列本次象棋整改的关键覆盖，不包含其他原有 WIP。

| 覆盖 | 测试源码 |
|---|---|
| 输入时机、直接走子、拖动/外部放置与取消、OTB 朝向 | `test/widgets/xiangqi_input_parity_test.dart`、`test/widgets/xiangqi_board_test.dart`、`test/model/xiangqi/xiangqi_direct_move_test.dart`、`test/model/xiangqi/xiangqi_board_editor_controller_test.dart`、`test/view/xiangqi/xiangqi_board_editor_screen_test.dart` |
| 在线预走 | `test/model/xiangqi/xiangqi_premove_test.dart`、`test/model/xiangqi/online/xiangqi_premove_controller_test.dart` |
| 布局边界、文字缩放、评估条、结果按钮定时/销毁 | `test/widgets/xiangqi_analysis_layout_test.dart`、`test/widgets/xiangqi_result_dialog_test.dart`、`test/widgets/xiangqi_ui_parity_test.dart` |
| 低时间阈值与反馈 | `test/model/xiangqi/xiangqi_clock_warning_test.dart`、`test/view/xiangqi/xiangqi_feedback_regression_test.dart` |
| 谜题提交、共享 autoNext、失败保棋盘、提示题不自动推进 | `test/model/xiangqi/puzzle/xiangqi_puzzle_controller_test.dart`、`test/view/xiangqi/xiangqi_puzzle_screen_test.dart` |
| 课程保存失败重试、撤销忽略回包、晚保存不重计阅读暂停 | `test/model/xiangqi/lesson/xiangqi_lesson_save_test.dart`、`test/view/xiangqi/xiangqi_lesson_player_screen_test.dart` |
| 文件夹验证/失败留草稿/删除确认、好友搜索刷新、国家选择取消 | `test/view/xiangqi/xiangqi_saved_friends_parity_test.dart`、`test/view/xiangqi/xiangqi_leaderboard_screen_test.dart` |
| 资料失败留草稿、改名慢存储、同名新账号/退出重登录隔离 | `test/view/xiangqi/xiangqi_profile_edit_screen_test.dart` |
| 私信发送失败回滚/留草稿、退出清输入、加载中换身份、订阅重建、token 轮换保留联系人 | `test/view/message/xiangqi_conversation_screen_test.dart`、`test/model/message/xiangqi_conversation_controller_test.dart` |
| 会话/请求边界、新账号不受旧取消匹配影响 | `test/network/xiangqi_hardening_test.dart`、`test/network/xiangqi_http_test.dart`、`test/view/xiangqi/xiangqi_new_game_screen_test.dart` |

测试使用现有规则引擎构造棋局、假 Socket 帧和 HTTP 层 mock；布局用例检查几何边界及
组件属性，**不是 golden 或截图测试**。未执行红/绿回归循环，不能据此声称问题已在运行环境复现并消除。

## 验证与交接

本机仅直接调用现有 Dart SDK，不使用 Flutter wrapper、不下载依赖、不执行 codegen。
检查清单包含当前工作区修改/新增的非生成 Dart 文件（包括原有暂存 WIP）；生成文件和
大型合并源码/zip 不参与检查，不能把 analyzer 成功解释成测试通过。

2026-10-27 最终复跑结果：

- `dart analyze`：90 个文件，`No issues found!`，退出码 0。
- 只读格式检查：`Formatted 90 files (0 changed)`，退出码 0。
- 工作区与暂存区 `git diff --check` 均无错误；新增源码/测试/文档通过尾随空白和冲突标记检查。
- 暂存区 diff 与两份自审检查点逐字节一致，本轮没有暂存、提交或覆盖原有 WIP。
- 本地测试、编译、codegen、截图/声音/触觉验收均未执行。

临时检查清单和日志位于 `/tmp/chess-ui-parity-final/`：`dart-files-final.txt`、
`analyze-final.log`、`format-final.log`、`diff-final.log`。临时目录清理后可用下列入口重建。

复查入口：

```sh
cd /home/hentaku/go/src/chess/mobile
mkdir -p /tmp/chess-ui-parity-final
{ git diff HEAD --name-only --diff-filter=ACMR; git ls-files --others --exclude-standard lib test; } |
  LC_ALL=C sort -u | awk '/\.dart$/ && !/\.(g|freezed)\.dart$/' \
  > /tmp/chess-ui-parity-final/dart-files-final.txt
xargs -d '\n' /usr/bin/dart analyze < /tmp/chess-ui-parity-final/dart-files-final.txt
xargs -d '\n' /usr/bin/dart format --output=none --set-exit-if-changed \
  < /tmp/chess-ui-parity-final/dart-files-final.txt
git diff --check
git diff --cached --check
```

运行验收仍需在用户允许的构建/运行环境完成：

- 纵横屏、手机/平板、2 倍文字缩放的实际布局和逐页截图对照；不能因共享组件就推断全页面像素一致。
- 触控/鼠标拖动、外部拖入/拖出、overlay 裁切、多指取消和系统动画偏好。
- 真机声音、触觉、低时间提示、结果弹窗延迟及页面焦点变化。
- 执行上表回归用例，再验收刷新/断网/保存失败/换号/重连的完整交互。

本轮不提交、不合并、不部署；暂存区保持原样。自审快照是中途检查点，不是最初工作区基线。
