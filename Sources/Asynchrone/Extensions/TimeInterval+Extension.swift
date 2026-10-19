import Foundation

extension TimeInterval {
    var asNanoseconds: TimeInterval {
        self * 1_000_000_000
    }

    /// The interval in whole nanoseconds, limited to what `UInt64` can represent.
    ///
    /// Negative intervals and `nan` become zero. Intervals too long to represent,
    /// including `infinity`, become `UInt64.max`, which is longer than 584 years.
    var clampedNanoseconds: UInt64 {
        let nanoseconds = self.asNanoseconds

        // Also false for `nan`.
        guard nanoseconds > 0 else { return 0 }
        guard nanoseconds < TimeInterval(UInt64.max) else { return .max }

        return UInt64(nanoseconds)
    }
}
