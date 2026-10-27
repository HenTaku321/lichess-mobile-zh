# xiangqi.com 集成与交互加固

## 变更边界

- `XiangqiSessionStore` 是 HTTP、Socket 与 auth UI 的会话状态源，现有 auth provider 接口保留。
- 恢复会话与未登录分开，游客创建合并请求；刷新暂时失败不删除 refresh token。
- 会话 generation 阻止旧刷新或旧登录结果覆盖新身份；显式业务 Authorization 的 401 不触发通用清会话。
- HTTP 截止时间包含排队、响应体与刷新重放，支持单请求 abort，不关闭共享 transport 来取消单个请求。
- 账号 Socket 供私信和通知共享；每局棋、每次复盘、每个聊天室使用独立 transport。
- Socket 绑定当前会话，退出关闭旧连接，身份改变重新握手。存在 game id 的回复仍执行 id 校验。
- 归档 redirect 的防循环集合限于一次请求；重连后先完成快照同步，再恢复走子。

## UI 规则

基准是现有 Lichess App，不重新设计棋子材质或主题。

后续源码级 UI 对照及分批整改记录见 `docs/xiangqi-ui-parity.md`。
该记录明确列出尚未完成的逐页检查，不能以本表或静态分析通过推断全部 UI 已一致。

| 场景 | 行为 |
|---|---|
| 首次加载/恢复会话 | loading，不提前显示“未登录” |
| 加载失败/历史请求超时 | 结束 loading，提供重试 |
| 已加载后断线 | 保留棋盘/历史，禁用在线动作，显示断线状态 |
| 实时走子确认 | 一次声音/触觉；重复帧与快照不补播 |
| 浏览历史期间收到走子 | 更新实时局面，保持回放位置 |
| 回放单步 | 声音及设置指定的动画，不触发走子震动 |
| 多步跳转/首次载入复盘 | 无动画补播 |
| 关闭上一步高亮 | 只影响高亮，不同时关闭走子动画 |
| 对局结束 | 自适应结果弹窗；在线实时结束延迟 400ms，本地对局沿用 Lichess 离线的 500ms；重复状态不重复弹出 |
| 聊天排队/发送失败 | 未提交草稿保留，不自动重发无确认消息 |
| 快速匹配取消/离页 | 清理排队，丢弃过期轮询，不自动跳转或认输 |

## 验证说明

新增回归位于 `test/network/xiangqi_hardening_test.dart` 和
`test/view/xiangqi/xiangqi_feedback_regression_test.dart`，并更新了受交互变化影响的旧测试。
Go 回归位于相邻 `proxy/hardening_test.go`。

实施中曾运行分组测试；随后按用户要求停止本机编译（包括会编译测试程序的测试命令）。
停止后的最终版本仅做源码静态分析、格式及 diff 检查，**不代表最终完整测试已通过**。
没有操作线上账号、没有部署、没有在 Android/iOS 真机验证。

在用户指定的构建环境中执行：

```sh
# Go：在 ../proxy 中
go vet ./...
go test -race ./...
go build ./...

# Flutter：在 mobile 中；使用该环境已安装的 Flutter SDK
flutter analyze --no-pub
flutter test --no-pub test/network/xiangqi_http_test.dart test/network/xiangqi_socket_test.dart test/network/xiangqi_hardening_test.dart
flutter test --no-pub test/model/xiangqi test/model/message/xiangqi_inbox_repository_test.dart
flutter test --no-pub test/view/xiangqi test/view/auth/xiangqi_login_screen_test.dart test/widgets/xiangqi_board_test.dart
flutter test --no-pub
```

运行时重点复核：游客升级账号、退出再切账号、刷新 503、两个棋局与复盘并行、
握手中关闭、反复归档 resync、重连后的走子禁用期、聊天断线及取消匹配的竞态。
用深浅主题和手机/桌面尺寸检查布局；真机触觉与声音须另外验收。

## 兼容与回滚

会话的 secure-storage JSON 和原有账号键不变；服务端 wire shape 不变。
新 Socket provider 属于内部接口调整，原账号共享 provider 保留。
没有自动提交或改动工作区原有的开局翻译、窗口标题栏和棋子材质修改。
