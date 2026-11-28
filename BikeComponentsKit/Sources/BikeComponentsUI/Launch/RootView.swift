import SwiftUI

/// The view shown from the first frame: it launches the app and shows the result (ADR-0010).
public struct RootView: View {
    let launchModel: LaunchModel

    public init(launchModel: LaunchModel) {
        self.launchModel = launchModel
    }

    public var body: some View {
        content
            .task { await launchModel.launch() }
    }

    @ViewBuilder
    private var content: some View {
        switch launchModel.state {
        case .opening:
            ProgressView()
        case .ready:
            // Placeholder until the root screen arrives (ADR-0014, #4).
            Text("Bike Components")
        case let .failed(error):
            // ADR-0011: a failed launch shows a fixed sentence and the error, until relaunch.
            ContentUnavailableView {
                Label("The app couldn't open its data.", systemImage: "exclamationmark.triangle")
            } description: {
                Text(String(describing: error))
            }
        }
    }
}
