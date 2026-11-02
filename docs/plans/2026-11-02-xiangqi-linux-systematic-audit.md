# 象棋集成全页面审查与整改：Linux 优先 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 先登记完整页面和状态，再按根因整改象棋集成，以同阶段的国象页面及真实 Linux 行为验收，不用共享组件或测试数量代替体验结论。

**Architecture:** 保留两种棋独立的规则、身份和上游协议，共用呈现角色、偏好与导航契约。
分页保留实际响应元数据，无请求 ID 的 Socket 通道各自串行、超时后换独立连接；旧账号、旧页面和旧请求的结果不得接管新状态。
审查和验收数据分开：源码事实、Actions 行为、成组图片、Linux 原生及用户主观确认分别记录。

**Tech Stack:** Flutter / Dart 3.10+、Riverpod 3、fast_immutable_collections、HTTP、Socket.IO、GitHub Actions、隔离的 Linux 图形会话。

---

## 执行约束与基线

- 复用 `/home/hentaku/go/src/chess/mobile-xiangqi-parity`、`fix/xiangqi-desktop-parity`；不另开子代理或工作树。
- 起点 `d2f89a627`，生产代码与 `4bd6c07cf` 相同，工作树干净。
- 既有验证：Actions `41380249454`。它只证明既有回归，不能证明此次全页面验收。
- 本机仅编辑、`dart format`、diff 和只读审查；不编译、不测试、不 analyze、不 codegen。
- 测试先在 Actions 真实失败，再最小实现、在 Actions 通过；语法或分析错误不算行为红。
- 不读或改 mihomo、个人秘密、宿主设置；不用 `rm`；不主动连接 iPhone。
- 可以上传代码及读取必要 Actions 证据。预览包独立保存，不滚动发布、安装或覆盖 `dist`。
- 风格基准是本项目的国象页面、现有 Material / Platform 主题与组件；不另换配色、字体或装饰风格。

## 检查点

| 批次 | 内容 | 当前状态 |
|---|---|---|
| 1 | 全入口／状态清单、源码根因登记 | 已登记；行为与主观验收未开始 |
| 2 | 编辑器安全出口、联系人异步导航与账号入口 | 指定86项在47eab2a81通过；完整页面/身份矩阵仍待后续 |
| 3 | 隐藏评分、缩略图偏好、题目完成操作栏 | 发现 test scope 固定评分yes和硬编码标签，旧相关R撤回；real 模式/负向对照重跑 |
| 4 | 私信／通知分页及无 ID 通道超时隔离 | 待协议测试与实现 |
| 5 | 好友／赛事／资料分页、局部失败与返回恢复 | 待红 → 绿 |
| 6 | 全页面配对、DPI 与字缩放分离 | 待实现 |
| 7 | 独立 Actions 原生检查与 Linux 待验收包 | 待实现；不自动发布 |
| 8 | 分组人工验收与遗留问题交接 | 待用户确认；iPhone 后置 |

### Task 1: 完整入口与状态审查

**Files:**
- Create: `docs/xiangqi-linux-parity-audit.md`
- Reference: `lib/src/view/xiangqi/`、六个 Hub、`home_tab_screen.dart`、`play_menu.dart`、`more_tab_screen.dart`、`account_menu.dart`、`contacts_screen.dart`、`xiangqi_links_service.dart`

1. 从 Screen 类、路由、菜单、弹层和链接入口形成清单，不只查独立页面。
2. 每页登记国象参考；无真正对应页的，明确以共用呈现角色为参考。
3. 每页列正常非空、空、加载、局部失败、重试、详情返回、换号；不可适用项注明原因。
4. 记录确切源码边界和复现输入；优先身份／棋局混乱、崩溃，再功能、偏好／恢复、视觉。
5. 全清单形成后才修改业务源码。审查登记不等于这些状态已运行通过。

### Task 2: 编辑器与联系人生命周期

**Files:**
- Modify: `lib/src/model/xiangqi/xiangqi_analysis_controller.dart`
- Modify: `lib/src/view/xiangqi/xiangqi_board_editor_screen.dart`
- Modify: `lib/src/view/xiangqi/xiangqi_analysis_actions.dart`
- Modify: `lib/src/view/message/contacts_screen.dart`
- Modify: `lib/src/view/account/account_menu.dart`、`lib/src/view/more/more_tab_screen.dart`
- Test: `test/view/xiangqi/xiangqi_board_editor_screen_test.dart`
- Test: `test/view/message/contacts_screen_test.dart`
- Test: `test/model/xiangqi/xiangqi_analysis_controller_test.dart`
- Modify: `.github/workflows/test.yml`（新专项前置，不替代原有回归）

1. 对缺将帅、照面将、不可达士象等图验证出口禁用及明确原因；合法图仍可分析、继续。
2. 对直接传入非法普通分析图验证引擎和继续出口拒绝，不能只在编辑器挡一次。
3. 真实点击联系人两次只推一页；父页卸载后对话返回不访问已释放 `ref`。
4. 同账号返回保留查询／滚动位置；换号不让旧导航回调清新查询，token 轮换不清状态。
5. 只登录象棋正式账号时两处 inbox 入口可用；游客、离线、国象儿童模式边界分别验证。
6. Actions 确认行为失败；只修上述根因，完整释放搜索 controller / focus / debouncer。
7. Actions 跑本专项及原有联系人、编辑器、分析、导航边界回归，记录同 SHA 证据。

### Task 3: 偏好与训练完成态

**Files:**
- Modify: `lib/src/widgets/xiangqi_player_row.dart`
- Modify: `lib/src/view/xiangqi/xiangqi_watch_screen.dart`、`xiangqi_puzzle_screen.dart`、`xiangqi_friends_screen.dart`、`xiangqi_leaderboard_screen.dart`、`xiangqi_profile_screen.dart`、`xiangqi_saved_screen.dart`
- Modify: `lib/src/view/account/account_menu.dart`、`lib/src/view/user/leaderboard_hub_screen.dart`
- Modify: `lib/src/view/analysis/analysis_hub_screen.dart`、`lib/src/view/board_editor/board_editor_hub_screen.dart`
- Reference: `lib/src/view/account/rating_pref_aware.dart`、`lib/src/view/puzzle/puzzle_screen.dart`
- Test: `test/widgets/shared_game_presentation_test.dart`、`test/view/xiangqi/xiangqi_training_history_test.dart`
- Test: `test/view/xiangqi/xiangqi_preference_presentation_contract_test.dart`
- Modify: `test/test_provider_scope.dart`（real 模式只移除默认评分覆盖，旧布局测试保持原行为）
- Create: `scripts/verify-xiangqi-rating-negative-control.sh`（只在 Actions 恢复原始渲染、验证真实 UI 失败，退出恢复当前代码）

1. 禁用 test scope 的固定 yes 覆盖；每次修改后显式断言真实 showRatingsPrefProvider，供给 `yes`、`no`、`exceptInGame`。
   在 Actions 用原始渲染做相同测试，确保失败来自 UI 而非夹具/编译；只在当前用户实战传 active，观战/复盘不误隐藏。
2. 账号／题目／好友／排行榜／资料的评级及最高评分都必须服从隐藏偏好，非评分统计保留。
3. 配对缩略图统一禁止坐标、关闭交互／动画，亮度和 hue 等照用主题偏好；保留象棋长宽比。
4. 完成题目直接提供分析；完成后不残留无用提示；继续训练图标与国象一致。
5. 教学只读、上游权限、保存失败及自动下一题的既有行为不退化。
6. 依次 Actions 红 → 最小实现 → 绿；配对渲染和主观验收仍独立。

### Task 4: 无 ID 通道与页模型

**Files:**
- Create: `lib/src/model/xiangqi/xiangqi_page.dart`
- Modify: `lib/src/model/message/xiangqi_inbox_repository.dart`
- Modify: `lib/src/model/xiangqi/social/xiangqi_social.dart`、`xiangqi_social_repository.dart`
- Modify: `lib/src/network/xiangqi_socket.dart`（仅复用独立连接生命周期）
- Test: `test/model/message/xiangqi_inbox_repository_test.dart`
- Test: `test/model/xiangqi/social/xiangqi_social_test.dart`

公共接口形状（按实际协议解析，不共用猜测字段）：

```dart
class const XiangqiPage<T>({
  required final IList<T> items,
  required final int currentPage,
  required final int? nextPage,
  required final int? previousPage,
  required final int totalPages,
});

Future<XiangqiPage<Contact>> loadChatsPage(int page);
Future<XiangqiPage<Message>> loadMessagesPage(String chatId, int page);
```

1. 根据已捕获的 `inbox.join {page}`、`inbox.chat.user {chat_id,page}`、`get.notifications {page}` 写页信封测试。
2. 去重请求键含账号代际／会话／页码；旧 `loadChats()`、`loadMessages(chatId)` 保留第一页兼容入口。
3. 私信、通知各自拥有独立 Socket。无 request ID 时通道串行；超时后关闭旧通道，重新握手，再发下一项。
4. 测试 A 超时、B 排队、A 迟到回包：B 不接受 A 内容，在线对局连接不断开。
5. 测试退出、换号、dispose、token 续期、首次连接失败和重连失败；队列无未完成 Promise 泄漏。
6. 不编造 message server ID；按已确认的合成身份合并，不把分页尾页当错误。

### Task 5: 页面分页和恢复

**Files:**
- Modify: `lib/src/view/message/contacts_screen.dart`、`xiangqi_conversation_screen.dart`
- Modify: `lib/src/view/xiangqi/xiangqi_notifications_screen.dart`、`xiangqi_friends_screen.dart`、`xiangqi_tournaments_screen.dart`、`xiangqi_profile_screen.dart`
- Modify: `lib/src/model/xiangqi/social/xiangqi_social_repository.dart`
- Test: 上述页面对应的 `test/view/` 文件及私信 controller 测试

1. 写第 2 页／尾页、页错误后原页重试、刷新期间旧内容、详情返回页码和滚动锚点测试。
2. 刷新、更多、局部重试分别呈现忙碌状态；失败留内容，不把错误伪装为空／零／成功。
3. 按真实下一页元数据启用入口，合并去重，不凭 items.length 推测总页数。
4. 好友筛选变化回第一页；换号清私有缓存，续 token 保留；赛事对局未知 shape 不猜功能。
5. 资料 `_RecentGames` 当前固定第 1 页，补上真实分页，不沿用先前记录里的错误判断。
6. 国象只做保持原行为的共享抽取；共同 bug 单独登记并共同回归。

### Task 6: 成组视觉证据

**Files:**
- Modify: `test/view/xiangqi/xiangqi_desktop_visual_test.dart`
- Create: 配对场景／几何检查测试及 `scripts/` 页面组索引脚本
- Modify: `.github/workflows/test.yml`

1. 两种棋同语言、主题、偏好、阶段配对真实页面，不用替换整个 controller 的 fake 状态代替输入链。
2. Linux 480×480、1280×720、1920×1080，中英和深浅主题；文字缩放和 devicePixelRatio 分别设置、分别命名。
3. 使用 `toImage(pixelRatio: ...)` 输出 DPI 对应原图；保存原图、角色差异图及页面组索引。
4. 同布局角色误差上限 1 逻辑像素；棋盘比例、棋子、合法内容等有意差异单独标注。
5. 不把旧矩阵的 TextScaler 1x／2x 称为 DPI；不把截图数称为验收数。

### Task 7: Actions 原生检查与待验收包

**Files:**
- Create: `.github/workflows/xiangqi-linux-audit.yml`
- Create: `scripts/` 隔离启动／回归／产物索引脚本
- Create: 独立 Linux 审核入口（正式 main 不引用夹具）
- Reference: `.github/workflows/build-linux.yml`（它会发布 rolling，不直接触发）

1. Actions 容器内单独显示、D-Bus、HOME/XDG、音频；不改宿主辅助功能开关。
2. 真实页面/controller、窗口缩放、鼠标/键盘/重复输入/焦点/弹层/剪贴板，真实 Pikafish 最短合法搜索。
3. 构建同 SHA Linux 包，仅 upload-artifact，无 release 权限及 rolling 删除逻辑。
4. 产物附 SHA、配置、步骤、结果、原生未验证项。只有确需用户验收时下载到新目录。
5. 不安装、不覆盖 `/home/hentaku/go/src/chess/dist/lichess-zh.pkg.tar.zst`。

### Task 8: 分组验收和交接

**Files:** `docs/xiangqi-linux-parity-audit.md`、`docs/xiangqi-ui-parity.md`

1. 每组展示修前／修后证据，记录用户“仍有问题”的具体阶段，不要求用户自行逐页找 bug。
2. 自动行为、几何、Linux 原生、主观视觉、iPhone 声音／触觉分别记录。
3. 未确认的 wire shape 与本轮未覆盖页面保留明确缺口，不增加无效操作。
4. 只有用户认可且各所需证据完成后才标该组已验收；本轮总计划不得因一组绿而完成。

## 统一验证入口（只在 Actions runner 执行）

```sh
dart format --output=none --set-exit-if-changed <本批非生成 Dart 文件>
flutter analyze
flutter test --no-pub --reporter expanded <本批专项测试>
flutter test --no-pub --reporter expanded <受影响的国象与象棋既有测试>
```

本机仅用 `git diff --check`、指定文件 `dart format` 及源码审查。
每次确认 Actions 的 `head_sha` 与提交一致，读取必要步骤日志；不全量下载巨大历史日志。
