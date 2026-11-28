# bike-components-2026

A bike components inventory app built in Swift and SwiftUI.

## Status

Early setup. There is no app code yet. The remaining architecture (navigation, design system and more) is being decided and recorded as [Architecture Decision Records](docs/adr/README.md) before the first feature is built.

## Requirements

| Requirement | Value |
| --- | --- |
| Xcode | 27.2, the version that ships the latest iOS SDK ([ADR-0002](docs/adr/0002-target-platforms-and-minimum-os-versions.md)) |
| Swift | 6.4, as shipped with Xcode 27.2, in Swift 6 language mode ([ADR-0005](docs/adr/0005-concurrency-model.md)) |
| Target platforms | iPhone and iPad ([ADR-0002](docs/adr/0002-target-platforms-and-minimum-os-versions.md)) |
| Minimum OS versions | iOS 27.2, iPadOS 27.2: latest release only, including point releases ([ADR-0002](docs/adr/0002-target-platforms-and-minimum-os-versions.md)) |
| Apple Developer Program | A development team, for the iCloud (CloudKit) capability and TestFlight ([ADR-0009](docs/adr/0009-sync-and-backup-with-cloudkit.md)) |

## Build, run and test

TBD. There is no Xcode project or Swift package yet. The app will be a thin Xcode project, `BikeComponents.xcodeproj`, with its modules in the local Swift package `BikeComponentsKit/`. Tests will run on an iOS Simulator with `xcodebuild` ([ADR-0004](docs/adr/0004-project-structure-and-module-boundaries.md)). Tests use Swift Testing ([ADR-0012](docs/adr/0012-testing-strategy.md)). Once the skeleton adds the `justfile`, `just test` will run every test and `just test-only '<identifier>'` one test, suite or target, with identifiers such as ``'BikeComponentsCoreTests/`Service intervals`/`a chain is due after 3000 km`()'``. [`just`](https://github.com/casey/just) is installed with Homebrew (`brew install just`). This section will describe how to build and run the app once the skeleton exists.

## Documentation

- [`docs/`](docs/) holds longer-form project documentation.
- [`docs/adr/`](docs/adr/README.md) holds the Architecture Decision Records and their index.

## License

[MIT](LICENSE)
