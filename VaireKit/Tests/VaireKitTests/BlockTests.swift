import Foundation
import Testing
@testable import VaireKit

@Test func blockDurationIsEndMinusStart() {
    let start = Date(timeIntervalSince1970: 0)
    let end = Date(timeIntervalSince1970: 3600)
    let block = Block(projectId: UUID(), start: start, end: end, source: .manual)
    #expect(block.duration == 3600)
}
