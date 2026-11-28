import BikeComponentsUI
import SwiftUI

@main
struct BikeComponentsApp: App {
    // ADR-0010: the App opens nothing itself and keeps only the launch model.
    @State private var launchModel = LaunchModel(start: makeAppModels)

    var body: some Scene {
        WindowGroup {
            RootView(launchModel: launchModel)
        }
    }
}
