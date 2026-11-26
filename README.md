# bike-components-2026

A bike components inventory app built in Swift and SwiftUI.

## Status

Early setup. There is no app code yet. The basic architecture (persistence, testing and more) is being decided and recorded as [Architecture Decision Records](docs/adr/README.md) before the first feature is built.

## Requirements

| Requirement | Value |
| --- | --- |
| Xcode | 27.2, the version that ships the latest iOS SDK ([ADR-0002](docs/adr/0002-target-platforms-and-minimum-os-versions.md)) |
| Swift | TBD |
| Target platforms | iPhone and iPad ([ADR-0002](docs/adr/0002-target-platforms-and-minimum-os-versions.md)) |
| Minimum OS versions | iOS 27.2, iPadOS 27.2: latest release only, including point releases ([ADR-0002](docs/adr/0002-target-platforms-and-minimum-os-versions.md)) |

## Build, run and test

TBD. There is no Xcode project or Swift package yet. The app will be a thin Xcode project, `BikeComponents.xcodeproj`, with its modules in the local Swift package `BikeComponentsKit/`. Tests will run on an iOS Simulator with `xcodebuild` ([ADR-0004](docs/adr/0004-project-structure-and-module-boundaries.md)). This section will describe how to build and run the app, how to run the full test suite, and how to run a single test once the skeleton exists and the testing framework is decided.

## Documentation

- [`docs/`](docs/) holds longer-form project documentation.
- [`docs/adr/`](docs/adr/README.md) holds the Architecture Decision Records and their index.

## License

[MIT](LICENSE)
