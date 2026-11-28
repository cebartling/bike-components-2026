import BikeComponentsCore
import Foundation
import Testing

private let holder = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
private let otherHolder = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

struct `Repository errors` {
    @Test(arguments: [
        (RepositoryError.gearIDTaken(heldBy: holder), RepositoryError.gearIDTaken(heldBy: holder)),
        (.unreadableRecord(detail: "BikeRecord.name"), .unreadableRecord(detail: "BikeRecord.name")),
        (.storeFailed(detail: "save failed"), .storeFailed(detail: "save failed")),
    ])
    func `a case with the same values is equal`(lhs: RepositoryError, rhs: RepositoryError) {
        #expect(lhs == rhs)
    }

    @Test(arguments: [
        (RepositoryError.gearIDTaken(heldBy: holder), RepositoryError.gearIDTaken(heldBy: otherHolder)),
        (.unreadableRecord(detail: "BikeRecord.name"), .unreadableRecord(detail: "RideRecord.distance")),
        (.storeFailed(detail: "save failed"), .storeFailed(detail: "fetch failed")),
        (.unreadableRecord(detail: "same"), .storeFailed(detail: "same")),
    ])
    func `different values or cases are not equal`(lhs: RepositoryError, rhs: RepositoryError) {
        #expect(lhs != rhs)
    }
}
