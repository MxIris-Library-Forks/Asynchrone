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

// NOTE: Operators that combine MULTIPLE generic base sequences (zip, chain,
// combineLatest and their 3-sequence variants) hit a Swift runtime issue when
// the FIRST base sequence is non-throwing and a LATER base sequence throws:
// in a generic `rethrows` context (such as `collect()` or `first()`), the
// specialized `next()` witness is treated as non-throwing, the error thrown
// by the later sequence is lost in the witness thunk and the caller suspends
// forever. Keep the throwing sequence in the first position, or erase the
// non-throwing sequence with `eraseToAnyThrowingAsyncSequenceable()` so all
// bases share the same throwing capability.
