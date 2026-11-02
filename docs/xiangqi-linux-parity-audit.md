# 象棋 Linux 全页面一致性审查

## 范围与证据（2026-11-02）

- 基准是本项目国象界面，不是照搬 xiangqi.com 网站。
- 工作树 `mobile-xiangqi-parity`，审查基线 `d2f89a627`；生产代码等同 `4bd6c07cf`。
- 完整实施顺序：`docs/plans/2026-11-02-xiangqi-linux-systematic-audit.md`。
- 本表覆盖页面、Hub、菜单、弹层、预览和内容链接。**清单完整不等于全部行为已验收。**
- 本轮 Actions 已证实下列 R 项；旧 Actions `41380249454` 的绿只作为历史回归基线。
- 安装包与源码不是同一基线；不根据用户已安装包推断最新代码已经验收。

证据等级：

| 标记 | 含义 |
|---|---|
| S | 已定位源码边界；尚未证明运行时影响 |
| R | 同 SHA 的 Actions 真实输入链复现失败 |
| G | 同一行为红 → 最小实现 → 同 SHA 绿 |
| P | 同阶段配对渲染／几何原始证据，不含主观认可 |
| N | Linux 隔离原生操作、输入／焦点／剪贴板／引擎证据 |
| U | 用户按组主观确认 |

不支持看图时不能写“我看过且一致”。本轮 P、N、U 全部尚待建立；iPhone 真机后置。

## 全页面与状态矩阵

每个适用页面要覆盖：正常非空（正常）、空结果（空）、首次加载（加载）、局部/完整失败（失败）、重试、详情返回（返回）、换号/退出/续 token（身份）。
下表列的是**待验收状态**；“本地页”不要求伪造网络加载/失败，“公开页”仍检查换号不会让旧异步操作导航。

### A. 首页、入口、账号（14 个入口角色）

| 入口角色 | 源码／国象参考 | 待验收状态及已登记差异 |
|---|---|---|
| 首页与进行中卡片 | `home/home_tab_screen.dart`、`home/games_carousel.dart`；同页 | 正常/空/加载/失败/重试/返回/身份；消息提示目前偏国象，进行中卡片角色检查 B6 |
| Play 菜单／新局入口 | `play/play_menu.dart`、`play/play_bottom_sheet.dart`；同菜单 | 正常/离线禁用/弹层返回/身份；不能用国象 Socket 健康决定象棋能力 |
| More 工具入口 | `more/more_tab_screen.dart`；同页 | 正常/离线/返回/身份；账号区 inbox 依赖国象账号（B3） |
| Analysis Hub | `analysis/analysis_hub_screen.dart` | 正常/引擎不可用/返回；象棋缩略图坐标/亮度/hue 不对称（B6） |
| Board Editor Hub | `board_editor/board_editor_hub_screen.dart` | 正常/返回；缩略图同角色偏好（B6） |
| Tournaments Hub | `play/tournaments_hub_screen.dart` | 正常/空/加载/单源失败/重试/返回/身份；折叠与统计不得把错误当零 |
| Friends Hub | `relation/friends_hub_screen.dart` | 正常/游客/空/加载/单源失败/重试/返回/身份；评分偏好及进入完整列表（B5/B9） |
| Leaderboard Hub | `user/leaderboard_hub_screen.dart` | 正常/空/加载/部分速度失败/重试/返回；评分偏好（B5） |
| Watch Hub | `watch/watch_games_hub_screen.dart` | 正常/空/加载/单源失败/重试/返回；名字可链接性和观战评级（B5/B14） |
| 账号菜单 | `account/account_menu.dart`；同页 | 未登录/游客/正式/资料局部失败/离线/返回/身份；B3/B5 |
| 象棋登录 | `auth/xiangqi_login_screen.dart`；国象登录只比表单角色 | 正常/校验/忙碌/失败/重试/返回/身份；不伪造两种认证流程完全一样 |
| 注册三步／国家选择 | `xiangqi/xiangqi_signup_screen.dart`；共用表单/弹层 | 空字段/加载/验证码失败/返回/重试/重复提交/身份；不触发真实注册 |
| 全局设置／主题预览 | `settings/account_preferences_screen.dart`、`theme_settings_screen.dart` | 本地偏好/加载/失败/保存/返回；隐藏评分、坐标/布局/动画/声音贯彻 |
| 账号／公开内容链接 | `service/xiangqi_links_service.dart`；同站内路由角色 | 正常/未知URL/危险协议/旧路由/未选标签/身份；既有边界回归必须保留 |

### B. 对弈、观战与预览（8 个角色）

| 页面／弹层 | 源码／参考 | 待验收状态及已登记差异 |
|---|---|---|
| 人机棋盘／走子评估 | `xiangqi_game_screen.dart`；`game/computer_game_screen.dart` | 新局/轮流落子/回看/撤销/提示/引擎错误/返回；好着错着卡片持续至下一用户输入，旧回归不代表全视觉一致 |
| 人机新局／菜单／结果 | 同文件；国象人机菜单/结果 | 忙碌/重复点/禁用/返回/新局/自定义 FEN；不误重置原树 |
| OTB 棋盘 | `xiangqi_over_the_board_screen.dart`；国象 OTB | 新局/计时/暂停/回看/盲棋/翻转/撤销/返回；鼠标与触摸分别验收 |
| OTB 配置／菜单／结果 | 同文件；国象 OTB 弹层 | 正常/取消/无合法步/自定义 FEN/二次确认/返回 |
| 新在线局／对手搜索 | `xiangqi_new_game_screen.dart`；共用 Create game 角色 | 游客/正式/校验/加载/无结果/超时/重试/取消/身份；保留已确认协议，不猜 rated 匹配能力 |
| 在线实战／观战详情 | `xiangqi_online_game_screen.dart`；国象在线局 | 正常/首次加载/断网/刷新/拒绝落子/预走/对局结束/返回/身份；错误文案目前可能 raw exception（B14） |
| Watch 列表 | `xiangqi_watch_screen.dart`；国象 live game 列表 | 非空/空/加载/失败/重试/打开返回；独立玩家评级直接显示（B5） |
| 进行中紧凑／轮播预览 | `xiangqi_ongoing_game_preview.dart`；国象 game preview/carousel | 正常/轮到我/不同主题/隐藏评分/缩放/打开返回；缩略图偏好（B6） |

### C. 训练、复盘、分析与数据库（13 个角色）

| 页面／弹层 | 源码／参考 | 待验收状态及已登记差异 |
|---|---|---|
| 题目搜索／加载 | `xiangqi_puzzle_screen.dart`；国象题目入口 | 无账号/非空/空队列/加载/失败/quota/重试/身份 |
| 题目解题／完成／回看 | 同文件；国象 puzzle_screen | 正确/错误/提示/成功/提交慢与失败/autoNext/历史/返回；B5/B7 |
| 课程目录 | `xiangqi_lessons_screen.dart`；共用列表 | 正常/空/加载/失败/重试/语言/返回/身份 |
| 课程专题 | `XiangqiTopicScreen`（同文件） | 同上，独立详情错误不可伪装为已完成 |
| 课程章节列表 | `XiangqiLessonScreen`（同文件） | 同上，当前章节/完成徽标/重复入口 |
| 课程播放／章节表／保存 | `xiangqi_lesson_player_screen.dart`；共用训练呈现 | 正确/错误/非法教学图/历史/保存慢与失败/重试/下一章/离页/身份；保留 acceptedMoves 与教学只读契约 |
| 归档棋局复盘 | `xiangqi_review_screen.dart`；国象 replay/analysis | 正常/加载/不支持棋谱/失败/重试/历史/完整交接/返回；B5 |
| 普通与导入分析／分支树 | `xiangqi_analysis_screen.dart`、`xiangqi_analysis_tree_view.dart` | 空线/主线/分支/切换/删除/提升/引擎失败/继续/返回；直接非法普通图安全边界（B1） |
| 分析菜单／设置／导出 | `xiangqi_analysis_actions.dart`、`xiangqi_analysis_settings_screen.dart` | 能力禁用/忙碌/复制失败/菜单返回/布局/棋谱/声音/引擎开关；不能只保护教学来源（B1） |
| 编辑器／调色盘／过滤器 | `xiangqi_board_editor_screen.dart`、`xiangqi_board_editor_filters.dart` | 空图/非法图/合法图/点选/拖出/替换/复制/导入/出口/返回；B1 |
| 数据库搜索／分页 | `xiangqi_database_screen.dart` | 正常/空/加载/页失败/重试/筛选/返回/语言；已有页码控件，仍需锚点与旧结果验收 |
| 数据库玩家／统计／棋谱列表 | `XiangqiMasterPlayerScreen`（同文件） | 同上/统计局部失败/棋谱分页/返回 |
| 数据库单棋谱 | `XiangqiMasterGameScreen`（同文件） | 正常/加载/错误棋谱/重试/完整分析交接/复制/返回 |

### D. 资料与社交目录（9 个角色）

| 页面／弹层 | 源码／参考 | 待验收状态及已登记差异 |
|---|---|---|
| 个人与他人资料 | `xiangqi_profile_screen.dart`；国象 profile | 正常/用户不存在/加载/局部统计失败/重试/返回/身份；B5/B12 |
| 资料编辑／国家／改名 | `xiangqi_profile_edit_screen.dart`；国象 edit_profile | 校验/国家加载失败/忙碌/失败留草稿/慢存储/返回/身份；已有归属防护需保留 |
| 账号退出／删除确认 | `xiangqi_profile_screen.dart`；共用危险操作确认 | 密码错误/取消/失败/忙碌/身份；不对真实账号做破坏性验证 |
| 资料棋局记录 | `_RecentGames`（同文件）；国象 game records | 正常/空/局部失败/页2/尾页/重试/复盘返回；实际固定 page=1（B12） |
| 排行榜／国家过滤／页码 | `xiangqi_leaderboard_screen.dart`；国象 leaderboard | 正常/空/加载/失败/重试/切速度/取消国家/页码/返回；B5 |
| 赛事目录 | `xiangqi_tournaments_screen.dart`；国象 tournament hub | 已结束/进行中/空/加载/失败/重试/返回 |
| 赛事详情／排名／参赛者 | `XiangqiTournamentScreen`（同文件）；共用详情分区 | 正常/空/某分区失败/页2/重试/返回；固定排名第一页（B11），未知 pairing 不猜功能 |
| 好友／申请／搜索／操作 | `xiangqi_friends_screen.dart`；国象 relation 角色 | 非空/空/加载/申请局部失败/页2/搜索/重试/操作忙碌/返回/身份；B5/B9 |
| 保存／目录／嵌套文件夹 | `xiangqi_saved_screen.dart`；共用 list/form/确认角色 | 题目/笔记/空/加载/局部失败/重试/新建/重命名/删除/返回/身份；评分偏好（B5） |

### E. 消息、房间与通知（5 个角色）

| 页面／入口 | 源码／参考 | 待验收状态及已登记差异 |
|---|---|---|
| 合并联系人／搜索 | `message/contacts_screen.dart`；同页 | 非空/空/加载/单源失败/双方失败/重试/页2/双击/返回/身份；B2/B4/B8/B10/B16 |
| 象棋私信／输入／菜单 | `message/xiangqi_conversation_screen.dart`；国象 conversation | 正常/空/加载/更多失败/发送失败/重试/草稿/复制/链接/返回/身份；B8，已有共用气泡不等于分组配对验收 |
| 房间目录 | `xiangqi_chat_screen.dart` | 非空/空/加载/失败/重试/返回/身份 |
| 房间消息／历史／输入 | `XiangqiChatRoomScreen`（同文件）；国象 chat | 正常/空/更多失败/发送失败/重试/草稿/复制/链接/返回/身份；分页已独立，滚动锚点待验收 |
| 通知／全标已读／链接 | `xiangqi_notifications_screen.dart`；共用通知角色 | 正常/空/加载/失败/页2/重试/mark失败/重复点/返回/身份；B13，不猜未确认的偏好写接口 |

上述 49 个角色包含同文件内子页面与弹层；每一组的原生/主观结论仍未验证。

## 根因问题台账

优先级：P0 身份/棋局错乱与崩溃风险；P1 操作/功能与偏好违约；P2 视觉/文案/反馈。来源冲突时先复现最早不确定边界。

| ID | 优先级／证据 | 根因与源码边界 | 最小复现与期望 |
|---|---|---|---|
| B1 | P0 / R | 编辑器 `_BottomBar` 仅 `pieceCount > 0`；分析 `positionError` 仅验证 teaching；公共 continue menu 不防任意图 | 缺黑将图点击分析/继续，或直接普通分析传同图；引擎不搜索、继续不可用，有明确原因；合法初始图不受限 |
| B2 | P0 / R | Contacts 的两次 `await Navigator.push` 后无 mounted/身份 guard；dispose 不释放 controller/focus | 联系人推对话、移除父路由、返回；无已卸载 ref 访问；换号后旧回调不改新状态 |
| B3 | P1 / R | account_menu inbox 条件只含国象 user/account；More inbox 位于 `if (user != null)` | 只登录象棋正式账号，两处入口可打开合并联系人；游客不冒充正式，国象儿童限制不绕过 |
| B4 | P1 / R | Contacts 无导航 gate，`_refreshAfterConversation` 无条件清查询/focus | 注册行回调两次仅一页；同账号返回保留搜索与位置，旧 callback 不清新输入 |
| B5 | P1 / R（部分） | PlayerRow、Watch、题目、好友、排行榜、资料、保存和账号 subtitle 的评级直接 Text | 真实 ShowRatings.no 不泄露评分；已复现玩家行、观战、排行榜、账号、资料及最高评分、题目与保存；好友/Hub及实战例外仍待专项 |
| B6 | P1 / R（坐标） | Analysis/Editor Hub 象棋预览未完整映射亮度/hue，坐标与国象缩略图相反 | 两个 Hub 坐标违约已复现；无坐标/交互及亮度/hue最终检查待绿；长宽比差异明确保留 |
| B7 | P1 / R（分析入口） | 题目完成栏只在菜单给分析、残留 disabled Hint，Next 图标另起契约 | 完成态缺直接 Analysis 已复现；完整按钮组合/继续图标/进行态权限待绿 |
| B8 | P0/P1 / S | Inbox 固定第1页并丢信封；messages 无 page；待办仅 chatId；超时后旧同通道帧可能匹配下一请求 | 两页请求不合并为一个；A 超时 B 排队 A 迟到，B 不接 A；对局独立连接不被断开 |
| B9 | P1 / S | Friends provider 固定 `page:1`，模型已有 nextPage，页面无更多 | 筛选第2页/尾页/失败原页重试；换号清私有内容，搜索重置页但不丢申请分区 |
| B10 | P1 / S | 合并 contacts 任一来源异常时静默移除该来源内容；搜索/首次失败 raw 英文异常；Linux 无显式刷新 | 一来源失败保另一来源，并给可重试提示；不伪装为空、泄露异常或强行显示后台品牌 |
| B11 | P1 / S | 赛事排名固定 `leaders((id,1))`，真实 endpoint 接受 page | 加载第2页/尾页/局部错误后重试；比赛基本信息和参赛者不一起消失 |
| B12 | P1 / S | Profile `_RecentGames` 固定 `history((username,1))`，无状态/页控件 | 页2可达，返回复盘保页/位置；统计加载失败不遮全资料；纠正旧交接中“已有分页”的误记 |
| B13 | P0/P1 / S | 通知 `FutureProvider` 发空 data，仅按 success 名 firstWhere，共用对局 Socket，无分页串行 | 并发刷新/更多/mark不会串包；超时后独立通道重建，页2实际可达 |
| B14 | P2 / S | 在线 `_Failed(message: error.toString())` 与零散名单呈现没有共用错误/可链接身份契约 | 网络失败显示可读本地化并可重试，游客/机器人不出现假资料入口；unknown URL保留原查询/片段 |
| B15 | P1 / S | 旧 screenshot `scale` 是 TextScaler，输出 `toImage()` 无 pixelRatio；大多只有象棋场景 | 字缩放/DPI独立命名与输出；每个布局角色同阶段配对，不冒称1032张就是完整验收 |
| B16 | P1 / S | Contacts 搜索只调用国象 `/inbox/search`，body 搜索分支还要求国象 `me != null` | 只登录象棋账号输入搜索目前没有对应效果；必须明确真实可用搜索范围，不猜 `inbox.others` 响应或新会话协议 |
| B17 | 共同问题 / S | `UserFullNameWidget` 在评分偏好加载/错误时默认显示数字，`RatingPrefAware` 则先隐藏 | 冷启动的原始加载帧需配对检查；本批不擅自改国象姓名组件的 fallback 行为 |

## 新证据记录

| 批次／SHA | 复现与回归 | 渲染/原生/主观 | 结论 |
|---|---|---|---|
| 审查 / `d2f89a627` | 仅源码边界 S，未跑新测试 | P/N/U未验证 | 可开始优先项的真实红测试，不表示修复或一致 |
| 首轮红 / `0eb86a4ea` / Actions `41385753695` | analyze通过；非法图实际出现 `position fen 9/9/9/9/9/9/9/9/9/4K4 w - - 0 1`；编辑器出口可点击；联系人返回清 `chab`、卸载后访问 ref；两处单账号入口缺失 | P/N/U未验证 | B1/B2/B3和B4查询均为行为红，不是语法错误 |
| 身份红 / `cb0401302` / Actions `41385947642` | analyze通过；账号变更后旧 debounced query 仍为 `chab`；同账号 token续期保持查询的正向对照 | P/N/U未验证 | 身份边界真实失败，不能将 token轮换等同换号 |
| 呈现红 / `518a61024` / Actions `41386918242` | analyze通过；同一行回调重入推两页；实际偏好写 `no` 后多页面仍显示评分；Hub仍有坐标；题目完成缺直接分析 | P/N/U未验证 | 可做最小整改；所有新回归的绿和实战例外仍待跑 |
| 静态检查 / `bc842f51d` / Actions `41388581094` | analyze发现 accountProvider 的内容本身为 nullable User，以及一处测试 import 排序；行为步骤未执行 | P/N/U未验证 | 不算行为红；已改为非空且 id 属于当前账号才开放，修正 import，仍须重跑 |
| 静态检查 / `ae4f3cae7` / Actions `41390983202` | 仅测试 import alias `analysisFixture` 违反 snake_case lint；行为步骤未执行 | P/N/U未验证 | 已改 `analysis_fixture`；不能据此宣称任何行为绿 |

代码已加入 B1 的入口/公共菜单/模型安全边界、B2/B4 的 mounted+身份保护与释放、B3 的统一收件箱权限判断。
这些源码改动尚未拿到同 SHA 绿；评分策略已共用并接入数字/元数据槽，最高评分携带角色而非预过滤文本，
避免刷新/失败缓存恢复时泄露评分。两个 Hub 缩略图已关闭坐标并应用亮度/hue；题目完成栏已提供直接分析、
去除提示并使用继续训练图标，增加真实直接分析交接/返回回归。实战例外语义仍待行为红再接入。
新增 PageStorageKey 也不等于所有返回锚点已经验收；B8–B17 未在此批宣称完成。

## 分页协议边界

- 已捕获 bundle：`inbox.join {page}`、`inbox.chat.user {chat_id,page}`、`get.notifications {page}`。
- 页信封实际使用 `has_next_page`、`next_page_num`、`prev_page_num`、`total_pages`；各响应自己的 parser，不共用猜测 wire shape。
- `inbox.chat.user.messages` 无 chat ID / server message ID；请求必须串行，超时后的旧连接不能服务下一请求。
- 通知实际 mark 回包 `mark.all.notif.read.success`；不按 bundle 常量臆造另一事件。
- 好友写值、赛事 pairing 非空 shape、通知偏好写成功仍未充分确认；不在本轮造按钮或替上游编造数据。
- 逆向材料只查已定位 `xiangqi-com-re/docs/` 与 bundle，不能读 `SECRETS.md`。

## 最终验收门槛

- 页面角色 → 状态 → 输入链 → 同 SHA 结果可追溯，受影响国象回归也通过。
- 480×480、1280×720、1920×1080，中英/深浅；字缩放与 DPI 分离。
- 相同布局角色误差 ≤1 逻辑像素；棋盘/棋子/合法内容差异独立标注。
- Linux 原生证据来自 Actions 隔离会话，不改宿主 D-Bus/辅助功能/音频设置。
- 待验收包与测试同 SHA，不 rolling、不安装、不替 `dist`。
- 用户按组认可后才记 U；iPhone 声音/触觉未测就继续标未测。
