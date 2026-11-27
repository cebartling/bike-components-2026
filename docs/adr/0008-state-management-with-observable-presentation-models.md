# 8. State management with `@Observable` presentation models

- Status: Accepted
- Date: 2026-11-27

## Context

ADR-0003 puts the domain rules (wear, service intervals, Strava import reconciliation) in Core, and makes the SwiftUI layer a driving adapter that calls Core's use cases directly, with no protocols in front of them. ADR-0004 puts views and presentation code in `BikeComponentsUI`, which depends on Core only, and left this ADR to pick the presentation pattern and to say whether presentation code needs a module of its own. ADR-0005 makes `BikeComponentsUI` main-actor by default, bans Combine, and starts unstructured tasks in the UI layer, preferably with `.task`. ADR-0007 keeps SwiftData inside the persistence adapter, so views can't use `@Query` and `@Model` objects never reach the UI.

What is still open: how views get state, where the logic that isn't a domain rule lives, how it is tested without SwiftUI, and who owns state that outlives a screen.

Forces at play:

- **Testability.** The project is test-driven. Logic inside a view's `body` or its action closures can only be tested by rendering the view or through UI tests.
- **Observation is available everywhere.** ADR-0002's minimum (iOS 27.2) is far above Observation's iOS 17, so `@Observable`, `@Bindable` and `@Environment` with observable types need no `#available` checks. Observation isn't part of SwiftUI, so a file can use `@Observable` without importing SwiftUI.
- **Core can't be observable.** Core imports Foundation only (ADR-0003), so domain types can't be `@Observable`. Anything a view observes lives outside Core.
- **Imports are per file.** Checked with Xcode 27.2, building for the iOS Simulator: in a main-actor package target with ADR-0005's settings, a file that imports only Foundation, Observation and Core fails with "cannot find 'Color' in scope" when it names `Color`, even though another file in the same target imports SwiftUI. `MemberImportVisibility` (ADR-0005) extends that to members that SwiftUI adds to other modules' types. The rule covers names, not types: such a file still compiles when it reaches a SwiftUI type through another declaration in the module, such as a typealias or a property whose type is inferred, and it can name the module's views. A separate module would stop that, but it wouldn't stop a system framework import: SwiftPM doesn't stop a target importing one.
- **Long-lived state.** Some state outlives any one screen: whether the app is connected to Strava, and an import in progress, which can be a long first backfill (#3). The import must keep running when the user leaves the screen that started it, and stay cancellable (ADR-0005).
- **iPad.** A list and a detail can be on screen together, so a change made in one can make the other stale.
- **Size.** One developer and a small app. A framework or an extra layer is paid for again in every feature.
- **Reference project.** investment-simulator-2026's [ADR-0004](https://github.com/cebartling/investment-simulator-2026/blob/main/docs/adr/0004-observable-presentation-models-and-dependency-injection.md) drives each screen with an `@Observable` presentation model that holds UI state, exposes intent methods that call Core and maps results and errors to display state. The models live in their own target, which imports only Foundation, Observation and Core. That target boundary didn't stop SwiftUI imports, so a SwiftLint custom rule was added later. Views are thin and keep only ephemeral `@State`. Models reach views through initializers, and `@Environment` is allowed sparingly for the root model. In its code, no model is ever put in the environment: views read only SwiftUI's own values from it, such as `timeZone` and `accessibilityReduceMotion`. App-wide models are built in the `App`'s initializer and kept in `@State`. Child models are made by their parent, through factory closures the composition root supplies. Its tests replace use cases with fakes.
- **Dependent decisions.** Dependency injection (#15) decides how the code that builds a model gets the ports it needs. Navigation (#17) is out of scope here.

## Decision

We will drive screens with `@Observable` presentation models in `BikeComponentsUI`, following the reference project, on the terms below.

### Where logic lives

- **Domain logic lives in Core.** Wear, service intervals, import reconciliation and every other rule about bikes, components, rides and service records are Core's, in its domain types and use cases (ADR-0003). A rule that would give a different answer on another screen, or without a UI, belongs in Core.
- **Screen logic lives in presentation models.** A presentation model holds a screen's state, exposes intent methods such as `load()`, `save()` or `startImport()`, calls Core's use cases and ports, and maps their results and errors to display state: what is shown, what is loading, which actions are enabled, which validation message appears. How errors become display state is decided with the error model (#18). Values derived from that state are computed properties.
- **Views are thin.** A view reads its model's state, binds to it with `@Bindable`, and calls its intent methods. It never calls a Core use case or port itself. Its own `@State` holds only ephemeral view state that no rule depends on, such as focus, scroll position, whether a sheet or confirmation dialog is shown, or whether a section is expanded. Selection and navigation state are decided in #17.
- **A screen that calls Core, or holds state that a rule depends on, has a model.** A view with only ephemeral state, such as a static about screen or a row that shows what it is given, needs none. A model may own the models of the parts it presents, for example a bike's model owning the model of its components section.
- **Models expose values, not formatted text.** Numbers, dates and measurements reach the view as values, and the view formats them with `FormatStyle`, which uses the environment's locale. A model that needs the current date, a calendar or a time zone gets it passed in, as Core does (ADR-0003), so its tests don't depend on the device. How it is passed is decided in #15. User-facing strings and string catalogs are decided in #22.
- **SwiftUI-only APIs stay in the view.** Where a step needs an API that only SwiftUI provides, the view calls it and hands the result to the model. For example, the view runs `webAuthenticationSession` for Strava connect and passes the resulting callback URL to its model, which passes it to Core's connection port (#3, ADR-0003).

### What a model is

- **An `@Observable` final class,** named for its screen and ending in `Model` (for example `BikeListModel`). It is main-actor isolated through `BikeComponentsUI`'s default isolation (ADR-0005), which also makes it implicitly `Sendable`, so it declares no conformance and is never marked `nonisolated`. What it passes to Core are Core's own `Sendable` types.
- **Not `ObservableObject`.** No `@Published`, `@StateObject`, `@ObservedObject` or `@EnvironmentObject`, which depend on Combine (ADR-0005).
- **In its own file, named after it (`BikeListModel.swift`), in `Sources/BikeComponentsUI/Presentation/`.** Every file in that folder, which holds the models, their extensions and the display-state types they expose, grouped by feature inside it, imports Foundation, Observation and `BikeComponentsCore` only. Never SwiftUI or UIKit. Views live elsewhere in `BikeComponentsUI`, so the compiler stops a model naming SwiftUI's declarations while views in the same module use them freely. It doesn't stop a model reaching a SwiftUI type through another declaration in the module, or naming a view, so code review checks that models don't use view-side declarations. Code review also checks the imports until the automated import check that ADR-0003 leaves as a follow-up covers this rule too.
- **Its initializer does no work.** It stores what it is given and sets initial state. It calls no port and starts no task. Loading happens in an `async` method, such as `load()`, that the view calls from `.task`. SwiftUI may run a view's initializer many times, and tests then control when loading happens.

### Tasks

- **Intent methods that call Core are `async`.** The view calls them from `.task`, `.task(id:)` or `.refreshable`, which cancel their task when the view goes away, or from a `Task` it starts in a button action. A model starts no unstructured task of its own, except an app-wide model running work that must outlive a screen (below), which keeps the task's handle, cancels it when asked and says why in a comment (ADR-0005).
- **The model decides what follows an intent.** A `Task` started in a button action isn't cancelled when the view goes away, so a save can finish after the screen is dismissed. An intent method reports its outcome in the model's state or in its return value, and the view's closure only acts on it, for example `if await model.save() { dismiss() }`. The condition is the model's.

### State ownership

- **The store is the source of truth for domain data.** Models hold copies of Core values loaded through Core. A model loads what its screen shows when the screen appears, and reloads, or updates its copy from the use case's result, after its own writes. There is no app-wide in-memory copy of the domain data.
- **The owner of two models keeps them consistent.** When a write on one screen changes what another screen on display shows, such as a detail beside its list on iPad, the model that owns both refreshes the other, for example by reloading the list model when the detail model's save returns. Where a view owns both, it only chains the two intent calls: it awaits the save, then the reload. There is no change-notification port until a screen needs one (ADR-0003 adds a port only when Core needs it).
- **App-wide state lives in app-wide models.** State that outlives any one screen, starting with the Strava connection state and import progress, lives in models built once by the composition root and kept in `@State` on the `App` for the app's lifetime. ADR-0007 opens the store asynchronously, and opening it can fail, so app-wide models that need a repository are built after the store opens. What the `App` holds until then, and how it shows a failure, is decided in #15. The import runs in such a model, so it keeps going when the user leaves the screen that started it, and the model can cancel it. A cancelled import isn't shown as an error (ADR-0005). The connection state comes from Core's connection port, which #3 names and designs.
- **Screens reload after an import saves.** No model owns both the import and a screen, so the owner rule above doesn't cover it. A screen that shows imported data is given the app-wide import model and reloads when that model reports that the import saved more, for example with `.task(id:)` on a counter the import model exposes. What the import reports, and how often, is designed with #3.
- **Every model has one owner that keeps it alive:** the `App` for an app-wide model, and the view (in `@State`) or model that presents the screen for a screen's model. A view that is given a model holds it as a `let`, or as a `@Bindable var` when it needs bindings, never in `@State`.
- **A model built from an input is rebuilt when the input changes.** SwiftUI keeps the first model a view puts in `@State` for as long as the view keeps its identity, so a detail view that builds its model from a bike's ID would keep showing the first bike when the iPad list's selection changes. Such a view gets a new identity when its input changes (`.id(bikeID)`), or its parent model owns the model and passes it in.
- **Models reach views through view initializers.** Our models are never put in the environment. `@Environment` carries SwiftUI's own values, such as `dismiss`, `openURL`, the locale and accessibility settings. How an owner gets the ports to build a model, and whether anything else goes in the environment, is decided in #15.

### Testing

- **Models are tested without SwiftUI.** A model's tests, in `BikeComponentsUITests`, build it with Core's real use cases over in-memory fakes of Core's ports, call its intent methods and check its state. Use cases have no protocols (ADR-0003), so the fakes go under the use case, at the ports, as in Core's own tests. The test target is main-actor by default (ADR-0005), like the models. The framework, and where shared fakes live, are decided in #16.
- **Views have no unit tests.** They hold no logic to test. Whether there are previews, UI tests or snapshot tests is decided in #16 and #19.

### Options considered

Approach:

- **`@Observable` presentation models (chosen).** Screen logic is unit tested with the same fakes as Core. Views stay thin. Every feature follows one pattern. It costs a type per screen and the wiring to build it.
- **"No view models":** app-wide `@Observable` objects in the environment, with views calling use cases and holding the screen's logic in `@State` and action closures. Least code, and close to Apple's samples. Rejected: that logic can only be tested through the view, and a missing environment object fails at run time, not at compile time.
- **`ObservableObject` view models with `@Published`.** The pre-Observation form of the same pattern. Rejected: it depends on Combine (ADR-0005), and a change to any published property invalidates every view that observes the object.
- **The Composable Architecture (TCA) or a similar unidirectional framework.** Strong testing of state changes, but it is a third-party package with macros that ADR-0006 would have to admit, its reducers and dependency system duplicate Core's use cases and ports, and its ceremony is paid in every feature. Rejected.
- **SwiftData in views (`@Query`, `@Model` objects as state).** Already ruled out by ADR-0003 and ADR-0007.

Where models live:

- **In `BikeComponentsUI`, in a `Presentation/` folder whose files don't import SwiftUI (chosen).** The compiler stops those files naming SwiftUI's declarations, as checked above, and there is no extra module. Code review catches a model reaching view-side declarations.
- **A `BikeComponentsPresentation` module of their own,** as in the reference project. A module boundary would also stop models reaching views and view-side declarations, but not a system framework import (the reference project needed a lint rule for that). Rejected: that extra protection is small next to the cost of a module, a test target and `package` access between views and models.

Keeping screens consistent:

- **Each model loads its own data, and the owner of two models refreshes them (chosen).** Simple, and it matches a store that is the only source of truth. Owners have to remember to refresh.
- **One app-wide model holding all the domain data in memory.** No stale screens, but a second copy of the store to keep in step with every write and import, and imported rides can number in the thousands. Rejected for now.
- **A change-notification port, with repositories publishing changes as an `AsyncSequence`.** Every screen stays fresh without coordination, but no screen needs it yet. Revisit if refreshing by hand gets awkward.

How models reach views:

- **View initializers (chosen).** Explicit, and checked by the compiler.
- **`@Environment` with the model's type.** Less passing in deep view trees, but a missing model fails at run time, and the reference project never needed it.

### Where this diverges from the reference project

- **Module.** The reference project keeps its models in their own target and enforces that target's imports with a lint rule. Here models share `BikeComponentsUI` with the views, and the import rule is per file.
- **Test fakes.** The reference ADR replaces use cases with fakes. Here use cases have no protocols (ADR-0003), so model tests use the real use cases over fakes of the ports.
- **`@Environment`.** The reference ADR allows it for the root model. Here models never go in the environment, which matches what the reference project's code does.
- **Initializers.** The reference project's `SettingsModel` reads the Keychain in its initializer. Here a model's initializer does no work, and loading is an `async` method called from `.task`.
- **Formatting.** The reference project's presentation target has formatter types that turn values into text. Here models expose values, and views format them with `FormatStyle`.

## Consequences

- **Easier:** testing screen behavior with fast tests and the same fakes as Core; keeping views small and readable; adding a feature, which always takes the same shape: a Core use case if there is a rule, a model, a view.
- **Harder:** every screen with state needs a model, and the code that builds it. Models hold copies of domain data, so keeping two visible screens consistent is explicit work for their owner, and a forgotten refresh shows stale data. The rule that presentation files don't import SwiftUI is checked only by code review until an automated check exists, and only code review stops a model using a view-side declaration.
- **Dependency injection (#15)** decides how the owner of a model gets the ports and use cases to build it (for example the reference project's factory closures), how the current date reaches models, the fakes used in previews, and what the `App` holds while the store opens or after it fails to open.
- **Testing (#16)** decides the framework for model tests, where the shared fakes of Core's ports live, and whether there are UI tests.
- **Navigation (#17)** decides selection and navigation state, state restoration, and whether iPad runs several scenes, and with it which models are per scene and which are app-wide.
- **Networking and error model (#18)** decides how errors, including cancellation, become a model's display state.
- **Strava (#3)** designs the connection port and the import's progress reporting that the app-wide models observe.
- **Localization (#22)** decides where user-facing strings live.
- **Follow-up:** the automated import check from ADR-0003 should also check that the files in `Sources/BikeComponentsUI/Presentation/` import only Foundation, Observation and `BikeComponentsCore`.
- **Revisit:** a change-notification port, if owners refreshing screens by hand gets awkward.
- **Agents.** `CLAUDE.md` records the pattern new features must follow.
