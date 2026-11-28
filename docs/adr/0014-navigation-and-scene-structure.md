# 14. Navigation and scene structure

- Status: Accepted
- Date: 2026-11-27

## Context

Navigation structure is hard to change once screens exist. It decides how the app reaches a bike, a component or a ride, which models own selection and navigation state, how iPhone and iPad layouts relate, and which URLs the app answers.

Earlier ADRs already settle part of it:

- **ADR-0002.** One universal SwiftUI app for iPhone and iPad. iPadOS windows can be freely resized (since iPadOS 26), so iPad layouts must handle any window size, likely with `NavigationSplitView`. macOS, and with it macOS window and scene layout (`Window`, `Settings`, `MenuBarExtra`), is out of scope. UIKit only where SwiftUI has no equivalent. Strava sign-in uses `ASWebAuthenticationSession` through SwiftUI's `webAuthenticationSession` environment value, or the `strava://` scheme when the Strava app is installed (#3).
- **ADR-0008.** Screen logic lives in `@Observable` models in `BikeComponentsUI/Presentation/`, whose files import Foundation, Observation and Core only, never SwiftUI. Views keep only ephemeral `@State`. Selection, navigation state and which sheet or destination is presented were left to this ADR, as were state restoration and whether iPad runs several scenes. The owner of two models on display refreshes one after the other's writes. A view that keeps a model built from an input gets `.id(input)`, or its parent model owns the model and passes it in.
- **ADR-0009.** Writes from another device arrive through the remote-change port. Reconciliation deletes duplicate bikes and rides, keeping the one with the smallest `UUID`, so a record on screen can disappear.
- **ADR-0010.** Child models come from factory closures written by the composition root. `AppModels` holds the app-wide models and a factory for the root screen's model, which the view shown in the launch model's ready state builds and owns. How many scenes there are was left to this ADR.
- **ADR-0012.** No XCUITest target. UI tests were to be revisited with this ADR.
- **ADR-0013.** App target build settings, including generated `Info.plist` keys, live in `Config/BikeComponents.xcconfig`, edited as text. Other `Info.plist` values go in `BikeComponents/Info.plist`, which Xcode merges with the generated one. Adding that file is a project change.

Forces at play:

- **What the app shows.** Bikes come only from Strava (#4). A bike has components, installations, service records and the rides recorded on it. Rides with no `gear_id` are shown as unassigned, not dropped (#3). Connecting Strava, importing bikes and editing records are tasks the user starts and finishes.
- **Window sizes.** An iPhone is always compact. An iPad window can be anything from a narrow strip to full screen, and can change while a screen is shown, so one layout has to work at every width.
- **SwiftUI's navigation types.** `NavigationSplitView` shows columns side by side in a regular width and collapses into a single stack in a compact one, on its own. `NavigationStack(path:)` binds to any `Hashable` collection, so a typed array of an enum can hold the path, where `NavigationPath` erases the element types and is a SwiftUI type that `Presentation/` files can't name (ADR-0008).
- **Several windows.** iPadOS can show more than one window of an app when the app supports multiple scenes. Each window would need its own selection and path. A write in one window would leave another stale, and no model owns both (ADR-0008 keeps no change-notification port).
- **URLs.** With `ASWebAuthenticationSession`, the Strava callback goes back to the session, not to the app. When the Strava app handles sign-in, Strava opens the app's redirect URL, which arrives through `.onOpenURL`, possibly on a cold launch, before the store has opened. No widget, notification or Spotlight entry needs a link into a screen yet.
- **Size.** One developer and a small app, used by the author and TestFlight testers (ADR-0002).
- **Reference project.** investment-simulator-2026 is macOS-only. Its [ADR-0010](https://github.com/cebartling/investment-simulator-2026/blob/main/docs/adr/0010-native-swiftui-window-management.md) and [ADR-0011](https://github.com/cebartling/investment-simulator-2026/blob/main/docs/adr/0011-document-window-management.md) (both superseded) gave each document window its own composition root, because app-level `@State` is shared by every window `WindowGroup` opens and windows would otherwise share their selection. [ADR-0021](https://github.com/cebartling/investment-simulator-2026/blob/main/docs/adr/0021-sqlite-library-replaces-document-persistence.md) replaced them with one library window whose sidebar lists every experiment, where selecting one shows its detail. Its [ADR-0019](https://github.com/cebartling/investment-simulator-2026/blob/main/docs/adr/0019-research-window.md) keeps selection in a model and restores open tickers from `UserDefaults`. Its window ADR made a rule of checking native SwiftUI behavior against the built app before planning custom code. Its window decisions are macOS ones: iPhone navigation needs its own answer.

## Decision

We will build the app as one window holding one `NavigationSplitView`, with navigation state in the root screen's model, on the terms below.

### Scenes

- **One `WindowGroup` scene, one window.** The `App`'s body has one `WindowGroup`, and the app doesn't support multiple scenes: `UIApplicationSupportsMultipleScenes` is `false` in the `UIApplicationSceneManifest` dictionary of `BikeComponents/Info.plist`. Xcode 27.2's build settings have no generated-`Info.plist` key for it (its build specification defines `INFOPLIST_KEY_UIApplicationSceneManifest_Generation` but nothing for multiple scenes), so ADR-0013's `.xcconfig` can't set it. Adding that `Info.plist` file is ADR-0013's project change, made by the user. iPadOS still shows the one window at any size the user chooses.
- **No other scene types.** No `DocumentGroup`. `Window`, `Settings` and `MenuBarExtra` are macOS scenes, and macOS isn't targeted (ADR-0002). No `ImmersiveSpace` or other platform's scenes.
- **One root screen model.** With one scene, the view shown in the launch model's ready state builds one root screen model from `AppModels`' factory and keeps it in `@State` (ADR-0010). Navigation state lives there, not in an app-wide model. App-wide models stay as ADR-0008 and ADR-0009 set them.

### Navigation model

- **The root screen is a two-column `NavigationSplitView`.** The sidebar lists the bikes and the app's other top-level entries, such as unassigned rides. The detail column shows the selected entry. In a compact width, on iPhone and in a narrow iPad window, the split view collapses into one stack on its own: the sidebar is the first screen, and selecting an entry pushes its detail. There is one layout, not one per device or size class. What each entry shows is screen design, outside this ADR.
- **Selection is an enum in the root screen's model.** The model holds `selection`, an optional `Hashable` enum in `Presentation/` with one case per kind of sidebar entry (`.bike(UUID)`, `.unassignedRides`, …), bound to the sidebar's `List(selection:)`. Cases carry domain `UUID`s, never domain values, so the destination loads its own data from the store (ADR-0008).
- **Drill-downs are a typed path in the detail column.** The detail column holds a `NavigationStack(path:)` bound to the root screen's model's `path`, an array of a `Hashable` enum in `Presentation/` (`.component(UUID)`, `.ride(UUID)`, `.serviceRecord(UUID)`, …), with one `navigationDestination(for:)` at the stack's root that maps each case to its screen. Views push with `NavigationLink(value:)`, which appends to the bound path. Only the root screen's model's own intents change `path`, such as clearing it (below), where tests check them. A pushed screen leaves with `dismiss()` on its intent's outcome, such as returning to the bike after deleting the component it shows (`if await model.delete() { dismiss() }`, ADR-0008), which pops the bound path. No `NavigationPath`, no view-destination `NavigationLink(destination:)`, and no router or coordinator object.
- **Changing the selection clears the path.** The model empties `path` when `selection` changes, so the detail column always starts at the selected entry's screen.
- **The root screen's model owns the detail column's model.** It holds the detail as an optional enum with one case per kind of entry, each holding that entry's model, and rebuilds it from a factory closure whenever `selection` changes, without calling a port. The detail view holds the model as a `let` (ADR-0008's "the parent model owns the model and passes it in") and is keyed on the selection (`.id(selection)`), so its `.task` runs again and loads each new model. The sidebar and the detail are on screen together, so the root screen's model is the owner ADR-0008 means for the two, and refreshes the sidebar after the detail's writes.
- **Pushed screens build their own models.** A screen pushed onto the path keeps its model in `@State`, built from a factory closure (ADR-0010) that the root screen's model holds and the destination mapping passes on. The root screen's model presents those screens, so their factories are what it uses, in ADR-0010's sense: it holds one per case of its path enum and the detail column, and nothing else, so it isn't the factory type ADR-0010 rejects, which can build any model. A sheet's factory is held by the model that presents the sheet. Each element of the path gets its own view, so no `.id` is needed. A pushed screen replaces the one below it in its column, so the two are never on display together.
- **A record that disappears leaves navigation cleanly.** When the root screen's model reloads the sidebar, from its own writes, an import's progress or a remote change (ADR-0008, ADR-0009), and the selected entry's record is gone, it clears the selection, and with it the path. A pushed screen whose record is gone shows that it no longer exists, which is not an error.

### Sheets and other presentations

- **Which sheet is presented is model state.** The presenting screen's model holds an optional `Identifiable` enum of its sheets, bound with `.sheet(item:)`. Intents set it, so a rule (such as prompting to reconnect after `authorizationRejected`, ADR-0011) can present one and a test can check it, and the presenter's own intents may clear it. The sheet closes itself on its own intent's outcome (`if await model.save() { dismiss() }`, ADR-0008), which clears the presenter's state through the binding. The sheet and the screen under it are on display together, but no model owns both, so the presenting view reloads its model from `.sheet(item:onDismiss:)`: ADR-0008's view that chains two intents. The same holds for full-screen covers and popovers. Confirmation dialogs stay ephemeral view `@State`, and alerts for failed actions follow ADR-0011.
- **Sheets are for tasks the user starts and finishes,** such as connecting Strava, picking bikes to import (#4) or editing a record. A sheet's view builds its model from a factory in `@State`, so each presentation starts fresh. A sheet that needs more than one step has its own `NavigationStack`, whose path is in its own model.

### URLs

- **The only URL the app handles is the Strava redirect,** when the Strava app handles sign-in (#3). With `ASWebAuthenticationSession`, the callback returns to the session, so no URL reaches the app. #3 chooses the redirect's form and registers it, in `BikeComponents/Info.plist` for a URL scheme (ADR-0013), or as a capability, which is a project change made by the user, for a universal link.
- **One `.onOpenURL`, on the launch model's root view.** That view is on screen from the first frame, so a URL arriving on a cold launch has a handler. It hands the URL to the launch model, which keeps the latest one until it is ready and then passes it on; a URL that arrives after a failed launch is dropped. A function in `Presentation/` matches a URL to the app-wide model that handles it (#3 designs that model and what it is handed), and an unknown URL is ignored. Matching, keeping and passing on are tested in the models.
- **No navigation deep links yet.** No URL selects an entry or pushes a screen. Routes are values holding domain `UUID`s, so adding a link later is a function that parses a URL into a selection and a path.

### State restoration

- **None yet.** No `@SceneStorage`, `NSUserActivity` or stored navigation state. When the system ends the app in the background, it opens again at the root screen with nothing selected. Restoring later adds `Codable` to the route enums, stores them, and drops restored routes whose records are gone, without changing this structure.

### Native behavior first

- **SwiftUI's own navigation, nothing wrapped.** No `UINavigationController` or `UISplitViewController` wrappers, and no custom collapse, column or window code. Column widths, collapsing and the compact column come from `NavigationSplitView` itself.
- **A new navigation or window requirement starts with an experiment** against the built app on the simulator, on iPhone and on an iPad window resized across widths, before custom code is planned, as the reference project does.

### Testing

- **Navigation is tested in the models,** in `BikeComponentsUITests` (ADR-0012): that changing the selection clears the path and builds the right detail model, that the root screen's intents change the path, that intents present sheets, that a pushed screen's or a sheet's intent reports the outcome its view dismisses on, that a gone record clears the selection, and how URLs are matched and kept. Views, and with them the bindings to `List(selection:)`, `NavigationStack(path:)` and `.sheet(item:)`, have no unit tests.
- **Still no UI tests.** ADR-0012's revisit is answered: the navigation decisions are model state that unit tests reach, and what's left untested is the views binding them. Revisit with #19, or when a navigation bug gets past the model tests.

### Options considered

Navigation structure:

- **One `NavigationSplitView` with a typed path in the detail column (chosen).** One layout for every width, collapsing on its own. All navigation state is plain values in a model.
- **`TabView` with `.sidebarAdaptable`,** tabs such as Bikes, Rides and Settings on iPhone, a sidebar on iPad, each tab with its own stack or split view. Rejected: one path per tab is more state to own and test, and the app has one main thing to browse, its bikes. Unassigned rides and Strava fit as sidebar entries or sheets.
- **`NavigationStack` everywhere.** Simplest, but a wide iPad window would show one column at a time. Rejected.
- **A three-column split view** (sections, a list, a detail). Rejected: no list needs a column of its own yet, and a third column narrows the detail in mid-width windows.

Navigation state:

- **A typed array in the root screen's model (chosen).** Plain `Hashable` values a `Presentation/` file can name, checked in tests.
- **`NavigationPath`.** Mixes destination types, but erases them, so tests can't read it, and it is a SwiftUI type a model can't name (ADR-0008). Rejected.
- **A router or coordinator object** that pushes screens and builds them. Rejected: a second owner of state beside the models, and its pushes would still have to end in a binding.
- **Plain `NavigationLink(destination:)`.** No state to own. Rejected: which screen is pushed then lives in views, where no unit test reaches it, and nothing can clear the path when the selection changes.

Sheets:

- **Model state (chosen).** One rule, testable, and a rule or an outcome can present or close one.
- **View `@State`, unless a rule presents it.** Less code for sheets the user opens, but two rules to choose between for every sheet. Rejected.

Scenes:

- **One window (chosen).** Every screen on display has one owner, so ADR-0008's refresh rule keeps them consistent.
- **Multiple windows on iPad,** each with its own root screen model, sharing the app-wide models. Rejected for now: a write in one window would leave another stale, which needs the change-notification port ADR-0008 keeps for later.

URLs and restoration:

- **The Strava redirect only, and no restoration (chosen).** Nothing else needs either yet, and routes as values keep both additive.
- **Navigation deep links now.** Rejected: no widget, notification or Spotlight entry needs one.
- **Restoration with `@SceneStorage`.** Rejected for now: it costs encoding the routes and dropping restored routes whose records are gone, for a small saving on reopening.

### Where this diverges from the reference project

- **Platform.** The reference project's window decisions are macOS ones. Here one layout serves iPhone and every iPad window width.
- **Windows.** The reference project once gave each document window its own composition root. Here there is one window, so one root screen model, and the composition root stays app-wide (ADR-0010).
- **Restoration.** The reference project restores open Research tickers from `UserDefaults`. Here nothing is restored yet.
- **Kept:** one window whose sidebar lists the main records with the selection showing a detail (its ADR-0021), selection held in a model (its ADR-0019), and checking native SwiftUI behavior before planning custom code (its ADR-0010).

## Consequences

- **Easier:** one layout for every device and window width; navigation that unit tests can drive, from selecting an entry to presenting a sheet; adding a screen, which is a case in a route enum, a destination mapping and a factory; adding deep links or restoration later, because routes are already values.
- **Harder:** every sheet needs a case in its presenter's model, and every pushed screen a case in the path enum. The app opens at the root after the system ends it in the background. iPad users can't open a second window.
- **ADR-0008 and ADR-0010.** Their open points on navigation are settled: the root screen's model owns selection, the detail column's model and its path; presenting models own their sheets; there is one scene, so one root screen model; and nothing is restored. ADR-0010's launch model also keeps an incoming URL until it is ready. Their rules are otherwise unchanged.
- **ADR-0012.** Its UI-test revisit is answered: still none, revisited with #19.
- **Strava (#3)** chooses the redirect's form, registers it, and designs the app-wide model that handles it and what that model is handed.
- **Skeleton.** It sets `UIApplicationSupportsMultipleScenes` to `false` in `BikeComponents/Info.plist`, once the user has added that file (ADR-0013), and checks in the built app's `Info.plist` that the key survives the merge with the generated scene manifest.
- **Checks with the first screens,** on the simulator on iPhone and on a resized iPad window: that a cold launch from the Strava redirect reaches the launch view's `.onOpenURL`; that a screen covered by a pushed one runs its `.task` again when it reappears, so it reloads after the pushed screen's writes; that selecting another entry in a regular width loads the new entry's detail; and that popping back to the sidebar in a compact width leaves the selection consistent with the path. If one fails, adjust the design before building on it, and record the change in a new ADR if it changes a rule here.
- **Follow-up:** if a pushed screen's write must change the sidebar, the first such case decides how the root screen's model learns of it.
- **Revisit:** multiple windows, with a change-notification port; restoration, if reopening at the root gets annoying; deep links, when a widget, notification or Spotlight entry needs one.
- **Agents.** `CLAUDE.md` records the navigation rules.
