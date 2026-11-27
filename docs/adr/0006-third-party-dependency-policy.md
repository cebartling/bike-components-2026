# 6. Third-party dependency policy

- Status: Accepted
- Date: 2026-11-27

## Context

Every third-party package is code we ship but don't control. It can break the build, lag behind a Swift or OS release, change its license or be abandoned. Several upcoming ADRs may reach for one: persistence (#12, e.g. GRDB), state management (#14, e.g. TCA), dependency injection (#15), networking (#18), crash reporting (#20) and release tooling (#21, e.g. fastlane). ADR-0004 left `just` for CI to decide under this policy. Without an agreed bar, each of those ADRs would judge a package by its own rules.

Forces at play:

- **The toolchain moves with every OS release.** ADR-0002 sets the minimum OS to the SDK we build with, including point releases, and moves the toolchain with each one. A package that doesn't build with the new Xcode blocks that move for the whole app.
- **Concurrency is strict.** ADR-0005 builds every target in Swift 6 language mode, and allows `@preconcurrency`, `@unchecked Sendable` and `nonisolated(unsafe)` only with a comment saying why the code is safe. A package whose API isn't `Sendable`-correct pushes those escapes into our code.
- **Layering already contains packages.** ADR-0003 keeps Core to Foundation only. ADR-0004 declares every package in `Package.swift`, has only the module that needs it use it, and keeps it out of the app target.
- **Distribution.** The app goes to the author and TestFlight testers (ADR-0002), under Apple's terms. The repository is MIT-licensed. The FSF holds that the App Store's terms conflict with the GPL.
- **Privacy.** Apple requires a privacy manifest from code that uses its required-reason APIs, and an SDK that sends data off the device affects what the app has to declare.
- **Build tools aren't shipped.** A formatter, a linter, a task runner and CI actions run on our machines and in CI, but none of their code reaches the app. A third-party GitHub Action still runs with the workflow's token, and a tag can be moved to point at other code.
- **Pinning facts (checked with Xcode 27.2).** Building a local package with `xcodebuild` from its folder writes `Package.resolved` next to its `Package.swift`. If `Package.swift` changes a pin and `Package.resolved` isn't updated, a plain `xcodebuild` build silently resolves again and rewrites the file. With `-onlyUsePackageVersionsFromResolvedFile`, the same build fails with "an out-of-date resolved file was detected".
- **Reference project.** investment-simulator-2026 has no written policy. In practice it admits one package, GRDB, in [ADR-0021](https://github.com/cebartling/investment-simulator-2026/blob/main/docs/adr/0021-sqlite-library-replaces-document-persistence.md), pinned with `exact:` in [`Package.swift`](https://github.com/cebartling/investment-simulator-2026/blob/main/Package.swift) behind a comment naming that ADR, and used only by one adapter target and its tests. It commits `Package.resolved`. Its CI pins SwiftFormat and SwiftLint by version and SHA-256 checksum and prints every tool's version, while `just` comes from Homebrew unpinned ([ADR-0009](https://github.com/cebartling/investment-simulator-2026/blob/main/docs/adr/0009-github-actions-ci-on-pinned-xcode-runner.md)'s amendment).

## Decision

We will use Apple's frameworks first, and add a third-party package only by exception, through an ADR that checks it against the bar below.

### Scope

- **Packages:** any SwiftPM dependency declared in `Package.swift`, whether the app links it, only tests use it, or it supplies macros or build plugins. This includes Apple's open-source packages that aren't part of the SDK, such as `swift-collections` or `swift-async-algorithms`. Binary frameworks (`.binaryTarget`, XCFrameworks) count as packages.
- **Tools:** programs that run on a development machine or in CI but ship no code in the app, such as a task runner, formatter, linter or GitHub Action not defined in this repository.
- **Not covered:** the SDK frameworks and Swift toolchain that ship with the Xcode ADR-0002 sets. They need no approval here, though ADR-0003 still limits what Core imports.

### Packages

- **Default stance.** A package is added only when the SDK can't do the job and writing it ourselves would clearly be worse, for example a SQLite wrapper with migrations and concurrent access. Saving a few lines isn't enough.
- **Admitted by an ADR.** The package is admitted by the ADR for the decision that needs it, such as #12 choosing GRDB, or by an ADR of its own. That ADR has a "Dependency check" section (below). The user approves it by merging the pull request (ADR-0001). An agent never adds a `.package` entry, test-only package or binary target without an accepted ADR. It may propose one in an ADR pull request.
- **The bar.** Every package must:
  - **License:** be MIT, BSD (2- or 3-clause), Apache-2.0, ISC or zlib. GPL, LGPL and AGPL are out. Any other license needs its ADR to argue for it.
  - **Transitive dependencies:** meet the same license, source and maintenance rules, every one of them. Fewer is better, and none is best.
  - **Source:** be built from source. A binary target can't be read, built with our toolchain or fixed by us, and may lag an OS release. An exception needs its ADR to argue for it.
  - **Maintenance:** have had a release or commit within the last 12 months, and build with the Xcode that ADR-0002 sets, for the iOS Simulator and devices at our minimum OS, when it is checked.
  - **Concurrency:** be usable from Swift 6 language mode (ADR-0005) without `@preconcurrency`, `@unchecked Sendable` or `nonisolated(unsafe)` in our code. If one is unavoidable, the ADR says so, and the code carries the comment ADR-0005 requires.
  - **Privacy:** collect no data and send nothing off the device, unless that is the job its ADR admits it for (such as a crash reporter, #20). Then the ADR says what it sends and where. If it uses required-reason APIs, it ships a privacy manifest.
  - **Containment:** be imported by one module, which its ADR names, and by that module's test target. A test-only package is imported only by the test targets its ADR names. Never `BikeComponentsCore` or its test target (ADR-0003), never the app target (ADR-0004). Its types stay inside that module, and an adapter maps them at its boundary (ADR-0003).
  - **Build cost:** for macros and build plugins, the time they add to a clean build (for example compiling `swift-syntax`) and the fact that they run code on our machines at build time count against them.
- **Dependency check.** The admitting ADR records, for the version it pins: the package URL and version, license, latest release and commit dates, the Xcode and iOS versions it was built with, every transitive dependency with its license, whether any target is binary, any concurrency escapes we need, what data it collects or sends and whether it ships a privacy manifest, the module or test targets that import it, and what replacing it would take.
- **Removing a package** changes the decision that admitted it, so the removal comes with the ADR that replaces that decision.

### Pinning and updates

- **Exact versions.** Each package is pinned with `exact:` in `Package.swift`, with a comment naming its ADR and the module that uses it, as in the reference project:

  ```swift
  // ADR-NNNN: used only by BikeComponentsPersistence.
  .package(url: "https://github.com/…", exact: "1.2.3"),
  ```

  No version ranges, branches or revisions.
- **Resolved files are committed.** `BikeComponentsKit/Package.resolved` pins the whole graph, including transitive dependencies, for builds of the package scheme. Xcode keeps a second copy for the app project, expected at `BikeComponents.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (not yet checked, since there is no project yet). Both are committed, and a change that moves a pin updates both.
- **CI uses only the resolved files.** CI builds with `-onlyUsePackageVersionsFromResolvedFile`, so a `Package.swift` change without its resolved file fails instead of resolving silently.
- **Updates are manual.** When the toolchain moves to a new Xcode (ADR-0002), each package is checked for a new release. A security fix is taken as soon as it is known. Each update is one pull request per package, which reads the release notes and repeats the dependency check. An update that still clears the bar needs no new ADR. One that doesn't, for example a new license, a binary target or a new transitive dependency that fails the bar, needs a new ADR or stays on the old version.

### Tools

- **Admitted by the ADR that introduces them**, for example CI (#2) for `just`, SwiftFormat or SwiftLint, and approved the same way. That ADR names the tool, its license and how it is installed. Tools aren't shipped, so any OSI-approved open-source license will do, but they must be maintained.
- **Standalone binaries.** Tools are installed as programs, with Homebrew on a development machine and as `README.md` documents. They are not SwiftPM build-tool plugins or package dependencies, so the package graph holds only code that the app and its tests build.
- **Pinned where they gate CI.** A tool whose version can change whether CI passes, such as a formatter or linter, is pinned in CI by version and SHA-256 checksum. A tool that only runs commands, such as `just`, may be installed unpinned. CI prints every tool's version. When a tool is upgraded locally, its CI pin moves in the same change.
- **GitHub Actions.** Actions from GitHub's own `actions` organization are pinned to a major version tag. Any other action is pinned to a full commit SHA, with its version in a comment, and is used only when a few lines of shell can't do the job.

### Options considered

Default stance:

- **Apple frameworks first, packages by exception (chosen).** Later ADRs can still choose a package, but have to show why the SDK isn't enough.
- **No third-party packages at all.** The simplest rule, but it would decide #12, #14, #18 and #20 in advance and could force us to write our own SQLite layer, which the reference project chose GRDB to avoid.
- **Packages welcome, lightly vetted.** A faster start, but every package has to keep up with each OS release (ADR-0002) and with Swift 6's concurrency rules (ADR-0005), and one that lags blocks the whole app.

Where a package is recorded:

- **An ADR, with `Package.swift` pointing to it (chosen).** It records the options and why the package won (ADR-0001), and `Package.swift` stays the one list of what is used.
- **A dependency list file**, such as `DEPENDENCIES.md`, with a line per package. It's lighter, but records what is used rather than why, and repeats `Package.swift`, so the two can drift.

Version pinning:

- **`exact:` versions with committed resolved files (chosen).** Every version change is an edit to `Package.swift` that shows up in review.
- **`from:` (up to the next major version) with committed resolved files.** The resolved file still pins the version, but any new resolution, for example after adding another package or using Xcode's "Update to Latest Package Versions", can move a package in a change that never mentions it.
- **Branch or revision pins.** No version semantics, and updates are hard to review.

Updates:

- **By hand, when the toolchain moves (chosen).** That is when packages break, and the work comes in one batch.
- **Dependabot version updates.** A pull request for every release. With no packages yet, or one, a scheduled bot adds noise for little gain. Revisit if the list grows.

Tools:

- **Standalone binaries, pinned in CI where they gate it (chosen).** This is the reference project's current practice.
- **SwiftPM build-tool plugins or Mint.** The version would be pinned in `Package.resolved`, but the tool would join the package graph, run on every build and need trusting in Xcode.
- **Unpinned Homebrew installs everywhere.** The reference project's first setup, which it moved away from because a new tool release could fail CI on its own.

### Where this diverges from the reference project

- **A written policy.** The reference project has none. Its GRDB practice (an ADR, an `exact:` pin with a comment naming the ADR, one adapter target and its tests, never Core) becomes the rule here, plus a written bar and dependency check.
- **Two resolved files.** The reference project builds with SwiftPM alone and has one `Package.resolved`. Here the package scheme and the Xcode project each keep one (ADR-0004), so both are committed and kept in step.
- **CI resolution.** The reference project's CI doesn't restrict resolution to its resolved file. Here CI passes `-onlyUsePackageVersionsFromResolvedFile`.
- **GitHub Actions.** The reference project uses only actions from GitHub's `actions` organization, by tag, and has no rule for others. Here any other action is pinned to a commit SHA.

## Consequences

- **Easier:** judging a package in #12, #14, #15, #18, #20 or #21 against one bar; seeing every package and why it is there from `Package.swift`; reviewing version changes, which are always visible edits.
- **Harder:** each package costs an ADR and a dependency check. Updates are a manual job at every toolchain move. Two resolved files have to be kept in step.
- **ADRs that consider a package** (#12, #14, #15, #18, #20, #21) include the dependency check for the one they choose.
- **Testing (#16).** A snapshot-testing or other test-only package is a package under this policy.
- **CI (#2)** decides which tools it uses (including `just`, which ADR-0004 left to it), pins them as above, builds with `-onlyUsePackageVersionsFromResolvedFile`, and pins actions as above.
- **Skeleton.** It has no packages, so there is no `Package.resolved` until the first package arrives. When one does, check where Xcode writes the project's resolved file, and that both files agree.
- **Agents.** `CLAUDE.md` tells agents not to add a package or tool without following this policy.
