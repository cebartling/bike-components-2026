import Foundation

/// Why a call to a repository port failed (ADR-0011).
package enum RepositoryError: Error, Sendable, Equatable {
    /// Another bike already holds this Strava gear ID (ADR-0007, ADR-0009).
    case gearIDTaken(heldBy: UUID)
    /// A stored record couldn't be mapped to a valid Core value (ADR-0007).
    case unreadableRecord(detail: String)
    /// Any other store failure.
    case storeFailed(detail: String)
}
