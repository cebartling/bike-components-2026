import Foundation
import Observation

/// Opens the app once, then holds the app-wide models (ADR-0010).
@Observable
public final class LaunchModel {
    public enum State {
        case opening
        case ready(AppModels)
        case failed(any Error)
    }

    public private(set) var state: State = .opening

    private let start: () async throws -> AppModels
    // ADR-0008's app-wide exception: the launch runs in a task the model keeps, so the
    // store opens once and a view going away never cancels it. Every caller awaits it.
    private var launchTask: Task<Void, Never>?

    public init(start: @escaping () async throws -> AppModels) {
        self.start = start
    }

    public func launch() async {
        if launchTask == nil {
            launchTask = Task {
                do {
                    state = .ready(try await start())
                } catch {
                    state = .failed(error)
                }
            }
        }
        await launchTask?.value
    }
}
