# 5. Concurrency model

- Status: Accepted
- Date: 2026-11-26

## Context

The concurrency settings change what compiles. Switching the language mode, the default actor isolation or the `Sendable` rules after code exists produces errors across every file. No code exists yet, and the skeleton (ADR-0004) waits for this ADR so that Xcode's app template doesn't decide it.

ADR-0003 left two questions here: whether use cases are structs, classes or actors, and whether driven ports are `async` and `Sendable`. ADR-0004 puts the package targets' Swift settings in `Package.swift`, and the app target's in the Xcode project.

Forces at play:

- **The toolchain.** Xcode 27.2 ships Swift 6.4.2. ADR-0002 keeps the toolchain on the latest release, so every concurrency API in it is available without `#available` checks.
- **Xcode's app template.** In Xcode 27.2, a new app target gets `SWIFT_VERSION = 5.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES`. The last turns on, among others, the upcoming features `NonisolatedNonsendingByDefault` (a `nonisolated` `async` function runs on its caller's actor unless it is marked `@concurrent`) and `InferIsolatedConformances` (a main-actor type's protocol conformances are main-actor isolated). Swift packages get none of these: a package target defaults to nonisolated, and its features are whatever `Package.swift` enables.
- **Swift 6 mode doesn't turn those two features on.** Checked with Swift 6.4.2 in Swift 6 mode: passing main-actor state of a non-`Sendable` type to a plain `nonisolated` `async` function fails with "sending value of non-Sendable type risks causing data races" unless `NonisolatedNonsendingByDefault` is enabled, and a main-actor class can't conform to a nonisolated protocol unless `InferIsolatedConformances` is enabled. With both enabled in `Package.swift`, a two-target package (one nonisolated, one main-actor by default) builds for the iOS Simulator.
- **The work is mostly I/O, not CPU.** The first concurrent code is the Strava import (#3): paging, rate-limit back-off and token refresh. Strava's refresh token can rotate, and the old one stops working at once, so two refreshes must never race. Core's rules (wear, service intervals, import reconciliation) are small calculations over one athlete's bikes and rides.
- **Core is Foundation only** (ADR-0003). It can't use Observation, Synchronization or any UI framework.
- **Reference project.** investment-simulator-2026's [ADR-0003](https://github.com/cebartling/investment-simulator-2026/blob/main/docs/adr/0003-swift-6-concurrency-and-actor-isolation.md) uses Swift 6 mode in every target. Its Core is nonisolated with `Sendable` value types. Its app and presentation targets set `defaultIsolation(MainActor.self)`. Driven ports are `Sendable` protocols, `async` when they do I/O, and adapters hide their own isolation behind the port. Heavy work uses structured concurrency and checks for cancellation. It uses no Combine, streams use `AsyncSequence`, and it has no global mutable state. Its `Package.swift` enables no upcoming features. Its presentation target marks value types that leave the main actor `nonisolated`, and moves blocking work off it with `@concurrent`.

## Decision

We will use Swift 6 language mode, a nonisolated Core and adapters, and a main-actor UI and app target, following the reference project, on the terms below.

- **Swift 6 language mode in every target**, package and app. The app target's `SWIFT_VERSION` changes from the template's `5.0` to `6`. No target drops to Swift 5 mode.
- **The same two upcoming features in every target:** `NonisolatedNonsendingByDefault` and `InferIsolatedConformances`. Package targets enable them with `.enableUpcomingFeature(...)` in `Package.swift`, from one shared list of Swift settings. The app target sets `SWIFT_UPCOMING_FEATURE_NONISOLATED_NONSENDING_BY_DEFAULT` and `SWIFT_UPCOMING_FEATURE_INFER_ISOLATED_CONFORMANCES` to `YES` explicitly, so it doesn't depend on the Approachable Concurrency setting, which Xcode's build-setting spec defines only for Swift 5 mode and earlier. An `async` function then behaves the same in every module: it runs on its caller's actor, and runs elsewhere only when it is marked `@concurrent` or belongs to an actor. Enabling another upcoming feature takes a new ADR.
- **Default isolation per module:**

  | Module | Default isolation |
  | --- | --- |
  | `BikeComponentsCore` | nonisolated (SwiftPM's default) |
  | `BikeComponentsUI` | `MainActor`, via `.defaultIsolation(MainActor.self)` |
  | `BikeComponentsPersistence`, `BikeComponentsStrava` | nonisolated |
  | `BikeComponents` (app target) | `MainActor`, as the template sets it |
  | Test targets | the same as the module they test |

  In a main-actor module, a type that has to be used off the main actor, such as a value type handed to Core or to an adapter, is marked `nonisolated`, as in the reference project.
- **Core has no actors and no shared mutable state.** Domain types are value types that declare `Sendable`. Use cases are structs or functions that take their ports as `let` properties or parameters, so they are `Sendable` too. Their state lives in the repositories, not in the use case. Use cases are `async` when they call a port, and synchronous when they are pure. A use case runs on its caller's actor. If profiling shows a Core calculation is slow enough to stall the UI, that function is marked `@concurrent`.
- **Driven ports are `Sendable` protocols.** A port method that does I/O is `async`. How port methods report errors is decided with the error model (#18). An adapter hides its own isolation behind the port: an actor, a framework's own isolation, or plain `async` calls into a framework that doesn't block.
- **Adapters never block their caller.** Because `async` functions run on their caller's actor, a port method called from the UI runs on the main actor unless the adapter moves it. Blocking or CPU-heavy work in an adapter, such as synchronous disk access or decoding a large response, runs in a `@concurrent` function or on an actor the adapter owns. Plain `await`s on non-blocking APIs, such as `URLSession`'s `async` methods, need neither.
- **Where actors live.** An actor is used when the adapter owns mutable state that concurrent calls share. The first one is in the Strava adapter: whatever holds the tokens and refreshes them is an actor that keeps a refresh in progress as a stored task, so concurrent requests await the same refresh, and a rotated refresh token is saved before any other request uses the token pair (#3). An actor alone isn't enough: it is reentrant, so while the first caller awaits the refresh, a second caller could start another one. The persistence adapter's isolation is decided with the store (#12), behind a `Sendable` port. The UI's state is on the main actor.
- **Escape hatches need a reason.** `@unchecked Sendable`, `nonisolated(unsafe)` and `@preconcurrency` are allowed only with a comment next to them that says why the code is safe, or which framework forces it. An actor or a value type comes first. In an adapter, a class with mutable state can instead protect it with Synchronization's `Mutex`, if it has to stay synchronous.
- **Structured concurrency first.** Parallel work uses `async let` or a task group. Unstructured tasks start in the UI layer, preferably with SwiftUI's `.task` modifier, which cancels its task when the view goes away. An adapter may start one only where structured concurrency can't express the work: a task in progress that several callers share, such as the token refresh, or the producer of an `AsyncStream`. The adapter keeps the task's handle, cancels it when the work is no longer needed, and says why in a comment. No `Task.detached`, no Dispatch queues and no completion-handler APIs in our own code. An adapter wraps a callback-only framework API with a checked continuation.
- **No Combine.** UI state flows through the presentation pattern #14 picks, and values over time use `AsyncSequence`.
- **`AsyncSequence` and `AsyncStream` are allowed** for values that arrive over time, such as import progress or rides arriving page by page. Whether `RideSource` returns a stream is decided with #3's sync model (ADR-0003). The producer of an `AsyncStream` stops when its consumer is cancelled, for example by cancelling its work in `onTermination`.
- **Long-running work is cancellable.** A Strava import, especially a first backfill, checks for cancellation between pages and stops with `CancellationError`. What it saved before it stopped stays saved, and the next import resumes from there (ADR-0003). Cancellation is not a failure: the UI doesn't show it as an error. Waits such as rate-limit back-off use a cancellable sleep.
- **No global mutable state.** A global or `static` value is a `let` of a `Sendable` type. This supports ADR-0003's rule against singletons and service locators.

### Options considered

Language mode:

- **Swift 6 mode (chosen).** The compiler rejects data races. Nothing has been written yet, so there is nothing to migrate.
- **Swift 5 mode with complete checking**, the template's language mode. The same diagnostics, but as warnings that can pile up, and a move to Swift 6 mode later anyway.

Default isolation:

- **Nonisolated Core and adapters, main-actor UI and app (chosen).** Core and the adapters don't depend on the main actor, and UI code needs no `@MainActor` annotations. Contributors must know which module they are in.
- **Main actor everywhere**, which Xcode's templates lean towards. One rule, but Core's types and functions would be main-actor isolated, and an adapter would have to opt out of the main actor on every method that does I/O.
- **Nonisolated everywhere.** One rule, but every presentation type needs `@MainActor` by hand, and forgetting it is easy.

Upcoming features:

- **`NonisolatedNonsendingByDefault` and `InferIsolatedConformances` everywhere (chosen).** The app target gets them from the template anyway, so `async` code behaves the same in the package and the app. The UI can pass its own non-`Sendable` state to Core's `async` functions, and moving work off the caller is an explicit `@concurrent`. The cost: an adapter that blocks would block the main actor unless it moves the work, which is why adapters must not block their caller.
- **Only what Swift 6 mode turns on**, as in the reference project's package. Fewer settings, but the app target would differ from the package unless its template settings were turned off, and every value a main-actor caller passes to a nonisolated `async` function would have to be `Sendable`.

Use cases:

- **Structs and functions (chosen).** They hold no state, so they need no isolation of their own and run where they are called.
- **Actors.** They serialize access to state that use cases don't have, and add a hop for every call.
- **Classes.** A reference type would need its own `Sendable` justification, and gains nothing over a struct.

Values over time:

- **`async`/`await` and `AsyncSequence` (chosen).** Checked by the compiler and cancelled with their task.
- **Combine.** It isn't checked for isolation, and it overlaps with Observation in the UI.
- **Callbacks and delegates.** Hard to cancel and to test, and the compiler checks less of them.

### Where this diverges from the reference project

- **Upcoming features.** The reference project's package enables none. Here every target enables `NonisolatedNonsendingByDefault` and `InferIsolatedConformances`, so the package matches the Xcode app target, which turns them on through its template.
- **App target.** The reference project's app is a SwiftPM executable target with `defaultIsolation(MainActor.self)`. Here the app target is in an Xcode project and gets its settings from the project, starting from Xcode's template with the language mode changed to Swift 6.
- **Adapters.** The reference project's CPU-heavy work is simulation inside Core. Here the work is mostly I/O in the adapters, so the rule that matters is that adapters don't block their caller.

## Consequences

- **Easier:** reasoning about where code runs, because `async` code stays on its caller's actor unless it says otherwise; sharing state between the UI and Core without making every type `Sendable`; cancelling an import; testing Core without actors.
- **Harder:** every domain type and port must be `Sendable`. Adapters that wrap non-`Sendable` framework types need an actor or a careful boundary. Main-actor and nonisolated modules sit side by side, so a value type in `BikeComponentsUI` that leaves the main actor has to be marked `nonisolated`. A blocking call in an adapter compiles but stalls the UI, so code review has to catch it.
- **Skeleton (ADR-0004).** `Package.swift` declares the shared Swift settings and `.defaultIsolation(MainActor.self)` for `BikeComponentsUI` and its test target. It needs `swift-tools-version` 6.2 or later for `.defaultIsolation`. In Xcode, the app target's `SWIFT_VERSION` is set to `6` and the two upcoming-feature settings to `YES`. These are project changes, so the user makes them.
- **Persistence (#12)** decides the store adapter's isolation, for example SwiftData's `ModelActor`, behind a `Sendable` port. A store whose objects aren't `Sendable` must not let them reach Core.
- **State management (#14)** picks the presentation pattern inside the main-actor `BikeComponentsUI`, and how it starts and cancels tasks.
- **Networking and error model (#18)** decides how ports report errors, how the Strava adapter's transport is isolated, and how back-off waits are tested.
- **Testing (#16)** decides how `async` code is tested. Test targets use the same isolation as the module they test.
- **Toolchain upgrades.** ADR-0002 moves the toolchain with every OS release. A future language mode may turn on these features, or change their behavior. That migration then takes an ADR.
- **Agents.** `CLAUDE.md` records the concurrency rules.
