import BikeComponentsCore
import Foundation
import Testing

private let quarterHour = Date(timeIntervalSince1970: 1_800_000_000)
private let nextQuarterHour = quarterHour.addingTimeInterval(15 * 60)

struct `Source errors` {
    @Test(arguments: [
        (SourceError.notConnected, SourceError.notConnected),
        (.authorizationRejected, .authorizationRejected),
        (.rateLimited(resetsAt: quarterHour), .rateLimited(resetsAt: quarterHour)),
        (.offline, .offline),
        (.unavailable(detail: "GET /athlete: 503"), .unavailable(detail: "GET /athlete: 503")),
        (.unreadableResponse(detail: "Athlete.bikes"), .unreadableResponse(detail: "Athlete.bikes")),
        (.cancelled, .cancelled),
    ])
    func `a case with the same values is equal`(lhs: SourceError, rhs: SourceError) {
        #expect(lhs == rhs)
    }

    @Test(arguments: [
        (SourceError.rateLimited(resetsAt: quarterHour), SourceError.rateLimited(resetsAt: nextQuarterHour)),
        (.unavailable(detail: "GET /athlete: 503"), .unavailable(detail: "GET /athlete: 502")),
        (.unreadableResponse(detail: "Athlete.bikes"), .unreadableResponse(detail: "Gear.id")),
        (.offline, .cancelled),
        (.notConnected, .authorizationRejected),
    ])
    func `different values or cases are not equal`(lhs: SourceError, rhs: SourceError) {
        #expect(lhs != rhs)
    }
}
