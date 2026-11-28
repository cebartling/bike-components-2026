import BikeComponentsUI
import Testing

private struct OpenFailed: Error, Equatable {}

/// Counts `start` calls and records the model's state while `start` runs.
private final class StartProbe {
    var calls = 0
    var stateDuringStart: String?
    var model: LaunchModel?
}

private func describe(_ state: LaunchModel.State) -> String {
    switch state {
    case .opening: "opening"
    case .ready: "ready"
    case .failed: "failed"
    }
}

struct `Launch model` {
    @Test func `a launch whose start succeeds is ready`() async {
        let model = LaunchModel(start: { AppModels() })

        await model.launch()

        #expect(describe(model.state) == "ready")
    }

    @Test func `a launch whose start throws keeps the error`() async throws {
        let model = LaunchModel(start: { throw OpenFailed() })

        await model.launch()

        guard case let .failed(error) = model.state else {
            Issue.record("expected failed, got \(describe(model.state))")
            return
        }
        #expect(error as? OpenFailed == OpenFailed())
    }

    @Test func `a failed launch is not retried`() async {
        let probe = StartProbe()
        let model = LaunchModel(start: {
            probe.calls += 1
            throw OpenFailed()
        })

        await model.launch()
        await model.launch()

        #expect(probe.calls == 1)
        #expect(describe(model.state) == "failed")
    }

    @Test func `the state is opening while start runs`() async {
        let probe = StartProbe()
        let model = LaunchModel(start: {
            probe.stateDuringStart = probe.model.map { describe($0.state) }
            return AppModels()
        })
        probe.model = model

        await model.launch()

        #expect(probe.stateDuringStart == "opening")
    }

    @Test func `concurrent launches run start once`() async {
        let probe = StartProbe()
        let model = LaunchModel(start: {
            probe.calls += 1
            await Task.yield()
            return AppModels()
        })

        async let first: Void = model.launch()
        async let second: Void = model.launch()
        _ = await (first, second)
        await model.launch()

        #expect(probe.calls == 1)
        #expect(describe(model.state) == "ready")
    }
}
