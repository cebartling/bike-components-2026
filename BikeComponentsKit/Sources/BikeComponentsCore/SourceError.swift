import Foundation

/// Why a call to a Strava port failed (ADR-0011).
package enum SourceError: Error, Sendable, Equatable {
    /// This device holds no Strava tokens.
    case notConnected
    /// Strava refused the tokens or their scopes; reconnecting fixes it.
    case authorizationRejected
    /// A Strava rate limit was reached; requests work again after `resetsAt`.
    case rateLimited(resetsAt: Date)
    /// The device has no usable network connection.
    case offline
    /// Strava couldn't be reached or answered with an error.
    case unavailable(detail: String)
    /// Strava's answer couldn't be read as the expected data.
    case unreadableResponse(detail: String)
    /// The caller's task was cancelled.
    case cancelled
}
