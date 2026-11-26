# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A bike components inventory app built in Swift and SwiftUI.

## Reference project

Use [investment-simulator-2026](https://github.com/cebartling/investment-simulator-2026) (same author, MIT, checked out next to this repo at `../investment-simulator-2026`) for examples and code reuse. Before writing an ADR or a component, check whether it has already solved the same problem:

- ADRs in `docs/adr/`, e.g. hexagonal architecture, Swift 6 concurrency, `@Observable` presentation models and injection, Swift Testing, CI, release
- Code such as the `HTTPTransport` test seam, the Keychain code behind its `CredentialStoring` port (here a token store inside the Strava adapter, not a Core port: ADR-0003), the `justfile` and the GitHub Actions workflows

Reuse what fits, and record where this project diverges and why. It is a macOS-only, SwiftPM-only app, so its build, bundle, window and distribution choices don't carry over to this iOS app (ADR-0002). Each ADR issue (#7 to #22) lists the relevant prior art.

## Current state

The repository holds `README.md`, `LICENSE` (MIT), an Xcode/Swift `.gitignore` and the docs in `docs/`. There is no Xcode project, Swift package, source code, build tooling or test target yet, so there are no build, lint or test commands. Once a project is added, update this file with them, including how to run a single test.

## Decided

- Platforms: iPhone and iPad, one universal iOS app target. Only the latest OS release is supported, down to the point release, currently iOS/iPadOS 27.2. The minimum always equals the SDK we build with, so never write `#available` checks or fallbacks, not even for point-release APIs. When a new OS release (major or point) ships, the toolchain and minimum move up together. Not macOS, visionOS, watchOS or tvOS. Audience is the author plus TestFlight testers. UIKit only where SwiftUI has no equivalent, wrapped in the UI layer. (ADR-0002)
- Architecture: hexagonal (ports and adapters). Layering rules (ADR-0003):
  - Core (the `BikeComponentsCore` module, ADR-0004) holds the domain model, its rules (wear, service intervals, Strava import reconciliation) and the driven ports. It imports Foundation only: no SwiftUI, UIKit, Observation, SwiftData, Core Data, AuthenticationServices, Security or packages. It does no I/O (e.g. `URLSession`, `FileManager`, `UserDefaults`, `Bundle` resources) and never reads the clock or the current locale, calendar or time zone: pass them in as parameters. There is no clock port. It may create IDs with `UUID()`; any other randomness is passed in. A new import into Core needs a new ADR.
  - Core's domain model types are plain value types (use-case isolation is decided in #11), never `@Model`, managed objects, SQLite records or Strava JSON types. Adapters map at their boundary; Core has no DTO or mapping layer. Invariants such as unique Strava gear IDs are enforced in Core.
  - Driven ports are protocols owned by Core, named for the role (`BikeRepository`, `RideRepository`, `BikeSource`, `RideSource`). Add a port only when Core needs one. Use cases have no protocols: callers use Core's concrete types.
  - Adapters (persistence, Strava, the SwiftUI UI) depend on Core; Core depends on nothing but Foundation. Each driven adapter is its own module, created when its first code is written. Adapter-internal seams (HTTP transport, Keychain token store) stay inside the adapter; Strava tokens never enter Core. Strava connect, disconnect and connection state go through a Core port (named in #3) that the Strava adapter implements.
  - Views and presentation code use Core's types and ports only, never a driven adapter module. Only the composition root imports adapters.
  - The app target is the composition root. Core gets ports through initializers or parameters, never from singletons, globals or service locators.
  - Core is tested through in-memory fakes of its ports: no UI, disk, network or real clock. No automated import check exists yet, so check Core's imports by hand.
- Project structure (ADR-0004):
  - `BikeComponents.xcodeproj` at the repo root holds one app target, `BikeComponents`, whose sources are a buildable folder, `BikeComponents/`. It holds only `@main` and the composition root: no views, presentation code or domain logic. Change the project in Xcode, never by hand-editing the `.pbxproj` or with a generator.
  - Every module lives in the local package `BikeComponentsKit/` (`Sources/<Module>/`, `Tests/<Module>Tests/`), iOS only. Modules: `BikeComponentsCore` (Foundation only), `BikeComponentsUI` (views and presentation code; depends on Core only), `BikeComponentsPersistence` and `BikeComponentsStrava` (driven adapters; depend on Core). Only the app target depends on adapter modules. Create a module with its first code, and give each library module a `<Module>Tests` test target.
  - A third-party package is used only by the module that needs it, never by the app target directly.
  - Tests run on an iOS Simulator with `xcodebuild` through the app's shared scheme. `swift build` and `swift test` on the Mac are not supported: they may build and pass, but they test macOS, which isn't a supported platform, so don't rely on them.

## Open decisions

Much of the architecture is still undecided. Don't assume any of the following until an ADR records it:

- persistence (SwiftData, Core Data or SQLite)
- testing framework (Swift Testing or XCTest)
- sync/backup

Architecture Decision Records live in `docs/adr/` (see ADR-0001 for the conventions). ADR files are named `NNNN-kebab-case-title.md`, start from `docs/adr/template.md`, use the Nygard format, and are listed in `docs/adr/README.md`. Record each of these decisions as an ADR when it is made, then update this file and the requirements in `README.md` to match.
