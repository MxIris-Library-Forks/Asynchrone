# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Asynchrone is a dependency-free Swift package providing Combine-style operators and publisher-like types for Swift's `AsyncSequence` (debounce, throttle, merge, zip, combineLatest, shared, Just, Fail, Empty, PassthroughAsyncSequence, etc.).

This is a fork: `origin` is `MxIris-Library-Forks/Asynchrone`, `upstream` is `reddavis/Asynchrone`. The fork's main change is backporting deployment targets down to macOS 10.15 / iOS 13 / watchOS 6 / tvOS 13 (see `Package.swift`). Avoid APIs that require newer OS versions, or guard them with `@available` / `#available`.

## Commands

```bash
swift build                 # build
swift test                  # run all tests (CI runs exactly this)
swift test --filter AsynchroneTests.DebounceAsyncSequenceTests                 # one test class
swift test --filter AsynchroneTests.DebounceAsyncSequenceTests/testDebounce    # one test method
```

Many tests are timing-based (debounce/throttle/timer use real `Task.sleep` and `XCTAssertEventuallyEqual` with timeouts), so occasional flakiness under load is a known characteristic — rerun before assuming a regression.

## Architecture

### Operator file pattern (Sources/Asynchrone/Sequences/)

Every operator lives in its own file and follows the same structure; new operators should match it:

1. A public struct conforming to `AsyncSequence`, with a doc comment containing a runnable usage example (these examples are reused in the README and DocC).
2. The `Iterator` as a nested type declared in an `extension`, conforming to `AsyncIteratorProtocol`.
3. Conditional `Sendable` conformances in separate trailing extensions (`extension Foo: Sendable where ...`).
4. A trailing `extension AsyncSequence` adding the fluent operator method (e.g. `.debounce(for:)`, `.merge(with:)`) that just wraps `.init`.

Variants for 3 sources are separate types/files (`Merge3AsyncSequence`, `Zip3AsyncSequence`, `CombineLatest3AsyncSequence`) rather than variadic.

### Shared task race utility (Sources/Asynchrone/Common/TaskRace.swift)

`TaskRaceCoordinator` + `Task.firstToComplete(of:)` race multiple tasks and return the first finisher, cancelling all of them if the surrounding task is cancelled. Debounce and CombineLatest build on it: each side's `next()` runs in a `Task` capturing a COPY of the iterator, and the task's result threads the mutated iterator back into the value-type iterator struct. Losing tasks stay in `pending` slots and re-enter the next race so no element is dropped.

### Strict concurrency

Both targets compile with `.enableExperimentalFeature("StrictConcurrency")` (complete checking, surfaced as warnings since the package stays in the Swift 5 language mode). Keep the main target warning-free.

### Known Swift runtime pitfall: mixed-throwing multi-sequence operators

For operators combining MULTIPLE generic base sequences (`zip`, `chain`, `combineLatest` and 3-sequence variants): if the FIRST base sequence is non-throwing and a LATER one throws, the error is lost in the specialized `next()` witness inside generic `rethrows` contexts (`collect()`, `first()`, ...) and the caller suspends forever (Swift 6.x runtime issue; full analysis in the note in `Common/ErrorMechanism.swift`). Tests for throwing behavior MUST put the throwing sequence in the first position. Never write a test that combines a non-throwing first sequence with a throwing later one — it will hang the whole test run.

### Error rethrowing mechanism (Sources/Asynchrone/Common/ErrorMechanism.swift)

`_ErrorMechanism` is a `@rethrows` protocol retroactively conformed by `Result`, borrowed from swift-async-algorithms. It lets an iterator's `next() async rethrows` store a caught error in a `Result` (e.g. inside a racing `Task`) and later rethrow it via `result._rethrowGet()` / `result._rethrowError()` without forcing the whole sequence to be `throws`. Use this pattern when an operator must catch errors inside a child task but stay rethrowing.

### Tests (Tests/AsynchroneTests/)

- One test file per operator, mirroring the `Sequences/` / `Extensions/` source layout.
- `Assertion.swift` provides the shared async assertion helpers: `XCTAssertEventuallyEqual`, `XCTAssertEventuallyTrue`, `XCTAsyncUnwrap`, `XCTAsyncAssertThrow`/`NoThrow`/`Nil`/`Equal`. Prefer these over hand-rolled polling/sleeps.
- `TestError.swift` is the shared error type for throwing-sequence tests.

### Documentation

DocC catalog at `Sources/Asynchrone/Documentation.docc/`; docs are built by Swift Package Index (`.spi.yml`). Public APIs are expected to carry full doc comments with example code blocks, matching the existing style.
