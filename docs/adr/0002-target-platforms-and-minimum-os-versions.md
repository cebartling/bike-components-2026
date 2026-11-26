# 2. Target platforms and minimum OS versions

- Status: Accepted
- Date: 2026-11-26

## Context

The target platforms and the minimum OS version decide which APIs the app can use at all. Most of the other open ADRs depend on this one: project structure (#10), concurrency (#11), persistence (#12), state management (#14), navigation (#17), styling (#19) and release (#21). So do CI (#2) and the Strava integration (#3).

Forces at play:

- **Strava sign-in.** The plan in #3 is written for iOS: `ASWebAuthenticationSession`, plus the `strava://` scheme when the Strava app is installed.
- **API availability.** The Observation framework and SwiftData need iOS 17. The Liquid Glass design needs the 26 releases. The current releases are 27.x (Xcode 27.2, Swift 6.4).
- **Audience.** The app is for its author and a small group of TestFlight testers. A small, known audience can be asked to keep their devices on the latest OS.
- **Reference project.** investment-simulator-2026 targets macOS 26 only and is built with SwiftPM alone. Its build, bundle, window and distribution decisions don't carry over to an iOS app. Its architecture, concurrency, testing and code do.
- **Cost of a second platform.** Every additional platform adds layouts, navigation and scene structure, a test matrix and a release path.

## Decision

- **Platforms: iPhone and iPad.** The app is one universal iOS app that supports both device families.
- **One target, not one per platform.** A single SwiftUI app target serves iPhone and iPad and adapts to size classes and window sizes. There is no separate iPad target.
- **Only the latest OS is supported. Today that means a minimum of iOS 27 and iPadOS 27.** Observation, SwiftData, Liquid Glass and every API in the current SDK are available without availability checks or fallbacks.
- **Not targeted:** macOS (including Mac Catalyst and running the iPad app on Apple silicon Macs), visionOS, watchOS and tvOS. These are not built, tested or supported. Adding one takes a new ADR.
- **Audience: the author and TestFlight testers.** There is no plan for an App Store release. Changing that takes a new ADR. Release mechanics are decided in #21.
- **Raising the minimum OS.** The minimum follows the latest major release. When a new major version ships (e.g. iOS 28), we move the toolchain to the Xcode that ships with it and raise the minimum to match, in the same change. That change updates the project's deployment target and `README.md`. It needs no new ADR, because this ADR sets the policy. Lowering the minimum, or supporting more than the latest major release, does need a new ADR.
- **UIKit interop.** SwiftUI is the default. `UIViewRepresentable` and `UIViewControllerRepresentable` are allowed only where SwiftUI has no equivalent. Each use is wrapped in a small, dedicated type in the UI layer, with a comment saying which SwiftUI gap it fills. No UIKit types appear outside the UI layer. OAuth doesn't need UIKit: SwiftUI's `webAuthenticationSession` environment value drives `ASWebAuthenticationSession`.

## Consequences

- **Project structure (#10).** An iOS app can't be built with SwiftPM alone, as the reference project does for macOS. The app needs an Xcode project or a project generator. Local Swift packages for the domain and adapters remain possible.
- **CI (#2).** CI builds and tests with `xcodebuild` against an iOS Simulator destination, not `swift build` / `swift test`. iPhone and iPad simulators are both candidates for the test matrix.
- **Persistence (#12) and state management (#14).** SwiftData and Observation are available, so neither ADR has to rule them out on OS grounds.
- **Styling (#19).** Liquid Glass is available without fallbacks.
- **No compatibility code.** There are no `#available` checks or fallback paths for older OS versions. Every new API in the latest SDK can be used as soon as the minimum is raised.
- **Yearly upgrade work.** Each new major release brings a toolchain upgrade and a minimum-OS bump. Any deprecations and new warnings have to be dealt with then, not deferred.
- **Navigation (#17).** iPad needs adaptive layouts, likely `NavigationSplitView`, and must handle any window size, because iPadOS windows can be freely resized (since iPadOS 26). macOS window and scene layout is out of scope.
- **Release (#21).** Distribution is through TestFlight, which needs an Apple Developer Program membership and App Store Connect. The reference project's Developer ID, notarization and GitHub Releases path doesn't apply.
- **Strava (#3).** The iOS OAuth plan stands. Because TestFlight puts the app on other people's devices, the client secret question in #3 needs an answer before the app reaches testers.
- **Audience.** Testers must run the latest major iOS or iPadOS release, and update each year when a new one ships. Devices that can't run the latest release lose support.
- **Requirements.** `README.md` records the platforms and minimum OS versions.
