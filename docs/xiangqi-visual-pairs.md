# 完整视觉配对：执行与证据边界

## 不是旧截图矩阵的改名

- 两侧是实际 `ConversationScreen` / `XiangqiConversationScreen` 及各自 controller，通过点击入口进入。
- 只替换 HTTP、Socket 与引擎／平台边界。字体固定；评分偏好使用真实 provider 并断言投影。
- 逻辑窗口尺寸、文字缩放和 `tester.view.devicePixelRatio` 独立设置；原图 `toImage(pixelRatio: dpi)`。
- 每个配置保存双方原图、每个可比角色差异图、请求／真实操作／controller／几何元数据。
- 几何阈值为 1 逻辑像素；共享像素角色要求零差异。有意差异必须先写入注册表，不能事后加遮罩。
- 图片不能替代主观认可或原生声音／触觉。当前工具无法直接查看图片，不记录“已看过且一致”。

## 全乘积而非抽样

旧 DesktopSceneApp 曾在缩放 MediaQuery 外调用 buildAppWindow，导致正文的字缩放被覆盖回1；
首批追加的实际环境断言抓到了这一点。现在正确传播上下文；旧单侧矩阵的200%文字覆盖不计有效。

`test/visual/xiangqi_pair_registry.json` 从 49 个实际入口角色登记状态、适用偏好与有意差异。
编译的 `visualCatalogue()` 提供依赖里的完整枚举值与持久化投影，不硬编码主题或棋子子集。
每个适用状态使用三尺寸 × 两语言 × 两主题 × 两字缩放 × 两真实 DPI，共 48 个环境。
亮度与色相按用户指定网格枚举；音量按界面 11 档。偏好全部相乘，不换成 pairwise 或抽样。

`scripts/xiangqi_visual_pairs.py` 用整数积与混合进制按索引取配置，最多只展开本次 1024 对。
索引／总量在 JSON 中是十进制字符串，不能经过 JavaScript 或 Dart 的有限精度整数。
登记总量包含未实现 driver 的配置：**登记不等于通过，也不等于其适用性已完成逐页审查。**
未接 driver 返回 `not_run`；没有真实对应页面／协议证据返回 `blocked`，两者都不能通过 gate。

## 手动批次

新 workflow 尚未进入默认分支，GitHub 不会为它直接注册 dispatch。因此已有 Tests workflow
提供纯手动入口，调用独立 `xiangqi-parity-visuals.yml`；普通 push 不运行完整配对批次。

```sh
gh workflow run test.yml --repo HenTaku321/lichess-mobile-zh \
  --ref fix/xiangqi-desktop-parity \
  -f candidate=FULL_40_CHARACTER_SHA \
  -f role=private-conversation -f state=normal \
  -f offset=0 -f limit=48
```

空 role/state 表示该轴所有登记范围，不是自动选“已支持的那一点”。offset 在选择范围内计数，
输出 case index 始终为全注册表索引。越界、超过 1024 对或未解析的枚举会明确拒绝，不静默缩小。

每分片最多 64 对、最多 16 片、并发 4、每片 30 分钟；每次只跑所请求批次，不自动继续。
固定 source SHA、注册表和渲染依赖指纹；字体或 Flutter／依赖变化不能沿用旧证据。

## 产物与判定

- `xiangqi-visual-plan-RUN_ID`：精确计数、作用域、枚举目录、依赖指纹及每片配置。
- `xiangqi-visual-metadata-RUN_ID-SHARD`：小元数据，排查几何优先读这个，不搬运全套截图。
- `xiangqi-visual-pairs-RUN_ID-SHARD`：DPI 原图、角色差异图、渲染 JSON 结果。
- `xiangqi-visual-coverage-RUN_ID`：本批 passed/failed/invalid/not_run/blocked，完整范围仍未运行量。

产物保留 90 天；缺图、错误 DPI、过期、错误阶段、固定评分 override、缺真实操作／controller
证明、伪造差异图均不计通过。差异从双方 PNG 原图独立重算，不仅相信 changedPixels 字段。
每对还必须对应实际 Flutter JSON 的非跳过成功结果，截图后出现 teardown／夹具错误也不计通过。
当前覆盖索引只总结本批；跨批有效覆盖汇总尚未实现，不能手工把多个绿色批次数量相加当完整覆盖。

## 当前配对进度

首批 `b8aeda4aa` / Actions `41439892393` 生成 48 对，全部被几何 gate 正确拒收：
国象保留空 typing/status 行，象棋缺该槽。首对最新气泡 y 差为 21 逻辑像素，气泡本身与 composer
像素差为零。已提取这对元数据与原图用于复现；由于工具不支持图片输入，没有主观验收。
后续实现使用共用状态槽，不模拟上游不存在的 typing 功能，等待同链路绿验证。

目前真实 driver 仅私信 normal/draft，其他角色／状态仍明确未实现；不能声称全页面已视觉配对。
相关红绿证据见 `docs/plans/2026-11-02-xiangqi-pagination-socket-visual-pairs.md`。

最终检查点候选 `042796732d6a48e1be927440e970d338c8da8b61` / Actions `41461365086`：
私信normal、system主题的48环境全部通过，实际字缩放1/2及DPI1/2已断言；消息区、输入框与气泡
角色像素差为0，四角色几何差为0，appbar维持预登记协议能力差异。**不包含其余25主题、其它状态
或任何主观／原生通过结论**。同候选普通Tests `41460927161` 已全流程通过；修正旧字号夹具后
出现的12项在线／题目侧栏溢出已转绿，单侧矩阵仍不能作为完整配对。
