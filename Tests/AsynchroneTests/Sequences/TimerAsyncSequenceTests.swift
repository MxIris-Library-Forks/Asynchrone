import XCTest
@testable import Asynchrone

final class TimerAsyncSequenceTests: XCTestCase {
    private var sequence: TimerAsyncSequence!
    
    // MARK: Setup
    
    override func setUpWithError() throws {
        self.sequence = .init(interval: 0.5)
    }

    // MARK: Tests
    
    func testTimerEmissions() async throws {
        var values: [Date] = []
        let start = Date()
        var end = Date()
        
        for await value in self.sequence {
            values.append(value)
            
            if values.count == 3 {
                end = Date()
                self.sequence.cancel()
            }
        }
        
        var difference = end.timeIntervalSince(start)
        XCTAssert(difference >= 1.5)
        
        difference = values[1].timeIntervalSince(values[0])
        XCTAssert(difference >= 0.5)
        
        difference = values[2].timeIntervalSince(values[1])
        XCTAssert(difference >= 0.5)
    }

    func testCancellingBeforeIterationFinishesImmediately() async {
        let sequence = TimerAsyncSequence(interval: 0.1)
        sequence.cancel()

        let values = await sequence.collect()
        XCTAssert(values.isEmpty)
    }

    func testNegativeIntervalDoesNotCrash() async {
        let sequence = TimerAsyncSequence(interval: -5)

        for await _ in sequence {
            sequence.cancel()
        }
    }

    func testSecondIterationDoesNotStartAnotherTimer() async {
        let sequence = TimerAsyncSequence(interval: 0.1)

        var firstIterationValueCount = 0
        for await _ in sequence {
            firstIterationValueCount += 1

            if firstIterationValueCount == 2 {
                sequence.cancel()
            }
        }

        // The timer task has finished; a new iteration must complete
        // immediately instead of spawning another timer task.
        let values = await sequence.collect()
        XCTAssert(values.isEmpty)
    }
}
