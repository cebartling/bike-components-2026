# 4. Project structure and module boundaries

- Status: Accepted
- Date: 2026-11-26

## Context

ADR-0003 needs Core to be a module of its own, depending on no adapter and not on the app, with one module per driven adapter, each with its own test target. It left the module names and how they are packaged to this ADR. It also left open, for this ADR and #14, whether a separate UI module lets the compiler stop views importing a driven adapter.

Forces at play:

- **An iOS app needs an Xcode project.** SwiftPM alone can't build, sign or run an iOS app (ADR-0002), so the reference project's SwiftPM-only build doesn't carry over.
- **Project files are hard to review.** A `.pbxproj` is noisy in diffs, merges badly, and is hard for people and agents to edit by hand. Since Xcode 16, a buildable (synchronized) folder adds its files to a target without listing each one in the `.pbxproj`.
- **Generators are tools to vet.** XcodeGen and Tuist keep the project in a text manifest, but each is a tool to install and keep in step with every Xcode release, and the dependency policy (#8) isn't decided yet.
- **The compiler can enforce layering.** A target in a Swift package can import only the targets it declares as dependencies, so `Package.swift` states the layering in plain text. Checked with Xcode 27.2: building a package for the iOS Simulator in which one target imports a sibling it doesn't declare fails with "Unable to resolve module dependency", even when that sibling is built in the same run.
- **Reference project.** investment-simulator-2026 declares `InvestmentSimulatorCore`, `InvestmentSimulatorPresentation` and one target per adapter (`InvestmentSimulatorPersistence`, `InvestmentSimulatorMarketData`) in one `Package.swift`, each library with its own test target. Its views sit in the executable target, which also imports the adapters ([ADR-0006](https://github.com/cebartling/investment-simulator-2026/blob/main/docs/adr/0006-swiftpm-only-build-and-hand-assembled-app-bundle.md)).
- **CI (#2)** runs whatever this structure needs. ADR-0002 already settled that it is `xcodebuild` against an iOS Simulator.

## Decision

We will use a thin, hand-made Xcode project for the app target and put every module in one local Swift package, on the terms below.

- **The Xcode project holds only the app.** `BikeComponents.xcodeproj` at the repository root has one app target, `BikeComponents`, whose sources sit in a buildable folder, `BikeComponents/`. Adding, moving or removing a source file doesn't change the `.pbxproj`. The project changes only for target settings, capabilities, resources such as the app icon, and new targets. It is edited in Xcode, not by hand or by a generator.
- **The app target is the composition root and nothing else.** It holds the `@main` app type and the code that builds the adapters and hands them to Core and the UI. No views, presentation code or domain logic live there.
- **One local Swift package holds the modules.** The package `BikeComponentsKit` lives in `BikeComponentsKit/` at the repository root, and the app target depends on its library products. Its `platforms` lists iOS only, at the minimum ADR-0002 sets (`.iOS("27.2")` today).
- **Modules and their dependencies:**

  | Module | Holds | Depends on |
  | --- | --- | --- |
  | `BikeComponentsCore` | Domain model, rules and driven ports (ADR-0003) | Foundation only |
  | `BikeComponentsUI` | SwiftUI views and presentation code | `BikeComponentsCore` |
  | `BikeComponentsPersistence` | The store adapter (#12) | `BikeComponentsCore`, and the store's framework or package |
  | `BikeComponentsStrava` | The Strava adapter (#3), including its HTTP transport and token store | `BikeComponentsCore` |
  | `BikeComponents` (app target) | Composition root | Every module above |

  No module depends on the app, and no module but the app depends on an adapter module. `BikeComponentsUI` can't import an adapter module, so the compiler enforces ADR-0003's rule that the UI reaches adapters only through Core. Which presentation pattern `BikeComponentsUI` uses is decided in #14.
- **Modules are created when their first code is written** (ADR-0003). The skeleton starts with `BikeComponentsCore`, `BikeComponentsUI` and the app target. `BikeComponentsPersistence` and `BikeComponentsStrava` are added with their first real code. A new module is a new target in `Package.swift` and needs no ADR if it fits the rules above, for example splitting a module that has grown. A new kind of module, or a module that breaks the dependency rules, needs a new ADR.
- **Naming.** Every module name starts with `BikeComponents`, as in the reference project, so names don't collide with system frameworks, packages or each other. A module's test target is the module name plus `Tests`, e.g. `BikeComponentsCoreTests`. `BikeComponentsUITests` is the unit test target of `BikeComponentsUI`. If an Xcode UI test target is added (#16), it gets a name that can't be mistaken for that one.
- **Folders.** The package follows SwiftPM's defaults: `BikeComponentsKit/Sources/<Module>/` and `BikeComponentsKit/Tests/<Module>Tests/`. App sources and app resources (asset catalog, `Info.plist` and entitlements, if any) live in `BikeComponents/`. Folders inside a module group code by feature or concept, with no rule set here.
- **Each library module has its own test target** in the package, depending on that module and on Core only where it needs Core's types. Test targets that need fakes of Core's ports get them as #16 decides.
- **Tests run on an iOS Simulator through the package's scheme.** Xcode generates a scheme for the package, `BikeComponentsKit`, whose Test action includes every `.testTarget` in `Package.swift`. A new test target therefore runs without anyone editing a scheme (checked with Xcode 27.2). CI and local runs use the same `xcodebuild test` invocation against that scheme, run from `BikeComponentsKit/`. The app's shared scheme, committed under `BikeComponents.xcodeproj/xcshareddata/`, builds and runs the app, and CI builds it too. The exact commands, including how to run a single test, are added to `README.md` and `CLAUDE.md` with the skeleton. `swift build` and `swift test` on the Mac aren't a supported way to build or test. Listing only iOS in `platforms` sets iOS's minimum but doesn't stop SwiftPM building the package for macOS at a default minimum, so `swift test` may well run. It runs on macOS, which ADR-0002 doesn't support, so a pass there says nothing about iOS.
- **Build settings.** Package targets set their Swift settings (for example language mode and default isolation, decided in #11) in `Package.swift`. App target settings live in the Xcode project. Signing and build configurations are decided in #21.
- **Third-party packages.** Any package dependency is declared in `Package.swift` and used only by the module that needs it, under the dependency policy (#8). The app target depends on no third-party package directly.

### Options considered

Container:

- **A thin Xcode project and one local package (chosen).** The layering lives in a text `Package.swift` that's easy to review and for agents to edit. The `.pbxproj` stays small and rarely changes. It needs no generator. It costs one hand-made project file, edited in Xcode.
- **A generated project (XcodeGen or Tuist).** Everything is text, but it adds a tool that has to keep up with Xcode releases, and a second manifest next to `Package.swift`. It would have to clear the dependency policy (#8) before the skeleton could exist. Buildable folders remove most of the `.pbxproj` churn a generator would save.
- **An Xcode project with a framework target per module, and no package.** It uses only Xcode's own tooling, but every new module, dependency or setting is a `.pbxproj` edit, which is the file that is hardest to review and to edit by hand.
- **One app target with folders for layers.** It was already rejected by ADR-0003, because nothing would enforce the boundary.

Package layout:

- **One package with many targets (chosen).** One manifest shows every module and dependency, as in the reference project.
- **One package per module.** Each module would get its own manifest and version of the same settings, linked by relative paths. It suits modules shared between apps, which this project doesn't have.
- **`Package.swift` at the repository root, next to the project.** It saves a folder, but mixes the package's files with the project's and the app's at one level. A `BikeComponentsKit/` folder keeps them apart.

Where tests run:

- **The package's generated scheme (chosen).** It picks up every test target in `Package.swift` by itself.
- **The app's shared scheme.** One scheme would build the app and run the tests, but package test targets join its Test action only when someone adds them in Xcode's scheme editor. A test target added to `Package.swift` alone would never run, while CI stayed green.

Where the UI lives:

- **A separate `BikeComponentsUI` module (chosen).** The compiler enforces that views and presentation code never import an adapter, and the app target shrinks to the composition root.
- **Views in the app target, as in the reference project.** One module fewer, but the app target imports every adapter, so only code review would keep views away from them.

Module names:

- **Prefixed with `BikeComponents` (chosen).** The reference project's convention. Longer imports, but no collisions.
- **Short names (`Core`, `UI`, `Persistence`, `Strava`).** Shorter imports, but generic names can collide with other modules, and `Core` reads like one of Apple's `Core*` frameworks.

### Where this diverges from the reference project

- **Build.** The reference project has no Xcode project and builds with SwiftPM alone. Here an Xcode project builds the app and runs the tests on a simulator, because an iOS app needs one (ADR-0002).
- **Views.** The reference project's views sit in its executable target, which imports every adapter. Here they sit in `BikeComponentsUI`, which can't.
- **Platforms.** The reference package targets macOS, and `swift test` is its test command. This package lists only iOS. SwiftPM could still build it for macOS, but `swift test` isn't a supported check here.
- **Xcode.** The reference project doesn't use the Xcode IDE and has no `#Preview` blocks for that reason. Here the Xcode IDE is used, so previews are possible. Whether to write them is left to the UI ADRs.

## Consequences

- **Easier:** reviewing the layering, which is one table of dependencies in `Package.swift`; adding a module, which is a text edit; keeping views away from adapters, which the compiler checks; adding files without touching the `.pbxproj`.
- **Harder:** the `.pbxproj` can't be generated, so its rare changes have to be made in Xcode and reviewed as they are. Tests need a simulator, so they're slower to start than `swift test` on the Mac.
- **Skeleton.** A follow-up issue creates the project, the package with `BikeComponentsCore` and `BikeComponentsUI` and their test targets, and the app's shared scheme. It adds the build and test commands, including running a single test, to `README.md` and `CLAUDE.md`.
- **CI (#2)** runs `xcodebuild test` against the package's `BikeComponentsKit` scheme on an iOS Simulator, and builds the app with `BikeComponents.xcodeproj` and its shared scheme.
- **Concurrency (#11)** sets language mode and default isolation per target in `Package.swift` and in the app target's settings.
- **Persistence (#12).** The store's framework or package is imported only by `BikeComponentsPersistence`.
- **State management (#14)** decides the presentation pattern inside `BikeComponentsUI`, and whether presentation code needs a module of its own.
- **Testing (#16)** decides the framework, where shared fakes of Core's ports live (for example a test-support target), and whether there is an Xcode UI test target.
- **Release (#21)** decides signing and build configurations for the app target.
- **Localization (#22)** decides where string catalogs live, since package targets and the app target can both hold resources.
- **Core's imports.** The package stops Core importing other modules but not system frameworks. The Foundation-only check stays a follow-up from ADR-0003.
- **Agents.** `CLAUDE.md` records the module names, their dependencies and where code goes.
