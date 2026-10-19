import Testing

/// The suite that every suite in this target is nested in.
///
/// Many operators here are timing-based, and their tests sleep for fractions of a
/// second. Swift Testing runs tests in parallel by default, and that load makes those
/// sleeps overshoot, so the whole target runs one test at a time, as it did under XCTest.
@Suite(.serialized)
enum AsynchroneTestSuite {}
