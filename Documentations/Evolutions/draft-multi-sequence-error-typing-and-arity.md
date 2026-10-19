# Draft - 多源算子的错误类型与任意个数

- **状态**: In Progress
- **作者**: JH
- **创建日期**: 2026-10-19
- **最后更新**: 2026-10-19
- **所属愿景**: 无
- **关联提案**: [重写竞速类算子，让 throttle 按时间窗发出](draft-rework-racing-and-throttle.md)（`combineLatest` 的内部重写在那份里，本提案的 `combineLatest` 部分依赖它）
- **实现分支 / PR**: `feature/multi-sequence-error-typing-and-arity`（worktree `.worktrees/Asynchrone-MultiSequenceErrorTypingAndArity`），PR 待定
- **配套文档**: 待定 —— 落地时登记实现说明的链接

## 摘要

`zip`、`combineLatest`、`chain` 靠 `rethrows` 让编译器推断「会不会抛错」，而编译器只看第一个上游：第一个上游不抛、后面的上游会抛时，调用方可以不写 `try`，后面上游的错误就被吞掉。这几个算子也只支持两个或三个上游。本提案给它们各加一组重载，不提高库的部署目标：

- **任意个数、总要写 `try`**：用参数包函数实现，任何系统都能用。另提供行为相同的 `tryZip` / `tryCombineLatest` / `tryChain`，让旧系统的调用方也能主动选它。
- **macOS 15 / iOS 18 起**：上游都不抛的两元、三元调用照旧不用写 `try`；只要有上游会抛，就必须写 `try`。
- **更低的部署目标**：调用方行为不变。

## 动机

**吞错漏洞。** 第一个上游不抛、后一个会抛时：

```swift
let numbers = AsyncStream<Int>.makeStream().stream                       // never throws
let words = AsyncThrowingStream<String, any Error>.makeStream().stream   // throws

// Compiles without `try` on every deployment target. The error from `words` is lost.
let pairs = await numbers.zip(words).collect()

// With a deployment target of macOS 15 / iOS 18 or later, this compiles without `try` too.
for await pair in numbers.zip(words) { print(pair) }
```

现在只能靠调用约定绕开：

- `Sources/Asynchrone/Common/ErrorMechanism.swift:31` 的注释要求把会抛的序列放在第一个，并把原因写成「Swift 运行时问题」。根因其实在编译期，见下文《前期调研》。
- `Tests/AsynchroneTests/Sequences/CombineLatestAsyncSequenceTests.swift:70` 和 `CombineLatest3AsyncSequenceTests.swift:58` 的 `Error is rethrown` 测试，故意把会抛的序列放在第一个。

**只支持两个或三个上游。** 每个元数各写一个类型和一个方法：

| 算子 | 两个上游 | 三个上游 |
|------|----------|----------|
| `zip` | `ZipAsyncSequence`（48 行代码） | `Zip3AsyncSequence`（58 行） |
| `combineLatest` | `CombineLatestAsyncSequence`（139 行） | `CombineLatest3AsyncSequence`（197 行） |

行数不含注释和空行。要组合更多上游只能嵌套，`a.zip(b).zip(c).zip(d)` 得到的是嵌套元组。

## 前期调研

### 现状代码

- 几个 `next()` 都只标了 `rethrows`，没有声明 `Failure`：
  - `Sources/Asynchrone/Sequences/ZipAsyncSequence.swift:95`（方法在 `:148`）
  - `Zip3AsyncSequence.swift:109`（`:171`）
  - `CombineLatestAsyncSequence.swift:107`（`:259`）
  - `CombineLatest3AsyncSequence.swift:127`（`:326`）
  - `ChainAsyncSequenceable.swift:101`（`:170`）
- 这几个类型的初始化器只有 `ChainAsyncSequence`、`CombineLatestAsyncSequence`、`CombineLatest3AsyncSequence` 是 public，`Zip` 的两个是 internal。
- 库内部没有调用这三个算子的地方。

### 编译器怎么决定要不要写 `try`

依据本机 Swift 6.4.0 源码（`/Volumes/SwiftProjects/swift-project/swift`）：

- `Failure` 是 SE-0421 给 AsyncSequence 和 AsyncIteratorProtocol 加的关联类型，表示迭代时抛什么错。Swift 6.0 起，一个 AsyncSequence 要不要 `try`、经过它的 `rethrows` 函数（`collect()`、`first()`、`contains(where:)`、`reduce` 等）要不要 `try`，都由它的 `Failure` 决定。`lib/Sema/TypeCheckEffects.cpp:202` 的注释原文是「the thrown error result is captured by the Failure type」。
- 类型没有声明 `Failure` 且 `next()` 标的是 `rethrows` 时，编译器取 `next()` 泛型签名里**第一个** AsyncSequence / AsyncIteratorProtocol 约束的 `Failure`，见 `lib/Sema/AssociatedTypeInference.cpp:2670` 的 `computeFailureTypeWitness`。对 `ZipAsyncSequence<P, Q>` 来说就是 `P.Failure`，与 `Q` 无关。
- 实测（见下文）：部署目标低于 macOS 15 时，`for await` 仍然要求 `try`；部署目标 ≥ 15 时，`for await` 改用按 `Failure` 判断的 `next(isolation:)`，不再要求 `try`。经过 `rethrows` 函数的调用在任何部署目标下都不要求 `try`。

### 系统版本要求

- `Failure` 关联类型标的是 `@available(SwiftStdlib 6.0, *)`，对应 macOS 15.0、iOS 18.0、watchOS 11.0、tvOS 18.0、visionOS 2.0（`utils/availability-macros.def:46`）。在约束、类型或不透明返回类型（`some AsyncSequence<Element, Failure>`）里引用它，都要这个版本。
- 带参数包的**类型**（`struct Zip<each Base>`）要 SwiftStdlib 5.9，即 macOS 14 / iOS 17 / watchOS 10 / tvOS 17（`:44`）。
- 参数包**函数**没有系统要求。参数包可能用到的两个运行时函数 `swift_allocateMetadataPack`、`swift_allocateWitnessTablePack`，由工具链自带的 `libswiftCompatibilityPacks.a` 回部署到运行时 5.8 及以下的系统（`include/swift/Frontend/BackDeploymentLibs.def:32`）。
- 库现在的部署目标是 macOS 10.15、Mac Catalyst 13、iOS 13、watchOS 6、tvOS 13、visionOS 1。

### 验证过的结论

用 Swift 6.4.2 和 Xcode 27.2 SDK 写一次性小样例，在 Swift 6 语言模式下验证，只编译、链接，没有运行：

- **漏洞属实**：仿照 `ZipAsyncSequence` 写的两元类型，在 macOS 11 和 15 两种部署目标下，`await pair.contains(1)` 都不要求 `try`；macOS 15 下 `for await` 也不要求。
- **参数包类型不可行**：
  - 部署目标 11、13 下报「parameter packs in generic types are only available in macOS 14.0.0 or newer」。
  - 带参数包的类型配 `rethrows` 的 `next()`，`Failure` 被推断成一个包（`'Never, Never'`），swift-frontend 在「generating SIL witness table protocol conformance … AsyncIteratorProtocol」时段错误崩溃。
  - 元素类型写成 `(repeat (each Base).Element)` 时，调用处经过协议取 `Element` 的地方（`for-in`、`reduce`）把它当成裸包，报「pack reference … can only appear in pack expansion」。把第一个上游单独放出来能绕开，但 `for try await (a, b, c) in …` 这种三元及以上的解构仍然报「pattern cannot match values of type '(Int, String, Bool)'」。
- **参数包函数可行**：
  - 序列类型本身不带参数包，三个类型参数都是普通元组；参数包只出现在构造它的函数里。
  - Swift 6 模式、macOS 11 部署目标下编译通过；按 macOS 11（arm64）和 10.15（x86_64）链接成功，产物里没有从系统运行时导入的参数包函数。
  - 二元、三元、四元的循环头解构，以及 `reduce`、`map` 都正常。
  - 条件 `Sendable` 两个方向都成立：上游都是 `Sendable` 时它也是，有一个不是时它就不是。
- **「上游都不抛」写不进参数包**：
  - `where repeat (each Base).Failure == Never` 报「same-type requirements between packs and concrete types are not yet supported」，写在方法上和全局函数上都一样。
  - 「所有上游的 `Failure` 相同」报「same-element requirements are not yet supported」。SE-0393 正文定义了这种约束，编译器到 6.4 还没实现。
  - 用联合错误类型 `throws(EitherError<Never, Never>)` 仍然要求 `try`，编译器只把 `Never` 当成不抛。
  - 函数自己迭代、每组元素交给闭包的 `rethrows` 全局函数：固定个数时判断正确，换成参数包后三个上游都不抛也要求 `try`；而且它不再是序列。
- **按系统版本拆重载可行**（只在 macOS 部署目标上验证过，其他平台在落地时验证）：最终方案的选择结果，按调用方部署目标 macOS 15 和 macOS 11 分别编译验证过，见下文《提议方案》里的表格。另外：
  - `obsoleted` 能让旧重载只对低于 15 的调用方可见；15 起的调用方有别的重载可选时，不会报「不可用」。
  - 在部署目标 15 起，`chain` 带 `Never` 约束的重载优先于不带约束的重载。
- **显式声明 `Failure = any Error`**：`@available(macOS 15, *) typealias Failure = any Error` 在 macOS 11 部署目标下也会被用来判断要不要 `try`，能堵住漏洞，但两个上游都不抛时所有系统都要写 `try`。
- **剩余警告**：参数包构造函数里的两个闭包捕获了各上游的元类型，产生 4 条 `SendableMetatypes` 警告。给泛型参数加 `SendableMetatype` 约束可以消除，这要 Swift 6.2 编译器。
- **下游**：本机仓库里只有 RuntimeViewer（`RuntimeViewerCore/Package.swift`，`from: "0.23.0-fork.1"`）依赖本库，它只用了 `shared()`。

## 提议方案

`zip`、`combineLatest`、`chain` 各有四组入口：

1. **现在的 `rethrows` 版**：方法和返回类型都不变，但方法加上 `obsoleted`（macOS 15、iOS 18、Mac Catalyst 18、tvOS 18、watchOS 11、visionOS 2），只有低于这些版本的调用方选得到。
2. **不抛重载**（这些系统版本起）：两元、三元各一个，约束为每个上游的 `Failure == Never`，返回的仍是现在的类型。所有上游都不抛时，现在的类型本来就是对的。
3. **会抛的通用版**：
   - `zip`、`combineLatest` 用参数包函数实现，上游个数不限，任何系统都可用，结果总要写 `try`。
   - `chain` 的元素类型要相同，写不成参数包，是固定两个序列的新类型，只在 15 起作为 `chain(with:)` 的重载出现。
4. **`tryZip` / `tryCombineLatest` / `tryChain`**：与第 3 组行为相同、名字不同，任何系统都可用。低于 15 的调用方靠它选择「必须写 `try`、不会吞错」。

按调用方的部署目标，选择结果是：

| 调用 | macOS 15 / iOS 18 起 | 更低的部署目标 |
|------|----------------------|----------------|
| 两元、三元，上游都不抛 | 不用 `try` | 不用 `try`（旧版） |
| 两元、三元，有上游会抛，`for await` | 要 `try` | 要 `try`（旧版） |
| 两元、三元，有上游会抛，经过 `collect()` 这类 `rethrows` 函数 | 要 `try` | **不用 `try`，错误被吞（旧版的漏洞保留）** |
| 四元及以上（`zip`、`combineLatest`） | 要 `try` | 要 `try` |
| `tryZip` / `tryCombineLatest` / `tryChain` | 要 `try` | 要 `try` |

### 非目标

- **不提高库的部署目标**。
- **不修低于 15 的吞错漏洞**：那里用不了 `Failure`，能让「上游都不抛就不写 `try`」成立的只有 `rethrows` 推断。要正确，改用 `try` 开头的那组方法。
- **不改 `merge`**：它的上游都是同一个类型，没有这个漏洞。`merge` 还有一个问题，后一个上游的错误要等前一个上游结束才传出来。这是 bug 修复，带复现测试单独做，不在本提案里。把 `merge` / `merge3` 合并成可变参数也另议。
- **不改 `catch`**：它吞掉替换序列错误的问题与本提案无关。
- **不消除 `SendableMetatypes` 警告**：等工具链版本定下来再处理，见《影响》。
- **不覆盖非 Apple 平台**：那里没有系统版本，旧重载和新重载会同时可见。本次没有验证那里的重载选择。

### 尚未确认的假设

2026-10-19 批准时确认了前两条；第三条留到落地第 4 步，先写样例验证。

- 新类型名为 `ThrowingZipAsyncSequence`、`ThrowingCombineLatestAsyncSequence`、`ThrowingChainAsyncSequence`，沿用库里 `ThrowingPassthroughAsyncSequence` 的叫法。
- 下一个版本号是 `0.24.0-fork.1`：0.x 阶段的破坏性改动按惯例只升 minor。
- `combineLatest` 参数包版的内部结构（见《详细设计》）还没写样例验证。

## 详细设计

### zip

```swift
/// Zips any number of sequences. Iterating it always requires `try`.
public struct ThrowingZipAsyncSequence<Bases, Iterators, Element>: AsyncSequence {
    fileprivate let bases: Bases
    fileprivate let makeIterators: @Sendable (Bases) -> Iterators
    fileprivate let advance: @Sendable (inout Iterators) async throws -> Element?

    public func makeAsyncIterator() -> Iterator {
        Iterator(iterators: self.makeIterators(self.bases), advance: self.advance)
    }

    public struct Iterator: AsyncIteratorProtocol {
        fileprivate var iterators: Iterators
        fileprivate let advance: @Sendable (inout Iterators) async throws -> Element?
        fileprivate var isFinished = false

        public mutating func next() async throws -> Element? {
            guard !self.isFinished else { return nil }
            guard let element = try await self.advance(&self.iterators) else {
                self.isFinished = true
                return nil
            }
            return element
        }
    }
}

extension ThrowingZipAsyncSequence: Sendable where Bases: Sendable {}

/// Thrown by `advanced(_:)` when an iterator ends, so the iterators after it are not advanced.
private struct EndOfZippedSequence: Error {}

private func advanced<Iterator: AsyncIteratorProtocol>(
    _ iterator: Iterator
) async throws -> (iterator: Iterator, element: Iterator.Element) {
    var iterator = iterator
    guard let element = try await iterator.next() else { throw EndOfZippedSequence() }
    return (iterator, element)
}

private func makeThrowingZip<each Base: AsyncSequence>(
    _ bases: repeat each Base
) -> ThrowingZipAsyncSequence<(repeat each Base), (repeat (each Base).AsyncIterator), (repeat (each Base).Element)> {
    ThrowingZipAsyncSequence(
        bases: (repeat each bases),
        makeIterators: { bases in (repeat (each bases).makeAsyncIterator()) },
        advance: { iterators in
            do {
                let results = (repeat try await advanced(each iterators))
                iterators = (repeat (each results).iterator)
                return (repeat (each results).element)
            } catch is EndOfZippedSequence {
                return nil
            }
        }
    )
}
```

- 迭代器存在元组里，不能对元组里的元素原地调用 `mutating` 方法（报「cannot use mutating member on immutable value of type 'each Iterator'」）。所以每轮把迭代器拷出、推进，再写回元组。
- 语义与现在一致：几个上游依次推进；有一个上游结束，就不再推进排在它后面的上游，整个序列结束；第一个错误结束序列并抛出。

重载：

```swift
extension AsyncSequence {
    // 1. Today's method, unchanged apart from the attributes.
    @available(macOS, obsoleted: 15)
    @available(iOS, obsoleted: 18)
    @available(macCatalyst, obsoleted: 18)
    @available(tvOS, obsoleted: 18)
    @available(watchOS, obsoleted: 11)
    @available(visionOS, obsoleted: 2)
    public func zip<Q>(_ other: Q) -> ZipAsyncSequence<Self, Q> where Q: AsyncSequence
    // The three-sequence `zip(_:_:)` gets the same attributes.

    // 2. No sequence throws: today's types, which are correct in this case.
    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, watchOS 11, visionOS 2, *)
    public func zip<Other: AsyncSequence>(_ other: Other) -> ZipAsyncSequence<Self, Other>
    where Failure == Never, Other.Failure == Never

    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, watchOS 11, visionOS 2, *)
    public func zip<Second: AsyncSequence, Third: AsyncSequence>(
        _ second: Second, _ third: Third
    ) -> Zip3AsyncSequence<Self, Second, Third>
    where Failure == Never, Second.Failure == Never, Third.Failure == Never

    // 3. Any number of sequences, on every system. At least one besides this one.
    public func zip<Second: AsyncSequence, each Remaining: AsyncSequence>(
        _ second: Second, _ remaining: repeat each Remaining
    ) -> ThrowingZipAsyncSequence<
        (Self, Second, repeat each Remaining),
        (AsyncIterator, Second.AsyncIterator, repeat (each Remaining).AsyncIterator),
        (Element, Second.Element, repeat (each Remaining).Element)
    >

    // 4. The same as 3, chosen explicitly.
    public func tryZip<Second: AsyncSequence, each Remaining: AsyncSequence>(
        _ second: Second, _ remaining: repeat each Remaining
    ) -> ThrowingZipAsyncSequence<
        (Self, Second, repeat each Remaining),
        (AsyncIterator, Second.AsyncIterator, repeat (each Remaining).AsyncIterator),
        (Element, Second.Element, repeat (each Remaining).Element)
    >
}
```

重载怎么选（已验证）：

- 固定个数的重载优先于参数包版，所以：
  - 低于 15 时，两元、三元总是选中第 1 组。
  - 15 起，第 1 组不可用。所有上游都不抛时选中第 2 组，否则落到第 3 组。
- 四元及以上只有参数包版可选。

### chain

`chain` 的几个序列元素类型必须相同，用参数包表达要写 same-element 约束，6.4 不支持（已验证），所以只提供两个序列的版本。一条链要接更多序列，像现在一样连续调用 `chain(with:)`。

```swift
public struct ThrowingChainAsyncSequence<First: AsyncSequence, Second: AsyncSequence>: AsyncSequence
where First.Element == Second.Element {
    public typealias Element = First.Element

    public struct Iterator: AsyncIteratorProtocol {
        public mutating func next() async throws -> Element?
    }
}

extension ThrowingChainAsyncSequence: Sendable where First: Sendable, Second: Sendable {}

extension AsyncSequence {
    // 1. Today's method, with the same `obsoleted` attributes as `zip`.
    public func chain<P>(with sequence: P) -> ChainAsyncSequence<Self, P> where P: AsyncSequence

    // 2. No sequence throws.
    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, watchOS 11, visionOS 2, *)
    public func chain<Other: AsyncSequence>(with other: Other) -> ChainAsyncSequence<Self, Other>
    where Failure == Never, Other.Failure == Never

    // 3. Everything else.
    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, watchOS 11, visionOS 2, *)
    public func chain<Other: AsyncSequence>(with other: Other) -> ThrowingChainAsyncSequence<Self, Other>

    // 4. Available everywhere.
    public func tryChain<Other: AsyncSequence>(with other: Other) -> ThrowingChainAsyncSequence<Self, Other>
}
```

两元的 `chain` 第 2、3 组都是固定个数，同时适用时，带 `Never` 约束的那个优先（已验证）。

### combineLatest

重载结构与 `zip` 相同，约束沿用现在的 `Self: Sendable, Element: Sendable`，参数包里的每个上游也要求 `Sendable`、元素 `Sendable`：

```swift
extension AsyncSequence where Self: Sendable, Element: Sendable {
    public func combineLatest<Second, each Remaining>(
        _ second: Second, _ remaining: repeat each Remaining
    ) -> ThrowingCombineLatestAsyncSequence<…>
    where Second: AsyncSequence & Sendable, Second.Element: Sendable,
          repeat each Remaining: AsyncSequence & Sendable, repeat (each Remaining).Element: Sendable

    public func tryCombineLatest<Second, each Remaining>(…) -> ThrowingCombineLatestAsyncSequence<…>
}
```

`AsyncIterator: Sendable` 这个约束按第二批提案的结论放宽。

内部沿用第二批提案的做法，每个上游一个生产 Task。区别在于：第二批提案的内部流传的是「哪一侧、什么元素」，参数包里没法给每个位置定义一个 case，所以参数包版改为：

- 每个上游一个加锁的槽位，类型是 `LatestValueSlot<Element>`，按该上游的元素类型分别实例化。生产 Task 只往自己的槽位写最新值，再往同一条内部流里发一个「有变化」的信号。
- 迭代器收到信号后，若每个槽位都有值，就组合成 `(repeat (each slots).latestValue!)` 发出。
- 结束与报错规则沿用第二批提案的结论。

这一节是推测，实现前先写样例验证。建议第二批重写固定个数的版本时也采用槽位加信号的结构，两边共用。

## 替代方案考量

- **带参数包的序列类型**（`struct ZipSequence<each Base>`）：要 macOS 14；`rethrows` 让编译器崩溃；调用处元素类型的两个问题（见《验证过的结论》）。否。
- **给现有类型声明 `Failure = any Error`**（`/modernize-swift` 审查报告里的第 1 条建议）：能堵住漏洞，但两个上游都不抛时所有系统都要写 `try`，也解决不了个数限制。本提案在 15 起保留了「都不抛就不写 `try`」，所以取代它。
- **限定所有上游共用一个 `Failure`**（`where Second.Failure == Failure`，`next()` 写 `throws(Failure)`）：两元可行，但不抛和会抛的上游混用时直接编译不过，调用方要先转换；参数包里写不出这个约束。否。
- **联合错误类型**（`throws(EitherError<First.Failure, Second.Failure>)`）：上游都不抛时仍要写 `try`。否。
- **参数包版加「都不抛」重载**：6.4 不支持参数包与具体类型之间的同类型约束。做不到。等编译器实现 SE-0393 的 same-element 约束后可以重新考虑，届时它仍要 macOS 15。
- **函数自己迭代、交给闭包**（`forEachZipped(a, b) { … }`）：固定个数时判断正确，但不再是序列，接不了其他算子；参数包版仍要 `try`。否。
- **返回 `some AsyncSequence<Element, Failure>`**：要 macOS 15。否。
- **闭包捕获上游的类型擦除盒子**（类似 `AnyIterator`）：失去条件 `Sendable`，后面接不了要求 `Sendable` 的算子（`debounce`、`shared()` 等）。改用以元组为类型参数的包装类型。
- **用宏生成固定个数的重载**：
  - 生成的东西很少，每多一个元数只多一个几行的转发重载。
  - 使用者要编译 swift-syntax，Xcode 要信任这个宏，`xcodebuild` 要加 `-skipMacroValidation`。
  - swift-syntax 的版本范围还要与使用者的其他宏包重叠，例如 FrameworkToolbox 要求 `600.0.0..<604.0.0`。
  - 文件顶层的宏不能引入事先没声明的名字（「macros are not allowed to introduce arbitrary names at global scope」）。
  - 结论：否。以后要更多元数，就手写，或用提交进仓库的生成脚本。
- **提高部署目标到 14 或 15**：本方案不需要；提高会影响所有使用者。否。
- **改用 swift-async-algorithms**：会成为所有使用者的传递依赖，还会把最低工具链抬到 6.2。否。

## 影响

### 源码兼容性（source compatibility）

**有破坏**，只影响部署目标在 macOS 15 / iOS 18 / tvOS 18 / watchOS 11 / visionOS 2 及以上的调用方。

1. 第一个上游不抛、后面有上游会抛时，从此必须写 `try`。编译错误暴露的正是原来被吞掉的错误：

   ```swift
   // Before: compiles, the error from `words` is lost.
   let pairs = await numbers.zip(words).collect()
   // After
   let pairs = try await numbers.zip(words).collect()
   ```

2. 有上游会抛时，返回类型从 `ZipAsyncSequence` / `Zip3AsyncSequence` / `CombineLatestAsyncSequence` / `CombineLatest3AsyncSequence` / `ChainAsyncSequence` 变成对应的 `Throwing…` 类型。代码里写死了类型名的地方要改，或者改写成 `some AsyncSequence`。

部署目标更低的调用方：已有代码的行为不变，只是多了四元及以上的 `zip` / `combineLatest`，以及 `try` 开头的三个方法。

不能用 `@available(*, deprecated, renamed:)` 过渡：破坏来自编译器强制要求写 `try`，这正是要修的问题。

### ABI 兼容性（条件项）

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

### 下游影响

- **本仓库**：测试 target 的部署目标是 macOS 14（Swift Testing 要求），已有测试走第 1 组，行为不变。新行为的测试放在 `@available(macOS 15, *)` 的测试函数里。
- **RuntimeViewer**：只用了 `shared()`，不受影响。
- **库自身代码**：没有调用这三个算子。
- **编译警告**：库源码会新增 `SendableMetatypes` 警告，每个参数包构造函数 4 条，`zip` 和 `combineLatest` 合计约 8 条。现在库源码是 0 警告。工具链提到 Swift 6.2 后，加 `SendableMetatype` 约束即可清零。

### 文档与示例

- README（英文）的 `ChainAsyncSequence`（`README.md:182`）、`CombineLatestAsyncSequence`（`:222`）、`CombineLatest3AsyncSequence`（`:250`）、`ZipAsyncSequence`（`:643`）、`Zip3AsyncSequence`（`:668`）几节：
  - 补任意个数的用法和 `try` 开头的方法；
  - 写明不同部署目标下要不要 `try`。
- 所有新增和改动的方法写 DocC 注释。旧重载的注释写明低于 15 时的吞错情况，并指向 `try` 开头的那组方法。
- 改正 `ErrorMechanism.swift:31` 的注释，以及两个 combineLatest 测试里的同类注释。

## API 演进与废弃策略

- 现有方法不标 `deprecated`：低于 15 的调用方要么继续用它，要么改用 `try` 开头的方法。旧方法只用 `obsoleted` 对 15 起的调用方隐藏。
- 现有类型保留：第 2 组重载还在返回它们。
- 等库的部署目标提到 macOS 15 / iOS 18 时，删除第 1 组重载，并把这几个类型的 `rethrows` 改成用 `Failure` 表达。
- 0.x 阶段的破坏性改动升 minor，下一个版本为 `0.24.0-fork.1`（待确认）。

## 落地步骤

1. **先写复现测试，确认会失败**：
   - 在 `@available(macOS 15, *)` 的测试里，对「第一个上游不抛、第二个会抛」的 `zip` 和 `chain` 调用 `collect()`，期望抛出第二个上游的错误。
   - 现状下错误会丢失（现有注释记录的现象是挂起），用超时或 exit test 兜住，避免整个测试卡死。
   - `tryZip` / `tryChain` 的测试在实现之前编译不过，算作失败。
2. **`zip`**（2026-10-19 完成）：加 `ThrowingZipAsyncSequence` 和参数包构造函数、第 3、4 组方法；给现有两个方法加 `obsoleted`，加第 2 组重载。补上测试：
   - 四元及以上；
   - 三元的循环头解构；
   - 15 起「都不抛就不写 `try`」：写在测试代码里，选错重载就编译不过。
3. **`chain`**：加 `ThrowingChainAsyncSequence` 和四组方法，测试同上。
4. **`combineLatest`**：等第二批提案落地以后再做。先写样例验证槽位加信号的结构，再实现，测试同上。
5. **文档**：按《文档与示例》改 README、DocC 和注释。
6. **验证**：
   - `swift test` 只认原始退出码。
   - 再为 iOS Simulator 编译一次，确认各平台的可用性标注都生效。只编译，不启动模拟器。

**收尾时必须判断两件事**（判断结果写进决策日志）：

- **要不要配套文档**：预计要写一份实现说明，记下几个从代码看不出来的决定：
  - 序列类型为什么不带参数包；
  - 为什么不用 `rethrows`；
  - 为什么按系统版本拆重载；
  - 6.4 编译器的几处限制。
- **有没有新术语**：预计没有。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-10-19 | Created as Draft | 起因是 `/modernize-swift` 审查发现多源算子的吞错漏洞，随后讨论了用参数包消除按元数写的样板。用户最后说「先提案吧」 |
| 2026-10-19 | 参数包只用在函数上，序列类型不带参数包 | 用户指出只有带参数包的类型才要 macOS 14，全局函数没有这个限制。已验证属实，并确认返回的具体类型可以不带参数包 |
| 2026-10-19 | 按系统版本拆重载：15 起用 `Failure == Never` 约束的不抛重载，更低版本保留现有 `rethrows` 版 | 用户提出「参数包加一个 available，旧版本就手动写多个参数的版本」。已验证重载选择符合预期 |
| 2026-10-19 | 旧系统也提供必须写 `try` 的版本 | 用户要求「旧版本也给用户多几个选择」。同名重载在旧系统上总会选中旧版，所以换了名字 |
| 2026-10-19 | 命名为 `tryZip` / `tryCombineLatest` / `tryChain`；不抛重载只做两元和三元；单独成提案，`combineLatest` 的内部重写仍在第二批提案；暂时接受 `SendableMetatypes` 警告 | 用户同意按这四条写提案 |
| 2026-10-19 | 不用宏生成固定个数的版本 | 用户让评估宏。评估结论是成本远大于收益，理由见《替代方案考量》，用户未反对 |
| 2026-10-19 | 按完整模板撰写 | 改动包含破坏性 API 变更，属于完整档；用户要求先写提案，未再追加提问。尚未确认的假设列在《提议方案》里，等审阅时确认 |
| 2026-10-19 | 状态改为 Accepted，开始实现 | 用户调用 `/accept-proposal` 批准，类型名与版本号两条假设随之确认。`combineLatest` 仍按第 4 步等第二批提案落地 |
| 2026-10-19 | 状态改为 In Progress；第 1 步的复现测试按算子分开写，确认失败后与该算子的实现放进同一个提交 | `tryZip` 这类测试在实现之前编译不过，单独提交会让那个提交构建失败。失败的实测记录：旧代码上 `zip` 两元、三元的两个复现测试都在 5 秒超时后失败，`collect()` 一直不返回；编译器同时提示 `try` 里没有会抛的调用 |
| 2026-10-19 | `ThrowingZipAsyncSequence` 的迭代器抛错后也标记结束，之后的 `next()` 直接返回 `nil` | 《详细设计》要求「第一个错误结束序列」，草图代码漏了这一处。不标记的话，下一次 `next()` 会用这一轮之前的迭代器拷贝重新推进，排在出错上游前面的上游会被多推进一次。测试 `An error ends the sequence without advancing it again` 覆盖 |
| 2026-10-19 | 测试 target 的部署目标是 macOS 14，15 起的行为写在 `@available(macOS 15, …)` 的测试函数里即可验证 | 查编译器源码 `lib/AST/AvailabilityConstraint.cpp`：判断 `obsoleted` 时先取所在上下文的可用范围，没有才退回部署目标，所以 `@available(macOS 15, *)` 的函数里旧重载就不可见了。实测与此一致 |
