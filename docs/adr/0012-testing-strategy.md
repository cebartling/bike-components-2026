# 12. Testing strategy

- Status: Accepted
- Date: 2026-11-27

## Context

The project is test-driven: each change starts with a failing test. The skeleton (ADR-0004) can't create its first test target until the framework is chosen, and every later feature follows whatever this ADR sets.

Earlier ADRs already settle part of it:

- **ADR-0003.** Core is tested through in-memory fakes of its driven ports, with no UI, disk, network or real clock. Adapters are expected to be tested against an in-memory store (persistence) and fixture JSON through an injected transport (Strava). It left the framework and where shared fakes live to this ADR.
- **ADR-0004.** Every library module has a `<Module>Tests` target in the package. Tests run on an iOS Simulator through the package's generated `BikeComponentsKit` scheme, which picks up every `.testTarget` by itself. `swift test` on the Mac isn't a supported check. A new kind of module needs an ADR. If an Xcode UI test target is added, it must not take Xcode's default name, which is `BikeComponentsUITests`.
- **ADR-0005.** A test target uses its module's default isolation, so `BikeComponentsUITests` is main-actor. Fakes of ports are actors or final classes guarding their state with `Mutex`, and test targets may import Synchronization. It left to this ADR how `async` code is tested.
- **ADR-0006.** A test-only package, such as a snapshot-testing library, needs an ADR that admits it.
- **ADR-0007.** Adapter tests use an in-memory configuration, one container per test. Migration tests write a store to a temporary file. Adapter tests run with Core Data's concurrency assertions on (`com.apple.CoreData.ConcurrencyDebug` = 1), and the adapter's first tests check on the simulator that a port method called from the main actor runs off the main thread. How the setting reaches the generated scheme was left to this ADR.
- **ADR-0008.** Models are tested in `BikeComponentsUITests` with Core's real use cases over in-memory fakes of the ports. Views have no unit tests. Whether there are previews, UI tests or snapshot tests was left to this ADR and #19.
- **ADR-0009.** Reconciliation is tested in Core with fakes, the merge port method in the adapter against in-memory stores, and CloudKit isn't unit tested. Adapter tests pass `cloudKitDatabase: .none`.
- **ADR-0010.** One in-memory fake per port, written when a test first needs it, shared by the test targets that need it, and given to models through their shipping initializers. Tests pass a fixed date and calendar. The composition root has no unit tests. It left to this ADR where shared fakes live, whether there are previews and where their fakes live, and whether UI tests launch the app with fake adapters.
- **ADR-0011** (#18). The Strava adapter's tests use a fake `HTTPTransport` that records requests, an injected `sleep` and a fixed `now`, with scrubbed fixture JSON in `Tests/BikeComponentsStravaTests/Fixtures/`. Fakes of Core's ports throw each error case a model shows differently. It left the framework to this ADR.

Forces at play:

- **The loop has to be fast.** Every change starts with a test, so the test command runs many times an hour. Tests on a simulator are already slower to start than `swift test` (ADR-0004).
- **Checked with Xcode 27.2 (Swift 6.4.2) on the iOS 27.2 simulator (iPhone 18 Pro),** in a scratch package with ADR-0005's settings: a nonisolated Core target, a main-actor UI target, a SwiftData adapter target, and a support target holding fakes that is not in the library product. Test targets used Swift Testing only.
  - `xcodebuild test` against the generated scheme ran every test target, including suites and tests named with raw identifiers, parameterized tests, an `async` model test in the main-actor target (on the main thread, as ADR-0005 expects), `confirmation(expectedCount:)` over an `AsyncStream`, an actor fake and a `Mutex` fake from the support target used by two test targets, a fixture read through `Bundle.module`, and in-memory SwiftData containers built per test while tests ran in parallel. It built with no warnings.
  - A port method of a plain actor holding its own `ModelContext`, called from a `@MainActor` test, ran off the main thread, as the check recorded on #16 found for ADR-0007's design.
  - `-only-testing:` picks out one Swift Testing test with `<TestTarget>/<Suite>/<test>()`, keeping a raw identifier's backticks: ``ScratchCoreTests/`Listing bikes`/`sorts bikes by name`()``. A parameterized test is named with its argument labels, `` `a part is worn out at its limit`(distance:worn:) ``. A suite or a whole target works too. The same works with `test-without-building`.
  - **A filter that matches nothing passes.** The same identifier without backticks, or with a typo, runs no test, prints `Executed 0 tests` and `TEST EXECUTE SUCCEEDED`, and exits 0. The result bundle tells the two apart: `xcrun xcresulttool get test-results summary` reports `totalTestCount` 0 and `result` `unknown`, against 1 and `Passed` for a filter that matched.
  - The generated scheme can't carry launch arguments, but the `.xctestrun` file that `build-for-testing` writes can (the check recorded on #16, whose negative control showed the assertions really were on). Adding `-com.apple.CoreData.ConcurrencyDebug 1` to every test target in that file, then running `test-without-building`, reached the persistence test process (`UserDefaults` read 1) and every other target still passed.
- **Previews need fakes the app doesn't link.** A preview built in `BikeComponentsUI` can only use fakes that `BikeComponentsUI` can import, and everything it imports ships in the app.
- **The OS moves at every point release** (ADR-0002), and so does the simulator the tests run on.
- **Size.** One developer, a small app, and two driven adapters.
- **Reference project.** investment-simulator-2026's [ADR-0007](https://github.com/cebartling/investment-simulator-2026/blob/main/docs/adr/0007-swift-testing-and-test-strategy.md) uses Swift Testing only (`@Test`, `#expect`, `#require`, `@Suite`), gives every library target a test target with Core's as the main one, replaces driven ports with in-memory fakes with no disk, network, real clock or system random source, uses parameterized tests for table-driven logic, and names tests as sentences with raw identifiers. `just test` runs everything and `swift test --filter <Suite>/<test>` runs one test. It has no UI tests, and lists coverage and snapshot tests as things to revisit. Each of its test targets keeps its own `Fakes.swift`, such as `FakeExperimentRepository`.

## Decision

We will test with Swift Testing in the package's test targets, with shared fakes in a test-support module and no UI or snapshot tests, following the reference project, on the terms below.

### Framework

- **Swift Testing only.** Tests use `import Testing`: `@Test`, `@Suite` where a suite needs traits, `#expect`, `#require`, `confirmation` and parameterized tests. XCTest is not used.
- **XCTest only for what Swift Testing can't do,** which today is UI tests (XCUITest) and performance tests (`measure`). Neither is adopted here. A later ADR that adds either uses XCTest for that target alone.

### What is tested where

- **Core** (`BikeComponentsCoreTests`) is the main test target. Domain rules, use cases and reconciliation are tested with in-memory fakes of the ports (ADR-0003, ADR-0009). Anything with a rule belongs in Core so it can be tested there.
- **Models** (`BikeComponentsUITests`) are tested with Core's real use cases over the same fakes, a fixed `now` and a fixed `Calendar` (ADR-0008, ADR-0010).
- **Persistence** (`BikeComponentsPersistenceTests`) is tested against in-memory stores, with migration tests on temporary files (ADR-0007), and covers the mapping and the merge port method (ADR-0009).
- **Strava** (`BikeComponentsStravaTests`) is tested through the fake transport and fixtures ADR-0011 describes.
- **Not unit tested:** views (ADR-0008), the composition root (ADR-0010), `URLSessionTransport` (ADR-0011) and CloudKit itself (ADR-0009). They are checked by running the app.

### No UI tests

- **There is no XCUITest target.** Views hold no logic (ADR-0008), and the logic behind them is tested in models. A UI test target would be a new target in the Xcode project, would need the app to launch with fake adapters (a launch-argument branch in the composition root, which ADR-0010 keeps free of logic), and would run slower and break more often than the model tests that already cover the same behavior.
- **Revisit** when a navigation flow (#17) or an accessibility requirement (#19) needs a check that model tests can't give. That ADR names the target something other than `BikeComponentsUITests` (ADR-0004) and decides how the app launches with fakes.

### No snapshot tests

- **No snapshot tests, and no snapshot package.** A library such as swift-snapshot-testing would need an admitting ADR (ADR-0006). Views hold no logic, and reference images depend on the simulator's OS, which moves at every point release (ADR-0002), so references would be re-recorded at every toolchain move. #19 can revisit this with the design system.

### Test doubles

- **Fakes, not mocks.** A fake is a working in-memory implementation of a port: it stores what it is given and answers from that, so a test sets up state and checks outcomes, not the order of calls. A fake may also record calls, for a test that has to check that something was or wasn't saved, and may be told to throw a given error from a given method, so a model's test can cover each error case (ADR-0011). There is no mocking library, and no fake that only replays a scripted list of calls.
- **A fake keeps the rules its port promises.** Where the real adapter enforces something Core relies on, such as `gearIDTaken` when a bike's gear ID is held by another `UUID` (ADR-0007, ADR-0011), the fake enforces it too. The adapter's test target runs the same test against the fake and the real adapter, parameterized over both, so the two can't drift apart unnoticed.
- **Named `Fake<Port>`,** for example `FakeBikeRepository`, as in the reference project. One per port (ADR-0010), written when a test first needs it. Under ADR-0005 it is an actor, or a final class guarding its state with `Mutex`.
- **No hand-written fakes of use cases.** Use cases have no protocols (ADR-0003). Tests use the real ones over fake ports.

### Where shared fakes live

- **`BikeComponentsTestSupport`, a test-support module.** It is a regular `.target` in `Package.swift`, at `Sources/BikeComponentsTestSupport/`, holding the fakes of Core's ports and helpers that build Core values for more than one test target. This is the new kind of module ADR-0004 says needs an ADR. Its rules:
  - It depends on `BikeComponentsCore` only, and may import Synchronization. It imports no adapter module, `BikeComponentsUI`, SwiftData or `Testing`.
  - It is not in the `BikeComponentsKit` product, so the app never links it. Only test targets depend on it. No library target and not the app target.
  - Its declarations are `package`. It is nonisolated, like Core.
  - It has no test target of its own. Its fakes are exercised by the tests that use them, and the parameterized contract tests above check the ones that model an adapter's rules.
- **Adapter-internal fakes stay in the adapter's test target.** The fake `HTTPTransport` and any Keychain fake belong to `BikeComponentsStravaTests` (ADR-0003, ADR-0011), and fixtures stay in the test target that reads them.

### Previews

- **This ADR adds no previews.** Whether views have previews is #19's decision. Preview fakes can't come from `BikeComponentsTestSupport` without `BikeComponentsUI` depending on it, which would ship the fakes in the app. If #19 adopts previews, it decides where they live, for example a module outside the product that depends on `BikeComponentsUI` and `BikeComponentsTestSupport` (not checked: whether Xcode renders previews from such a module), and that is another new kind of module for its ADR.

### Writing tests

- **Names are sentences.** Suites are structs named for what they test, and tests are sentences, both with raw identifiers: ``struct `Service intervals` `` and ``@Test func `a chain is due after 3000 km`()``. A test file is named for the type or feature it tests, `<Subject>Tests.swift`.
- **Tables are parameterized.** Rules checked against several inputs use `@Test(arguments:)` instead of a loop or copied tests.
- **`#require` for preconditions,** such as unwrapping an optional, so the test stops there. `#expect` for everything else.
- **Each test builds its own state.** A suite's stored properties are set in its `init`, which Swift Testing runs for every test, or the test builds what it needs in its body. Nothing is shared between tests through `static`s or globals (ADR-0005), so tests run in parallel, Swift Testing's default. `.serialized` only with a comment saying why.
- **`@testable import` only where a test needs `internal` declarations,** such as the persistence adapter's schema versions and `@Model` types. Tests otherwise use the module's `package` API.

### Async code

- **Tests are `async` and await the code they test.** An intent, a use case or a port call is awaited directly. A test never sleeps or polls to wait for work to finish.
- **Time is injected, never waited for.** `now`, `Calendar` (ADR-0010) and `sleep` (ADR-0011) are passed in. A test passes a fixed date and a sleep that records the durations and returns at once, or throws to cancel a wait.
- **Values over time use `confirmation`.** A test of an `AsyncSequence`, such as ADR-0009's remote-change port, consumes it inside `confirmation(expectedCount:)` and finishes the sequence from the fake, so the test ends without a timeout.
- **Cancellation is tested by cancelling.** A test starts the work in a task, cancels it at a point the fake controls, such as from inside a fake port call or the recording sleep, and checks the `cancelled` outcome (ADR-0011) and what was saved before it (ADR-0005).
- **Isolation follows the module** (ADR-0005). Model tests run on the main actor without annotations. A test that checks where a port runs marks itself `@MainActor`, as ADR-0007's thread check does.

### Persistence in tests

- **In-memory, one container per test,** as ADR-0007 says, with `cloudKitDatabase: .none` (ADR-0009). Each test opens its own adapter through a helper in `BikeComponentsPersistenceTests`, and keeps the adapter, which holds both the `ModelContainer` and its `ModelContext` (ADR-0007). A helper never returns a context without its container, because the context stops working once its container is released.
- **Migration tests use their own temporary directory,** named with a new `UUID` under `FileManager.default.temporaryDirectory`, and remove it when they end. A failed removal is recorded as a test issue, not ignored.
- **The thread check runs first.** ADR-0007's check that a port method called from the main actor runs off the main thread is among the adapter's first tests, run with the concurrency assertions on. If it fails, ADR-0007 is revisited.

### Running tests

- **A `justfile` at the repository root runs the tests,** with `just`, admitted below. `just test` runs every test, and `just test-only '<identifier>'` runs one test, suite or target. CI (#2) runs the same recipes.
- **The test command is three steps,** because the concurrency assertions have to reach the tests (ADR-0007):
  1. `xcodebuild build-for-testing` against the `BikeComponentsKit` scheme, from `BikeComponentsKit/`, for one iOS Simulator named in the `justfile`, into a derived-data folder that git ignores.
  2. Add `-com.apple.CoreData.ConcurrencyDebug` and `1` to the `CommandLineArguments` of every test target in the `.xctestrun` file it wrote. Every target, so a new test target needs no edit and no target is picked out by name.
  3. `xcodebuild test-without-building -xctestrun <file>` with a result bundle, adding `-only-testing:<identifier>` for `test-only`. The recipe uses the `.xctestrun` file this build wrote, whose name carries the SDK version and architecture, and removes the previous result bundle first, because `-resultBundlePath` fails when the path exists.
- **The identifier reaches `xcodebuild` as a positional argument.** The `justfile` sets `positional-arguments` and the recipe passes `"-only-testing:$1"`, never `{{identifier}}`. `just` pastes an interpolated value into the shell line, so the backticks of a raw identifier become command substitution: checked with `just` 1.59.0, an interpolated ``T/`Suite name`/`a test`()`` was a shell syntax error, and the positional form reached the command unchanged.
- **A run that executed no test fails.** After step 3, the recipe reads `totalTestCount` from the result bundle with `xcrun xcresulttool get test-results summary`, and fails with a message naming the filter when it is 0. A mistyped single-test filter otherwise passes.
- **Single-test identifiers** are `<TestTarget>/<Suite>/<test>()`, with the raw identifiers' backticks kept and quoted for the shell: ``just test-only 'BikeComponentsCoreTests/`Service intervals`/`a chain is due after 3000 km`()'``. A parameterized test adds its argument labels, as in `` `name`(distance:worn:) ``. ``BikeComponentsCoreTests/`Service intervals` `` runs a suite, and `BikeComponentsCoreTests` a target.
- **The skeleton writes the `justfile`.** No package exists yet. The skeleton creates it with its first test, and records the commands in `README.md` and `CLAUDE.md`. Which simulator CI uses is #2's.

### Tools

- **`just` is admitted** under ADR-0006's rules for tools, ahead of CI (#2), because the test command needs a wrapper before CI exists.
  - **Tool:** [`just`](https://github.com/casey/just), a command runner. It only runs the recipes' commands, so it doesn't gate CI the way a formatter does, and ADR-0006 lets it be unpinned.
  - **License:** CC0-1.0. ADR-0006 accepts any OSI-approved license for tools, and the OSI hasn't approved CC0, so this is an exception, argued here: CC0 dedicates the work to the public domain, which places fewer conditions on us than any OSI-approved license, and the tool is never shipped or linked, so no license notice goes with the app.
  - **Maintained:** release 1.59.0 on 2026-10-15, and commits on 2026-11-15.
  - **Installed** with Homebrew on a development machine (`brew install just`), as `README.md` says. CI installs it unpinned and prints its version (ADR-0006).
- **The rest ships with Xcode and macOS.** `xcodebuild`, `xcrun xcresulttool` and `/usr/libexec/PlistBuddy` are not third-party tools.

### Options considered

Framework:

- **Swift Testing only (chosen).** Parameterized tests, `#expect` with readable failures, raw-identifier names, `async` tests and `confirmation` for values over time, and suites as structs built per test, which fits value types and parallel runs. The reference project's choice. It costs XCTest's UI and performance APIs, which nothing here uses.
- **XCTest only.** Mature and has UI and performance testing. Rejected: no parameterized tests, more boilerplate (`XCTestCase` subclasses, `test` name prefixes, one assertion function per comparison), and expectations with timeouts where an `async` test can await.
- **Both, Swift Testing for unit tests and XCTest for UI tests.** The rule this ADR keeps for later, but with no UI test target there is nothing for XCTest to do.

UI tests:

- **None (chosen).** Behavior is tested in models, and views are thin.
- **A small XCUITest smoke target** launching the app with fake adapters. Catches wiring mistakes ADR-0010 accepts as a narrow risk. Rejected for now: a project change, a launch-argument branch in the composition root, and a slow, brittle check of little logic. Revisit with #17 or #19.

Snapshot tests:

- **None (chosen).**
- **swift-snapshot-testing.** Catches visual regressions. Rejected: a package under ADR-0006 for views with no logic, and references tied to an OS that moves at every point release.

Test doubles:

- **Hand-written stateful fakes (chosen).** Tests read as setup and outcome, and a fake changes only when its port does.
- **Mocks with call expectations,** hand-written or generated (for example with a macro package). Tests pin how code calls its ports, so a refactor that keeps the behavior breaks them, and a generator is a package under ADR-0006.

Where shared fakes live:

- **A test-support module outside the product (chosen).** One fake per port, as ADR-0010 asks, and the app never links it.
- **Copies in each test target,** as in the reference project. Rejected by ADR-0010: the copies drift.
- **Fakes in `BikeComponentsCore`.** Every test target can reach them, but they would ship in the app and sit beside the domain code.
- **Fakes in a test target that other test targets depend on.** It builds, but the dependent target also links and runs the other target's tests: checked with Xcode 27.2, `-only-testing:` of the dependent target ran both targets' tests.

Running the three steps:

- **A `justfile` (chosen).** One file of named recipes, as in the reference project, which CI can run too. It costs a tool whose license needs the exception above.
- **A shell script in the repository.** No tool and no exception, but recipes and their arguments are hand-parsed, and the reference project's `justfile` doesn't carry over.
- **Leave the wrapper to CI (#2),** where ADR-0004 and ADR-0006 put `just`. Rejected: the single-test command couldn't be recorded until CI exists, and three commands plus a plist edit and a result-bundle check aren't something to type for every test.

Passing the concurrency assertions:

- **Edit the `.xctestrun` file (chosen).** Checked in #16, and it touches no scheme.
- **The app's shared scheme, or a test plan.** ADR-0004 rejected running package tests through the app's scheme, because a test target added only to `Package.swift` would silently not run. Not checked: whether a test plan can carry the arguments for the generated scheme without editing it.
- **Setting the default from inside a test,** with `UserDefaults` before the first store opens. Not checked: it would depend on when Core Data reads the setting and on which test runs first, and only a negative control would show whether the assertions were on.

### Where this diverges from the reference project

- **Where tests run.** The reference project runs `swift test` on the Mac and filters with `--filter`. Here tests run on an iOS Simulator through `xcodebuild` (ADR-0004), in three steps, with `-only-testing:` and a check that a filter matched.
- **Fakes.** Each reference test target writes its own fakes. Here they live once, in `BikeComponentsTestSupport`, and fakes that model an adapter's rules are checked against the real adapter.
- **Async tests.** The reference project's presentation suites are marked `@MainActor`. Here the test target is main-actor by default (ADR-0005).
- **Kept:** Swift Testing only, Core as the main test target, in-memory fakes of driven ports with no disk, network or real clock, parameterized tests for tables, sentence names with raw identifiers, `just test`, and no UI tests.

## Consequences

- **Easier:** writing the first test of every change in the same shape; sharing one fake per port across Core and model tests; running one test from the terminal without a typo passing silently; testing time, sleeps and cancellation without waiting.
- **Harder:** the test command is a recipe, not one `xcodebuild` call, and it depends on the `.xctestrun` format, which a new Xcode could change. Views, the composition root and the wiring are checked only by running the app. A fake that models an adapter rule needs a contract test in the adapter's test target. Single-test identifiers with raw identifiers need backticks and shell quoting.
- **ADR-0004.** Its single `xcodebuild test` invocation becomes this ADR's three-step recipe. Tests still run against the generated scheme on a simulator. `BikeComponentsTestSupport` is a library target not listed in the product and with no test target, the exceptions to ADR-0004's rules that this ADR adds.
- **Answered for earlier ADRs.** ADR-0005: `async` code is tested with `async` tests, injected time and sleeps, `confirmation` and cancellation from inside a fake. ADR-0007: the concurrency assertions reach the tests through the `.xctestrun` file. ADR-0008: model tests use Swift Testing, and there are no UI or snapshot tests. ADR-0010: shared fakes live in `BikeComponentsTestSupport`, there are no previews yet, and no UI test launches the app with fakes. ADR-0011: its tests use Swift Testing.
- **Skeleton.** It creates the `justfile`, `BikeComponentsCoreTests` and `BikeComponentsUITests` with their first tests, and records `just test` and `just test-only` in `README.md` and `CLAUDE.md`. `BikeComponentsTestSupport` is created with the first fake.
- **ADR-0006.** `just` is admitted here rather than by CI (#2), with an argued exception to the tool license rule for CC0-1.0.
- **CI (#2)** runs `just test`, installs `just` unpinned and prints its version, picks the simulator, and decides whether to report coverage.
- **Design system and accessibility (#19)** decides previews, and may revisit UI and snapshot tests.
- **Toolchain upgrades.** A new Xcode is checked against the recipe: that the `.xctestrun` edit still applies and that a filter matching nothing is still caught.
- **Agents.** `CLAUDE.md` records these rules.
