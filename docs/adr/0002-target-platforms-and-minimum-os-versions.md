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

We will build one universal SwiftUI app for iPhone and iPad, on the terms below.

- **Platforms: iPhone and iPad.** The app is one universal iOS app that supports both device families.
- **One target, not one per platform.** A single SwiftUI app target serves iPhone and iPad and adapts to size classes and window sizes. There is no separate iPad target.
- **Only the latest OS release is supported, down to the point release. Today that means a minimum of iOS 27.2 and iPadOS 27.2.** The minimum always equals the SDK we build with, so Observation, SwiftData, Liquid Glass and every API in that SDK, including ones added in point releases, are available without availability checks or fallbacks.
- **Not targeted:** macOS (including Mac Catalyst and running the iPad app on Apple silicon Macs), visionOS, watchOS and tvOS. These are not built, tested or supported. Adding one takes a new ADR.
- **Audience: the author and TestFlight testers.** There is no plan for an App Store release. Changing that takes a new ADR. Release mechanics are decided in #21.
- **Raising the minimum OS.** The minimum follows the latest release, major or point. When a new release ships with its SDK (e.g. iOS 27.3 or iOS 28), we move the toolchain to the Xcode that ships that SDK and raise the minimum to match, in the same change. That change updates the deployment target of every app target and local Swift package (the `platforms` in each `Package.swift`, written as a string such as `.iOS("27.2")` because the version constants cover only major releases), the Xcode version CI builds with, `README.md` and `CLAUDE.md`. It needs no new ADR, because this ADR sets the policy. Lowering the minimum, or supporting more than the latest release, does need a new ADR.
- **UIKit interop.** SwiftUI is the default. `UIViewRepresentable` and `UIViewControllerRepresentable` are allowed only where SwiftUI has no equivalent. Each use is wrapped in a small, dedicated type in the UI layer, with a comment saying which SwiftUI gap it fills. No UIKit types appear outside the UI layer. OAuth doesn't need UIKit: SwiftUI's `webAuthenticationSession` environment value drives `ASWebAuthenticationSession`.

### Options considered

Platforms:

- **iPhone only.** Smallest scope, but iPad would run the app in compatibility mode. With one universal target, supporting iPad properly costs adaptive layouts, not a second app.
- **iPhone, iPad and Mac (one multiplatform target).** Most reach, but adds Mac navigation, window and scene layout, and a second distribution path. Mac Catalyst and running the iPad app on Apple silicon Macs were rejected for the same reason: they still make the Mac a supported platform.
- **Mac only.** Would reuse the reference project's build, CI and release almost unchanged, but the Strava sign-in plan in #3 is written for iOS and would need rework.
- **A separate iPad target.** A single target already adapts to size classes and window sizes. A second one would duplicate configuration for no gain.

Minimum OS:

- **iOS 17.** The lowest version with Observation and SwiftData. Widest reach, but Liquid Glass and every newer API would need availability checks and fallbacks.
- **One release behind the current one (iOS 26).** This was the first proposal. It was rejected in favor of supporting only the latest release, which removes compatibility code entirely.
- **Latest major release only (iOS 27.0).** APIs added in point releases would need `#available` checks, or would have to wait for the next major release. Tracking the point release avoids both.
- **Raise the minimum only when a newer API is worth it, with a new ADR each time.** Replaced by the latest-release policy, which needs no ADR per bump.

Audience:

- **The author only.** Not chosen: builds are shared with TestFlight testers.
- **App Store release.** Not planned. It would need a backend for the Strava token exchange (#3), App Review, and a review of Strava's API agreement.

## Consequences

- **Project structure (#10).** An iOS app can't be built with SwiftPM alone, as the reference project does for macOS. The app needs an Xcode project or a project generator. Local Swift packages for the domain and adapters remain possible.
- **CI (#2).** CI builds and tests with `xcodebuild` against an iOS Simulator destination, not `swift build` / `swift test`. iPhone and iPad simulators are both candidates for the test matrix.
- **Persistence (#12) and state management (#14).** SwiftData and Observation are available, so neither ADR has to rule them out on OS grounds.
- **Styling (#19).** Liquid Glass is available without fallbacks.
- **No compatibility code.** There are no `#available` checks or fallback paths for older OS versions, not even for point releases. Every API in the SDK we build with can be used.
- **Upgrade work with every release.** Each major release brings a toolchain upgrade and a minimum-OS bump, and any deprecations and new warnings have to be dealt with then, not deferred. Each point release brings a smaller toolchain update and bump.
- **Navigation (#17).** iPad needs adaptive layouts, likely `NavigationSplitView`, and must handle any window size, because iPadOS windows can be freely resized (since iPadOS 26). macOS window and scene layout is out of scope.
- **Release (#21).** Distribution is through TestFlight, which needs an Apple Developer Program membership and App Store Connect. The reference project's Developer ID, notarization and GitHub Releases path doesn't apply. App Store Connect offers iPhone and iPad apps on Apple silicon Macs and Apple Vision Pro by default, so both have to be turned off for this app to keep it off platforms it doesn't support. TestFlight builds expire 90 days after upload, so a new build has to reach testers at least that often or the app stops opening.
- **Strava (#3).** The iOS OAuth plan stands. Because TestFlight puts the app on other people's devices, the client secret question in #3 needs an answer before the app reaches testers.
- **Audience.** Testers must run the latest iOS or iPadOS release, including point releases. TestFlight won't install a build on a device below its minimum, so testers update their OS before they can take a new build. Devices that can't run the latest release lose support.
- **Requirements.** `README.md` records the platforms and minimum OS versions.
