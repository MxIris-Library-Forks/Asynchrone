//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

@rethrows
protocol _ErrorMechanism {
    associatedtype Output
    func get() throws -> Output
}

extension _ErrorMechanism {
    func _rethrowError() rethrows -> Never {
        _ = try _rethrowGet()
        fatalError("Materialized error without being in a throwing context")
    }
  
    func _rethrowGet() rethrows -> Output {
        try get()
    }
}

extension Result: _ErrorMechanism { }

// NOTE: Operators that combine MULTIPLE generic base sequences through a
// `rethrows` `next()` (zip, chain, combineLatest and their 3-sequence
// variants) do not declare `Failure`, so the compiler infers it from the
// FIRST base sequence only. This is decided at compile time: when the first
// base never throws and a later one does, `collect()`, `first()` and the
// other `rethrows` methods compile without `try`, the error from the later
// sequence is lost, and the call never returns.
//
// From macOS 15, iOS 18, tvOS 18, watchOS 11 and visionOS 2 on, `zip` and
// `chain` hide these overloads and return types that always throw whenever a
// base can throw. Below those versions, `tryZip` and `tryChain` always throw.
// `combineLatest` is not covered yet: keep the throwing sequence in the first
// position, or erase the non-throwing sequence with
// `eraseToAnyThrowingAsyncSequenceable()` so all bases share the same
// throwing capability. See Documentations/Internal/MultiSequenceOperators.md.
