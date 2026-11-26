# 3. Hexagonal architecture (ports and adapters)

- Status: Accepted
- Date: 2026-11-26

## Context

The app's value is its domain logic: which components are installed on which bike, how far each one has been ridden, when it is due for service, and how a Strava import reconciles with the data the app owns. #4 sets some of those rules already: every bike comes from Strava and keeps its Strava gear ID, imports upsert by that ID, a bike missing from Strava is flagged and never deleted, and import never touches components or service records. The logic has to be right, and the project is test-driven, so it needs fast unit tests.

The edges are the parts most likely to change, and most of them are still open: the store (#12: SwiftData, Core Data or SQLite), sync and backup (#13), and the Strava API (#3), whose fields are partly unverified and whose token exchange may move behind a backend. The UI is SwiftUI on iPhone and iPad (ADR-0002).

Forces at play:

- **Testability.** Domain code that calls SwiftData, `URLSession` or the Keychain can't be tested without them.
- **Size.** One developer and a small app. Every layer of indirection is paid for again in each feature.
- **Reference project.** investment-simulator-2026's [ADR-0001](https://github.com/cebartling/investment-simulator-2026/blob/main/docs/adr/0001-hexagonal-architecture.md) adopts hexagonal architecture. Core imports Foundation only. Ports are protocols owned by Core. Each driven adapter gets its own SwiftPM target, added only when a real adapter exists. The app target is the composition root, with no singletons or service locators. SwiftPM enforces inward dependencies, and Core is tested through in-memory fakes of its ports. SwiftPM can't stop Core importing a system framework, so a SwiftLint custom rule was added later to close that gap. Its Core never reads the clock: functions take the time as a parameter (for example `fillingLimitOrders(from:at:)`).
- **Platform.** An iOS app can't be built with SwiftPM alone, so this app needs an Xcode project or a generator. Local Swift packages remain possible (ADR-0002).
- **Dependent decisions.** Project structure (#10), concurrency (#11), persistence (#12), state management (#14), dependency injection (#15) and testing (#16) all depend on where the domain boundary sits.

## Decision

We will use hexagonal architecture (ports and adapters), following the reference project, on the terms below.

- **Core is the hexagon.** A Swift module separate from the app, called Core here (its name and container are decided in #10), holds the domain model (bikes, components, installations, rides, service records), the rules that operate on it (wear, service intervals, import reconciliation) and the driven ports.
- **Core imports Foundation only.** Not SwiftUI, UIKit, Observation, SwiftData, Core Data, AuthenticationServices, Security or any third-party package. Within Foundation, Core does no I/O: no `URLSession`, `FileManager`, `UserDefaults` or `Bundle` resources. It never reads the clock either: the current date is passed in as a parameter, as in the reference project. Core may create identifiers with `UUID()`, as the reference project's Core does. Any other randomness, and anything else that varies between runs, is passed in too. Allowing another import into Core takes a new ADR.
- **Domain types are not persistence or wire types.** Core's types are plain Swift value types. `@Model` classes, managed objects, SQLite records and Strava JSON types live only in their adapter, which maps them to and from Core types at its boundary. Invariants such as "a Strava gear ID is unique across bikes" (#4) are enforced in Core. The store may enforce them too (#12).
- **Strava rules are domain; the Strava API is not.** A bike's Strava gear ID (an opaque, required, unique string) and the rule that bikes are only created by import (#4) belong to Core. OAuth, tokens, the HTTP client, paging, rate limits and JSON shapes belong to the Strava adapter. Strava tokens never enter Core.
- **Driven ports are Swift protocols owned by Core,** named for the role Core needs, not for the technology behind it. The initial ports are:
  - `BikeRepository`: loads and saves bikes and the app-owned data attached to them (components, installations, service records).
  - `RideRepository`: loads and saves imported rides, by bike.
  - `BikeSource`: fetches the athlete's bikes from Strava.
  - `RideSource`: fetches the athlete's cycling rides from Strava.

  Their methods are designed when the first code needs them. The mechanics of HTTP paging and rate-limit back-off live in the Strava adapter, but `RideSource` must let Core save rides as they arrive and resume an interrupted import without fetching again what it already has (#3). Its shape is decided with #3's sync model. A port is added only when Core needs something from outside, and a repository can be split when it grows. Whether ports are `async` and `Sendable` is decided in #11.
- **No driving-port protocols.** The outside world calls Core's use cases directly: concrete types and functions, or methods on domain types. No protocol stands in front of a use case.
- **Adapters live outside Core and depend on it.** The driven adapters are persistence (#12) and Strava (#3). The driving adapters are the SwiftUI views and whatever presentation layer #14 chooses. An adapter's own test seams, such as an HTTP transport (the reference project's `HTTPTransport`) and a Keychain token store inside the Strava adapter, are internal to that adapter, not Core ports. Connecting to Strava, disconnecting and reporting the connection state go through a Core port that the Strava adapter implements. #3 names it and designs it, including how the UI hands the result of SwiftUI's `webAuthenticationSession` (ADR-0002) to that port. The UI never imports the Strava adapter.
- **The app target is the composition root.** It builds the concrete adapters and hands them to Core. Core never reaches for a singleton, a global or a service locator to find an adapter: it receives ports through initializers or parameters. How the app passes dependencies to views is decided in #15.
- **The compiler enforces the boundary.** Core is its own module and depends on no adapter module and not on the app, so it can't import them. Each driven adapter gets its own module, created with its tests when its first real code is written. How the modules are packaged (local Swift packages or Xcode targets) is decided in #10. A module boundary doesn't stop Core importing a system framework. Until an automated check exists (see Consequences), code review enforces the Foundation-only rule.
- **Core is tested through its ports.** Core's tests use in-memory fakes of the driven ports and touch no UI, disk, network or real clock. The framework and where shared fakes live are decided in #16.

### How much ceremony

The cost we accept: a protocol per driven port, mapping code in each adapter, and one module per adapter. What we leave out to keep a small app small:

- Driving-port protocols, a protocol per use case, or a rule that every use case is its own type.
- A port before there is an adapter for it, or a module before there is code for it.
- A clock port. The date is a parameter.
- DTO or mapping layers inside Core. Mapping happens only in adapters.

A feature that touches only domain logic and UI needs no port and no new module.

### Options considered

- **Ports and adapters (chosen).** Domain logic is testable in isolation with fast tests. The store and the Strava API can change, or move behind a backend, without touching Core. The module boundary is checked by the compiler. It costs more types and some mapping code. This is the reference project's choice, and its code (the `HTTPTransport` seam, port shapes, the import lint rule) can be reused.
- **A lighter split: a domain core with no ports.** Core would hold the domain types and pure rules, and presentation models would call the store and Strava themselves. Fewer types, but the orchestration #4 cares most about (fetch bikes from Strava, upsert by gear ID, flag missing bikes, leave app data alone) would live in presentation models, tested only through fakes at that level or not at all. Rejected because import reconciliation is domain logic that needs both the store and Strava.
- **Layered (UI, services, data).** Familiar and simple to explain. But the domain depends on the data layer, so testing domain logic needs a real or faked store underneath it, and changing the store ripples up through the services. Rejected.
- **SwiftUI-first, as in Apple's samples.** `@Model` types are the domain, views use `@Query`, and logic lives in views and models. Least code and fastest to start. Rejected: wear and import rules would be tangled with SwiftData and hard to unit test, it would decide #12 in favor of SwiftData before that ADR is written, and sync (#13) constraints such as CloudKit's (no unique constraints, every property optional or defaulted) would land on the domain types.
- **Enforcement by convention only** (one app target, folders for layers). Less setup, but nothing stops domain code importing SwiftData or a view reaching an adapter, and the boundary would decay unnoticed. Rejected: the app needs an Xcode project anyway (ADR-0002), and a separate module costs little to add.

### Where this diverges from the reference project

- **Packaging.** The reference project declares Core and each adapter as targets in one `Package.swift` and builds with SwiftPM only. This app needs an Xcode project (ADR-0002), so how the modules are packaged is left to #10.
- **Import check.** The reference project enforces Core's imports with a SwiftLint custom rule. There is no linter here yet, and adopting one falls under the dependency policy (#8), so the check is a follow-up.
- **Credentials.** In the reference project, `CredentialStoring` is a Core port, because the user types an API key into Settings. Here the Strava tokens come from OAuth and only the Strava adapter uses them, so token storage stays inside that adapter.
- **Driving side.** The reference project calls use cases "driving ports" without giving them protocols. This ADR says outright that they have none.

## Consequences

- **Easier:** testing wear, service intervals and import reconciliation with fast, in-memory tests; choosing and later changing the store (#12); absorbing changes to the Strava API, or a backend for the token exchange (#3), in the Strava adapter alone.
- **Harder:** a feature that crosses an edge touches more files: the Core type, the port, the adapter, its mapping and the wiring. Mapping code between Core types and store or wire types is extra code, and it needs tests in the adapter's own test target.
- **Persistence (#12).** Whichever store is chosen, its types stay inside the persistence adapter and are mapped to Core types. With SwiftData, views can't use `@Query` and `@Model` objects never reach the UI, so much of its convenience over Core Data or GRDB is lost. #12 should weigh that.
- **Project structure (#10).** The structure has to provide Core as a module that depends on no adapter and not on the app, plus one module per driven adapter, each with its own test target.
- **Concurrency (#11).** Decides the isolation of Core's types and whether ports are `async` and `Sendable`.
- **State management (#14) and dependency injection (#15).** The presentation layer depends on Core and its ports, not on adapter modules. Ports are what the composition root injects.
- **Testing (#16).** Core is tested with in-memory fakes of its ports. Adapters are tested on their own: persistence against an in-memory store, Strava against fixture JSON through an injected transport.
- **Follow-up:** an automated check that Core imports only Foundation, such as the reference project's lint rule or a script in CI (#2), once the tooling is decided. Until then, code review enforces it.
- **Revisit:** whether one module per driven adapter stays worthwhile, and whether `BikeRepository` should be split, once real code exists.
- **Agents.** `CLAUDE.md` records the layering rules.
