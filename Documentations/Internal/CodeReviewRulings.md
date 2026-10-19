# Code review 已裁决清单

这里记录 code review 中判定为误报、不修或只改文档的发现，以及当时的理由。每次 code review 先对照这份清单：理由仍然成立的发现直接跳过；新证据推翻了理由，就更新对应条目并重新裁决。

## `delay` 实际是「相邻两次发出至少间隔 interval」

- **来源**：2026-10-18 对 main 的全量审查，第 15 条。
- **裁决**：设计如此。不改行为，只改文档。
- **理由**：文档示例（输出时刻 0.5、1.0、1.5）和测试 `DelayAsyncSequenceTests.delay()`（断言相邻两次的间隔不小于 0.5 秒）都按「间隔」语义写，说明这是有意的行为。改成「每个元素各自往后推 interval」会改变现有调用方看到的时序。错的只是开头那句「Delays emission of all elements by the provided interval」，已改为描述实际行为。
- **位置**：`Sources/Asynchrone/Sequences/DelayAsyncSequence.swift`

## 在 async 版 stream 初始化器的 build 闭包里设置 `onTermination` 会互相覆盖

- **来源**：同一次审查，第 12 条的公开 API 部分。
- **裁决**：不改代码，改为文档约定。
- **理由**：初始化器靠 `continuation.onTermination` 在 stream 结束时取消 build Task。调用方在 build 闭包里再设置这个回调，两次赋值谁后执行谁生效。`Continuation` 是标准库类型，初始化器拦截不到之后的赋值，也就没法把两个回调组合起来。库里唯一这样用的 `shared()` 已改为不再经过这个初始化器。约定写进了两个初始化器的文档注释：不要在 build 闭包里设置 `onTermination`，需要收尾时改为处理 build Task 的取消。
- **位置**：`Sources/Asynchrone/Extensions/AsyncStream+Extension.swift`、`Sources/Asynchrone/Extensions/AsyncThrowingStream+Extension.swift`
