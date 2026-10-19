# 多源算子的错误类型与任意个数：实现说明

> 配套提案见《[多源算子的错误类型与任意个数](../Evolutions/draft-multi-sequence-error-typing-and-arity.md)》。
> 本文记录**实际落地的实现**、与提案的差异，以及当前覆盖范围与已知降级。面向维护者。

## 背景与目标

`zip`、`chain`、`combineLatest` 的旧类型靠 `rethrows` 让编译器推断要不要写 `try`，而编译器只看第一个上游。第一个上游不抛、后面的会抛时，`collect()` 这类调用不用写 `try` 也能编译，后面上游的错误丢失，调用永远不返回。`zip` 还只支持两个、三个上游。

目前落地的是 `zip` 和 `chain`：

- 新增总要写 `try` 的新类型，`zip` 支持任意个数。
- macOS 15 / iOS 18 / tvOS 18 / watchOS 11 / visionOS 2 起，旧重载对调用方隐藏。
- 新增 `tryZip` / `tryChain`，任何系统都可用。

`combineLatest` 按提案第 4 步，等第二批提案（重写竞速类算子）落地后再做。

## 关键设计决策

**序列类型不带参数包，参数包只出现在构造函数里。**

- 带参数包的泛型类型（`struct Zip<each Base>`）要 macOS 14 / iOS 17 / tvOS 17 / watchOS 10，库的部署目标是 macOS 10.15 / iOS 13。参数包函数没有系统要求，用到的运行时函数由工具链自带的 `libswiftCompatibilityPacks.a` 回部署。
- 所以 `ThrowingZipAsyncSequence<Bases, Iterators, Element>` 的三个类型参数都是普通元组。怎么创建迭代器、怎么推进一轮，由私有函数 `makeThrowingZip` 在参数包上下文里写成两个闭包，存进序列。
- 带参数包的类型除了系统版本，还有两处走不通：配 `rethrows` 的 `next()` 会让 swift-frontend 崩溃；元素类型写成 `(repeat (each Base).Element)` 时，调用处 `for try await (a, b, c) in` 这种三元及以上的解构编译不过。
- 闭包要标 `@Sendable`，序列的条件 `Sendable` 才成立。代价是闭包捕获了各上游的元类型，产生 `SendableMetatypes` 警告，见《已知降级》。

**每一轮把迭代器拷出来推进，再整体写回。**

- 迭代器存在一个元组里，元组的类型是参数包展开。这种元组的成员不能原地调用 `mutating` 的 `next()`，编译器报「cannot use mutating member on immutable value」。
- 一轮的写法是 `(repeat try await advanced(each iterators))`：按顺序推进每个迭代器的拷贝。某个迭代器返回 `nil` 时，`advanced` 抛私有错误 `EndOfZippedSequence`，展开就此中断，后面的上游不再推进。
- 推进的都是拷贝，所以一轮中途出错时，排在前面、已经推进过的拷贝就丢了，元组里还是这一轮之前的迭代器。迭代器因此在抛错后直接标记结束。不这样做的话，下一次 `next()` 会从旧迭代器重新推进，前面的上游被多推进一次，引用类型的上游会因此丢一个元素。

**不用 `rethrows`，按系统版本拆重载。**

- 根因在编译期：类型没有声明 `Failure`、`next()` 标的是 `rethrows` 时，编译器只取第一个 AsyncSequence 约束的 `Failure`（`lib/Sema/AssociatedTypeInference.cpp` 的 `computeFailureTypeWitness`）。与运行时无关，旧注释里「Swift 运行时问题」的说法不对。
- 能表达「每个上游都不抛」的只有 `where Failure == Never, Other.Failure == Never`，而关联类型 `Failure` 要 SwiftStdlib 6.0，也就是上面那组系统版本。
- 参数包里写不出这个约束：编译器不支持参数包与具体类型之间的同类型约束，也不支持 same-element 约束。所以不抛重载只有两元、三元，返回的仍是旧类型。上游都不抛时，旧类型推断出的 `Failure == Never` 本来就是对的。
- 旧重载加 `obsoleted`，在 15 起的上下文里不可见；那里总有别的重载可选，不会报「不可用」。
- 低于 15 时，固定个数的旧重载比参数包版优先，两元、三元的行为和以前一样，漏洞保留。要不吞错只能主动换方法。同名的重载在旧系统上总会选中旧版，所以总要 `try` 的版本叫 `tryZip` / `tryChain`。

**`obsoleted` 按所在上下文判断，不只看部署目标。** `lib/AST/AvailabilityConstraint.cpp` 判断 `obsoleted` 时，先取所在上下文的可用范围，没有才退回部署目标。测试 target 的部署目标是 macOS 14（SwiftPM 按 Swift Testing 的要求提高了它），所以 15 起的行为写在 `@available(macOS 15, …)` 的测试函数里就能测到，不需要单独的测试包。

**15 起会抛的 `chain(with:)` 只在 Apple 平台编译。**

- 非 Apple 平台没有系统版本，`obsoleted` 不生效，旧重载和这个重载同时可见。两者签名相同、都不带约束，上游有会抛的时报「ambiguous use of 'chain(with:)'」，那里原本能编译的代码会编译不过。
- 所以它包在 `#if canImport(Darwin)` 里，非 Apple 平台的行为与改动前一样。
- `zip` 没有这个问题：会抛版带参数包，固定个数的旧重载总是优先。

**`chain` 没有参数包版。** 几个序列的元素类型必须相同，这要 same-element 约束，6.4 编译器还没实现。要接更多序列，像以前一样连续调用。

## 模块结构

```
Sources/Asynchrone/Sequences/
├── ZipAsyncSequence.swift            # 旧类型；两元的旧重载（obsoleted）与 15 起的不抛重载
├── Zip3AsyncSequence.swift           # 同上，三元
├── ThrowingZipAsyncSequence.swift    # 总要 try 的新类型、参数包构造函数、zip(_:_:) 参数包版与 tryZip(_:_:)
├── ChainAsyncSequenceable.swift      # 旧类型；chain(with:) 的旧重载与 15 起的不抛重载
└── ThrowingChainAsyncSequence.swift  # 总要 try 的新类型、15 起会抛的 chain(with:) 与 tryChain(with:)
```

## 核心算法与数据流

**选中哪个重载**，取决于调用处所在上下文的系统版本：

| 调用 | 15 起 | 低于 15 |
|------|-------|---------|
| 两元、三元，上游都不抛 | 不抛重载，返回旧类型，不用 `try` | 旧重载，不用 `try` |
| 两元、三元，有上游会抛 | 新类型，要 `try` | 旧重载；`for await` 要 `try`，经过 `rethrows` 函数不用，错误会丢 |
| 四元及以上的 `zip` | `ThrowingZipAsyncSequence`，要 `try` | 同左 |
| `tryZip` / `tryChain` | 新类型，要 `try` | 同左 |

**`ThrowingZipAsyncSequence` 的一轮**：

1. 迭代器已结束（返回过 `nil` 或抛过错），直接返回 `nil`。
2. 调用存下的 `advance` 闭包：按顺序拷出每个迭代器并推进。
   - 全部拿到元素：把推进后的拷贝整体写回，返回元素组成的元组。
   - 有一个返回 `nil`：后面的不再推进，迭代器标记结束，返回 `nil`。
   - 有一个抛错：后面的不再推进，迭代器标记结束，把错误抛出去。

`ThrowingChainAsyncSequence` 与 `ChainAsyncSequence` 的实现完全相同，只是 `next()` 标的是 `throws`。

## 与提案的差异

- 迭代器抛错后标记结束。提案的文字要求「第一个错误结束序列」，草图代码漏了这一处。
- 15 起会抛的 `chain(with:)` 限定在 Apple 平台，理由见上。
- `combineLatest` 还没做，按提案第 4 步等第二批提案落地。

## 验证

- 测试文件：
  - `ZipAsyncSequenceTests`、`Zip3AsyncSequenceTests`、`ChainAsyncSequenceTests` 新增 15 起的测试：后面上游的错误被抛出；上游都不抛时不写 `try` 也能编译（选错重载就编译不过）。
  - `ThrowingZipAsyncSequenceTests`、`ThrowingChainAsyncSequenceTests` 覆盖新类型：四元、三元的循环头解构、`try` 开头的方法、推进顺序、抛错后不再推进、每个上游只建一个迭代器、条件 `Sendable`。
- 复现测试在旧代码上都失败：`collect()` 不返回，5 秒超时。
- 其他 Apple 平台只做了编译：为 iOS、tvOS、watchOS、visionOS 的模拟器和 Mac Catalyst 执行了 `build-for-testing`，没有运行测试。
- 非 Apple 平台没有实际编译。只用小样例在 macOS 上模拟了那里的重载可见性。

## 已知降级

- 部署目标低于 15 时，两元、三元的 `zip` / `chain` 仍会吞错：编译器选中旧重载，经过 `rethrows` 函数时不要求 `try`，错误丢失、调用不返回。要正确就用 `tryZip` / `tryChain`。
- 库源码有 4 条 `SendableMetatypes` 警告，来自 `makeThrowingZip` 的两个闭包。给泛型参数加 `SendableMetatype` 约束可以消除，但这要 Swift 6.2 编译器，等工具链版本定下来再处理。
- 15 起有上游会抛时，返回类型从旧类型变成新类型。代码里写死了旧类型名的调用方要改，这是提案里认可的破坏性变化。

## 后续工作

- `combineLatest` 的参数包版与 15 起的重载，等第二批提案落地。
- 库的部署目标提到 15 后：删掉旧重载，把旧类型的 `rethrows` 改成用 `Failure` 表达。
- 编译器实现 same-element 约束后，可以考虑参数包版的不抛重载和 `chain` 的参数包版。

## 延伸阅读

- 配套提案《[多源算子的错误类型与任意个数](../Evolutions/draft-multi-sequence-error-typing-and-arity.md)》
- 第二批提案《[重写竞速类算子，让 throttle 按时间窗发出](../Evolutions/draft-rework-racing-and-throttle.md)》
