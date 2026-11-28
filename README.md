# bike-components-2026

A bike components inventory app built in Swift and SwiftUI.

## Status

Early setup. The project skeleton builds, launches and tests, with no features yet. The remaining architecture (design system, logging and more) is being decided and recorded as [Architecture Decision Records](docs/adr/README.md) before the first feature is built.

## Requirements

| Requirement | Value |
| --- | --- |
| Xcode | 27.2, the version that ships the latest iOS SDK ([ADR-0002](docs/adr/0002-target-platforms-and-minimum-os-versions.md)) |
| Swift | 6.4, as shipped with Xcode 27.2, in Swift 6 language mode ([ADR-0005](docs/adr/0005-concurrency-model.md)) |
| Target platforms | iPhone and iPad ([ADR-0002](docs/adr/0002-target-platforms-and-minimum-os-versions.md)) |
| Minimum OS versions | iOS 27.2, iPadOS 27.2: latest release only, including point releases ([ADR-0002](docs/adr/0002-target-platforms-and-minimum-os-versions.md)) |
| Apple Developer Program | A development team, for the iCloud (CloudKit) capability and TestFlight ([ADR-0009](docs/adr/0009-sync-and-backup-with-cloudkit.md)) |

## Build, run and test

The app is a thin Xcode project, `BikeComponents.xcodeproj`, with its modules in the local Swift package `BikeComponentsKit/` ([ADR-0004](docs/adr/0004-project-structure-and-module-boundaries.md)). Commands run through [`just`](https://github.com/casey/just), installed with Homebrew (`brew install just`):

- `just build` builds the app for the iPhone 18 Pro simulator (iOS 27.2).
- `just test` runs every test in `BikeComponentsKit` on that simulator, with Swift Testing ([ADR-0012](docs/adr/0012-testing-strategy.md)).
- `just test-only '<identifier>'` runs one test, suite or target, for example ``just test-only 'BikeComponentsCoreTests/`Source errors`'``. It fails when the identifier matches nothing.

To run the app, open `BikeComponents.xcodeproj` in Xcode, or install the built app with `xcrun simctl`. The app target's build settings live in `Config/BikeComponents.xcconfig` ([ADR-0013](docs/adr/0013-build-configuration-and-secrets.md)), and project changes are made with Apple's `xcodeproj` tool ([ADR-0015](docs/adr/0015-project-file-changes-with-xcodeproj.md)). Per-developer values such as the Strava client ID will go in a local, git-ignored `Config/Secrets.xcconfig`, and the Strava integration will document its keys.

## Documentation

- [`docs/`](docs/) holds longer-form project documentation.
- [`docs/adr/`](docs/adr/README.md) holds the Architecture Decision Records and their index.

## License

[MIT](LICENSE)
