# Draft - 重写竞速类算子，让 throttle 按时间窗发出

- **状态**: Draft
- **创建日期**: 2026-10-18
- **最后更新**: 2026-10-18

## 摘要

`debounce`、`combineLatest`、`combineLatest3` 每一轮都把上游 iterator 的副本放进新建的 Task 里赛跑，由此带来四个问题：

- 提前退出后，留下没人取消的 Task。
- 慢的那一侧每一轮多挂一个等待用的 Task。
- `debounce` 的 sleep Task 从不取消；消费方被取消后还可能空转。
- 为了能复制 iterator，这几个算子要求上游 iterator 是 `Sendable`，于是在 Swift 6 语言模式下没法对 `AsyncStream` 使用它们。

另外，`throttle` 完全靠拉取驱动，最新值会被压住；`throttle` 和 `delay` 都用系统时钟计时。这份提案把这些问题一起改掉。对应的 8 个复现测试已经写好，目前全部失败。

## 方案

- **每个上游一个生产 Task。** 第一次调用 `next()` 时，为每个上游启动一个长期运行的 Task。它在 Task 内部自己创建并迭代上游 iterator，把元素、结束和错误送进一条内部的 `AsyncThrowingStream`，消费方的 `next()` 只从这条流里读。
  - 消费方的 iterator 持有一个 class 令牌，令牌被释放（iterator 被丢弃）时取消所有生产 Task。
  - 消费方被取消时，内部流的 `next()` 立即返回；流结束时同样取消生产 Task。
  - `debounce`：计时也放进生产 Task。每来一个元素，就取消上一个计时 Task、启动一个新的，计时到期才把元素送出。上游结束时仍丢弃尚未发出的元素，现有测试 `Sequence that finishes at once emits nothing` 规定了这一点。
  - `combineLatest` / `combineLatest3`：各上游的生产 Task 把「哪一侧、什么元素」送进同一条流，消费方维护各侧的最新值并组合。现有的结束与报错规则不变。
  - 错误沿用 `merge` 的做法，借 `_ErrorMechanism` 保持 `rethrows`。
- **`throttle` 改为按时间窗发出**，语义对齐 Combine：
  - 在时间窗之外到来的元素立即发出，并开启一个新窗口。
  - 窗口内到来的元素先存着，窗口结束时发出其中第一个或最新的一个。
  - 上游结束时，先发出存着的元素再结束，保留 fork 已有的行为。
- **计时改用单调时钟** `ProcessInfo.processInfo.systemUptime`，所有部署目标都能用。`throttle` 和 `delay` 都改。
- **放宽约束**：这几个算子不再要求 `AsyncIterator: Sendable`，只要求序列和元素是 `Sendable`。放宽约束是源码兼容的。

**没有询问就采用的假设**

- 上游会被提前读取，读到的元素在内部不限量缓冲、不丢弃。这保留了现在「不丢元素」的语义，代价是消费方很慢时内存会增长。
- 系统时钟那一条（审查第 11 条）不写复现测试：要测就得在源码里加一个可替换的时钟，那是新的测试接口。这一处改动是机械替换，会记进已裁决清单。
- 验证标准：8 个复现测试转绿，其余测试保持通过，测试 target 里那 38 条 `Sendable` 警告消失。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-18 | Created as Draft。用户在全量审查后说「开始修」；按计划，第二批（审查第 7–11 条，加上新发现的 `Sendable` 约束问题）先写精简提案，再动手 | 这批改动要重写竞速逻辑和 `throttle`，不算显而易见的 bug 修复 |
