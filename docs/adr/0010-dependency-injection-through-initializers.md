# 10. Dependency injection through initializers

- Status: Accepted
- Date: 2026-11-27

## Context

Every feature needs collaborators: Core's repository ports, the Strava adapter (#3), the current date and a calendar. How they are supplied decides how easily tests and previews swap in fakes. Picking one style before the first feature avoids a mix of singletons, environment values and initializer arguments that has to be untangled later.

Earlier ADRs already settle part of it:

- **ADR-0003.** The app target is the composition root. It builds the adapters and hands Core its ports through initializers or parameters. Core never reaches for a singleton, a global or a service locator, and never reads the clock, the current calendar or the time zone: they are passed in. There is no clock port. It left to this ADR the mechanism outside Core and any singleton rule for the rest of the app.
- **ADR-0004.** The app target holds only `@main` and the composition root. Only it imports the adapter modules, and `BikeComponentsUI` can't.
- **ADR-0005.** Ports are `Sendable` protocols. Use cases are `Sendable` structs or functions that hold their ports. Globals and `static`s are `let`s of `Sendable` types. `BikeComponentsUI` and the app target are main-actor by default.
- **ADR-0006.** A package needs an accepted ADR that admits it, and only when Apple's frameworks can't do the job.
- **ADR-0007.** The store opens through an `async`, `@concurrent` function in `BikeComponentsPersistence`, and opening can fail. If it fails, the app shows an error naming the path and the cause, and never falls back to an empty or in-memory store. One actor implements every repository port.
- **ADR-0008.** Screens are driven by `@Observable` presentation models, built by their owner: the `App`, or the view or model that presents the screen. A model's initializer does no work. Models reach views through view initializers and never go in the environment, which carries the system frameworks' own values. App-wide models live on the `App`, and those that need a repository are built after the store opens. It left to this ADR how an owner gets the ports to build a model, how the current date, a calendar or a time zone reaches a model, the fakes used in previews, what the `App` holds while the store opens or after it fails, and whether anything else goes in the environment.
- **ADR-0009.** An app-wide model that consumes the remote-change port is built by the composition root after the store opens, kept on the `App`, and runs from the root view's `.task`.

Forces at play:

- **Testability.** The project is test-driven. Model tests use Core's real use cases over in-memory fakes of the ports (ADR-0008), so the fakes have to get into the model without touching shipping code.
- **The store isn't there at launch.** Every repository port is the persistence actor, and it exists only once the store has opened, asynchronously. `App.init` can't wait for it.
- **The wiring compiles under our settings.** Checked with Xcode 27.2, building for the iOS Simulator with ADR-0005's settings: a main-actor `@Observable` model that stores a factory closure `(UUID) -> BikeDetailModel`, a `() -> Date` closure and a `Calendar`; a launch model that stores a `() async throws -> AppModels` closure; and a main-actor target standing in for the app target, whose `App` keeps the launch model in `@State` and passes it a function that awaits an `@concurrent` adapter open function and builds the models. It builds with no warnings and no concurrency escapes. A view keeping a model in `@State` that it builds from such a factory builds too.
- **Size.** One developer and a small app: a handful of screens and two driven adapters. A container or library would be paid for in every feature.
- **Reference project.** investment-simulator-2026's [ADR-0001](https://github.com/cebartling/investment-simulator-2026/blob/main/docs/adr/0001-hexagonal-architecture.md) makes the app target the composition root, with no singletons and no service locators. Its [ADR-0004](https://github.com/cebartling/investment-simulator-2026/blob/main/docs/adr/0004-observable-presentation-models-and-dependency-injection.md) injects through initializers and allows `@Environment` only for the root model and UI-level concerns, never for adapters or Core services. Its [ADR-0012](https://github.com/cebartling/investment-simulator-2026/blob/main/docs/adr/0012-market-data-and-secrets.md) builds app-wide services once in the `App` and passes them down through initializers. In its code, `InvestmentSimulatorApp.init` builds every adapter, opens the database synchronously, and keeps `@State` an optional `LibraryWindowModel` beside a `databaseError` string that the window shows when opening failed. `LibraryWindowModel` builds its child models through a `makeExperimentModel` closure the `App` supplies. Models that need the time take a `clock: () -> Date` closure, and some default it to `Date.init`. It has no previews, and each test target writes its own fakes.

## Decision

We will inject every dependency through initializers, with the app target as the only place that builds and wires them, following the reference project, on the terms below.

### Mechanism

- **Initializers, everywhere.** A type takes the collaborators it uses through its initializer, and a function takes per-call values as parameters. That holds for Core (ADR-0003), the adapters, presentation models and views. There is no property injection, no container, no DI library and no dependency in the environment.
- **Ports are what is injected.** A model takes the Core ports it uses, as `any BikeRepository` and so on, and builds the Core use cases it calls from them. Use cases are `Sendable` structs that hold their ports (ADR-0005), so building one costs nothing, and the composition root deals only in ports. A model's initializer therefore names every port its intents reach, directly or through a use case.
- **No default arguments for dependencies.** A port, a factory closure, the clock or a calendar is never a defaulted parameter, so every caller, a test included, says what it passes, and a test can't reach the real clock or calendar by leaving an argument out.
- **Views are given models, or closures that build them, never ports.** A view that is given a model holds it as ADR-0008 says. A view that builds the model it keeps in `@State` is given a factory closure for it. A view never holds a port, an adapter or a use case, so it can't call one (ADR-0008).

### Child models

- **Factory closures, written by the composition root.** A model or view that builds another screen's model is given a closure that takes only the inputs that vary, such as `makeDetailModel: (Bike.ID) -> BikeDetailModel`. The composition root writes the closure, capturing the ports and the factories the child needs in turn. A parent holds only what it uses itself, and the whole graph is in one place.
- **One way, even when the parent could build the child.** A parent that already holds the ports its child needs is still given a factory, so there is one rule to follow and a child's new dependency changes only the composition root.
- **Tests pass a closure too.** A parent model's test builds the child over the same fakes in the closure it passes, or records the inputs it was called with.

### Composition root

- **The app target, and nothing else.** The `@main` `App` and the wiring code beside it in `BikeComponents/` are the only code that names an adapter type, opens the store, builds the Strava adapter, and passes the real clock (`{ Date.now }`) and calendar (`Calendar.autoupdatingCurrent`). The wiring is plain functions, one per model it builds, that capture the opened ports. It is not a type in `BikeComponentsUI` and holds no logic beyond wiring.
- **What the wiring names is `public`.** The app target is outside the package, so under ADR-0004's access rule everything it names is `public`: each model's initializer, `LaunchModel`, `AppModels` and its initializer (an implicit memberwise initializer is `internal`), the root view, the adapters' opening functions and initializers, and the ports and Core types those signatures name. Use cases stay `package`, because only models build them.
- **Each adapter is built once.** The one persistence actor (ADR-0007) is passed as every repository port, and the one Strava adapter as every Strava port. No model builds or opens an adapter.
- **The composition root has no unit tests.** Anything with a decision in it, such as what to show when the store fails to open, lives in a model that has them. A wiring mistake that still compiles shows up only when the app runs, which with one adapter per port is a narrow risk.

### Launch

- **`App.init` opens nothing.** It builds one model, `LaunchModel` in `BikeComponentsUI`, and keeps it in `@State`. The `App` holds no other state.
- **The launch model starts the app.** Its initializer takes one closure, `start: () async throws -> AppModels`, which the composition root supplies. The closure opens the store through ADR-0007's `@concurrent` function, builds the adapters, and returns `AppModels`: a value type in `BikeComponentsUI` holding the app-wide models (ADR-0008, ADR-0009) and the root screen's model. The launch model's state is opening, ready (holding the `AppModels`) or failed (holding the error). The root view, in `BikeComponentsUI`, calls its `launch()` intent from `.task`, shows that the app is opening, then either the app or the error. `launch()` runs `start` once, and later calls do nothing.
- **Every app-wide model is built by `start`.** Nothing is usable before the store opens, so all of them, including any that need no repository, are built in one place after it opens. They are kept on the `App` through the launch model's ready state, which is how ADR-0008's and ADR-0009's "kept on the `App`" is met.
- **Failure is final.** A failed launch shows the error until the app is relaunched. There is no retry, and no fallback store (ADR-0007). How the error is worded is decided with the error model (#18). ADR-0007 already requires it to name the path and the cause.
- **The launch model is tested like any model,** with a `start` closure that throws, or that returns models built over fakes.

### Clock, calendar and time zone

- **The current date is a `() -> Date` closure.** A model that needs the current date takes `now: () -> Date` and calls it each time an intent needs the date, so time moves on in a long-lived model. It passes the result to Core as a `Date` (ADR-0003). The composition root passes `{ Date.now }`. Tests and previews pass a fixed date.
- **A calendar is a `Calendar` value.** A model that needs a calendar or a time zone takes a `Calendar` and uses its `timeZone`, and passes them to Core as parameters. The composition root passes `Calendar.autoupdatingCurrent`, which follows the user's settings when they change. Tests pass a fixed calendar with a fixed time zone, so they don't depend on the device.
- **Models never read them themselves.** No `Date.now`, `Date()`, `Calendar.current`, `TimeZone.current` or `Locale.current` in Core or in `Sources/BikeComponentsUI/Presentation/`. Views format through the environment's values (ADR-0008).

### Fakes

- **Tests and previews use the shipping initializers.** A fake reaches a model the way the real adapter does: as an argument. There are no test-only or preview-only initializers, no defaulted dependencies, and no checks in shipping code for whether it runs in a test or a preview.
- **One in-memory fake per port, written when a test first needs it,** under ADR-0005's rules (an actor, or a final class guarding its state with `Mutex`), and shared by every test target that needs that port rather than written again in each. Where shared fakes live is decided in #16. Writing them is outside this ADR.
- **Previews, if any, build models with fakes.** Whether views have previews is decided in #16 and #19. If they do, a preview builds its model with the same in-memory fakes and a fixed date and calendar, and never touches the real store, Strava or the Keychain. Fakes in a test target can't be reached from `BikeComponentsUI`, so #16 decides where preview fakes live. A module for them would be a new kind of module, which ADR-0004 says needs an ADR.

### Singletons and shared instances

- **No singletons of our own, in any module.** No `static let shared`, no global or `static` that holds a dependency, no service locator and no type that resolves dependencies by type. ADR-0003 already rules them out for Core. ADR-0005's `let` constants of `Sendable` types, such as a file name, are values, not dependencies, and stay allowed.
- **System shared instances stay at the edges.** `URLSession.shared`, `FileManager.default`, `UserDefaults.standard`, `NotificationCenter.default` and `UIApplication.shared` are used only in adapters and the composition root. Core can't use them (ADR-0003). Models and views don't. A view uses the environment's action where there is one, such as `openURL` instead of `UIApplication.shared.open`. An adapter that uses a shared instance its tests need to replace takes it through its initializer, as the reference project's `URLSessionTransport(session:)` does.

### Environment

- **Nothing of ours goes in the environment.** Ports, adapters, use cases, models, the clock and the calendar are never environment values. `@Environment` carries only the values the system frameworks provide (ADR-0008). We define no custom `EnvironmentValues` entries. A later one for a view-only concern that no model reads, such as a style, needs no ADR. One that carries a dependency does.

### Options considered

Mechanism:

- **Initializer injection (chosen).** The compiler checks that every dependency is supplied, a type's initializer shows what it uses, and fakes go in the same way as real adapters. The reference project's choice. It costs passing values down through every layer that builds something.
- **SwiftUI `@Environment` for ports or models.** Idiomatic for deep view trees. Rejected: a missing value fails at run time, not at compile time, views would hold ports, and ADR-0008 already keeps models out of it.
- **A container or service locator,** hand-written or from a library such as Swinject or Factory. Rejected: dependencies are resolved at run time and hidden from initializers, ADR-0003 forbids a service locator for Core, and a library would need an ADR under ADR-0006 for a job initializers already do.
- **Point-Free's swift-dependencies,** with `@Dependency` properties and struct-of-closures clients. Strong test overrides. Rejected: a macro package ADR-0006 would have to admit, dependencies that are ambient rather than passed, and clients that would replace the protocol ports ADR-0003 chose.
- **Struct-of-closures clients without a library.** Rejected: ADR-0003 chose protocols for ports. Closures are used only where one function is the whole dependency: the clock and the factories.
- **One dependencies value holding every port, passed to every model.** Adding a dependency touches nothing in between. Rejected: every model could reach every port, its initializer no longer says what it uses, and its tests must supply fakes for ports it never calls.

Child models:

- **Factory closures from the composition root (chosen).** The reference project's `makeExperimentModel`. A parent holds only what it uses. It costs a closure parameter per child, and nested wiring in the composition root.
- **The parent builds the child from ports it is given.** No closures. Rejected: a parent's initializer would collect the ports of every screen below it.
- **One factory type in `BikeComponentsUI` with a method per model.** Rejected: whoever holds it can build any model, which is the dependencies value again.

Current date:

- **A `() -> Date` closure (chosen).** One function is the whole dependency, and a fixed date in tests is one closure.
- **The view passes the date into each intent.** Rejected: the view would read the clock, and a model's computed properties couldn't use the date.
- **A clock protocol.** ADR-0003 rules out a clock port for Core. In a model it would be a type and a fake doing what a closure does.
- **Swift's `Clock` protocol.** It measures durations for sleeps and deadlines, not the calendar date a service interval needs.

What the `App` holds while the store opens:

- **A launch model given a `start` closure (chosen).** Opening and its failure are model state, unit tested, and the app target stays wiring.
- **Open the store in `App.init`,** as the reference project does. Rejected: ADR-0007's open is `async`, and opening synchronously would block the main thread at launch.
- **An enum in the `App`'s `@State`, set from a `.task` in its scene.** No extra model. Rejected: the branching and the error handling would sit in the app target, which ADR-0004 keeps to wiring, where they can't be unit tested.

### Where this diverges from the reference project

- **Store opening.** The reference project opens its database synchronously in `App.init` and keeps an optional model beside an error string. Here `App.init` builds only the launch model, and opening is `async` and part of that model's state.
- **Defaults.** Some of the reference project's models default their clock to `Date.init`. Here no dependency has a default.
- **Calendar.** The reference project's presentation types default to `.current` time zones and locales. Here a model takes a `Calendar` and never reads the current one.
- **Environment.** The reference ADR allows the root model in the environment. Here nothing of ours goes there, which matches the reference project's code.
- **Fakes.** Each of the reference project's test targets writes its own fakes. Here each port has one fake, shared by the test targets that need it.
- **Kept:** initializer injection, the app target as the only composition root, adapters built once and passed down, factory closures for child models, and no singletons or service locators.

## Consequences

- **Easier:** swapping fakes into tests and previews, which is passing different arguments; seeing what a model uses from its initializer; catching a missing dependency at compile time; knowing where every adapter is built.
- **Harder:** every layer that builds something passes its dependencies on, and the composition root grows with every screen. Adding a dependency to a model changes its initializer, its factory in the composition root and its tests. Because the app target does the wiring, every model's initializer and every port is `public`, a wider `public` surface than the UI alone would need. Wiring mistakes that compile surface only when the app runs.
- **ADR-0008 and ADR-0009.** Their open points are settled: owners get child models through factory closures, models get the date and calendar through their initializers, nothing else goes in the environment, and the `App` holds the launch model until the store opens. Their app-wide models are kept on the `App` through the launch model's ready state. Their rules are otherwise unchanged.
- **Testing (#16)** decides where the shared fakes live, whether there are previews and where their fakes live, and whether UI tests launch the app with fake adapters. If they do, the composition root is where they are swapped in, the way ADR-0009 already lets a launch argument trigger schema initialization.
- **Navigation (#17)** decides which models own selection and which screens they present, and so which factories exist. If iPad runs several scenes, they share the `App`'s one launch model, so the store opens once.
- **Networking and error model (#18)** decides how a failed launch's error is shown.
- **Strava (#3)** designs the Strava adapter's initializer, which `start` calls, and the connection port that an app-wide model takes.
- **Agents.** `CLAUDE.md` records the injection rules.
