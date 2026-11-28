# 15. Project file changes with Apple's `xcodeproj` tool

- Status: Accepted
- Date: 2026-11-27

## Context

The skeleton (#37) is the first time the project exists, and creating it went differently from what the earlier ADRs expected:

- **ADR-0004** says the project is changed in Xcode, never by hand-editing the `.pbxproj` or with a generator, and that the app's shared scheme is committed under `BikeComponents.xcodeproj/xcshareddata/`. #37 therefore listed the project's changes as steps for the user in Xcode.
- **ADR-0013** puts every app target setting in `Config/BikeComponents.xcconfig` and keeps the target level of the `.pbxproj` empty. The user sets the base configuration and deletes target-level settings in Xcode, and review checks the target's `buildSettings`.
- **ADR-0014** sets `UIApplicationSupportsMultipleScenes` to `false` in `BikeComponents/Info.plist`, and asks the skeleton to check that the key survives the merge with the generated scene manifest.

What happened, with Xcode 27.2 (all checked on the iOS 27.2 simulator, iPhone 18 Pro):

- **Xcode kept locking up** while the user created the project. Every project change in #37 was a step for the user in Xcode, so the skeleton stalled.
- **Xcode 27.2 doesn't write a `.pbxproj` for a new project.** File > New > Project… > App (the chooser has no platform tabs) wrote `BikeComponents.xcodeproj/project.xcproj`: a JSON-style text file with `files`, `targets`, `packages` and `build-settings` per target and for the project, no object IDs except a few fixed ones, and readable diffs. The project was the file Xcode ships as `IDEFoundation.framework/…/UntitledAppProjectPrototype/Project.xcodeproj/project.xcproj`, with only these changes: the names (`MyApp` to `BikeComponents`), a unique value for the placeholder bundle ID, the supported platforms narrowed to iPhone and iPad, and deployment targets of 27.2. Xcode nested it in a folder named after the product, with its own git repository.
- **Xcode 27.2 ships two command-line tools for this format,** in `Xcode.app/Contents/Developer/usr/bin/`:
  - `xcodeproj` "inspects and modifies Xcode project files from the command line": `init`, build settings at the project or target level (`setting get`/`list`/`set`/`unset`), targets and build phases, groups and file references, including excluding a file from a buildable folder (`group exclude`), the `.xcconfig` file backing a configuration (`config set`), and packages (`pkg add-local`/`add`/`link`). It never touches schemes, workspaces or the contents of `.xcconfig` files.
  - `xcprojformatter` pretty-prints a `project.xcproj` in its canonical format (`--update` rewrites it in place).
- **The skeleton was built with them.** Copying the prototype gave the same project Xcode wrote. Then:
  - `xcodeproj` narrowed the platforms, linked the local package, added `Config/` and set the `.xcconfig` file as the base configuration, which it records as `specialized-configurations`. It also excluded `Info.plist` from the buildable folder (`membership-exceptions`) and unset every target setting.
  - `xcrun xcodeproj setting list --target BikeComponents` then reports "(no build settings)" with the `.xcconfig` file linked for both configurations.
  - The app target's `-showBuildSettings` output matched the template's except for the intended changes: Swift 6, the three upcoming features, no `SWIFT_APPROACHABLE_CONCURRENCY`, the bundle identifier and `INFOPLIST_FILE`. `SUPPORTS_MACCATALYST = NO` came with narrowing the platforms. Later changes, each checked by building, added `DEVELOPMENT_TEAM`, turned scene-manifest generation off and dropped the macOS leftovers (below).
  - The app builds with no warnings, launches, and shows the launch model's ready state.
- **The generated scene manifest wins over `Info.plist`.** With `INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES` (the template's), the built app had `UIApplicationSupportsMultipleScenes` set to `true`, although `BikeComponents/Info.plist` said `false`. Turning generation off and giving `Info.plist` the whole manifest, the key plus an empty `UISceneConfigurations`, gave `false`, and the SwiftUI app still launched.
- **No scheme file is needed.** In a fresh clone with no scheme files, `xcodebuild -list` shows the `BikeComponents` and `BikeComponentsKit` schemes, `xcodebuild build -scheme BikeComponents` builds the app, and nothing is written into the repository.
- **ADR-0006** admits tools by ADR. `xcodebuild`, `xcrun`, `xcresulttool` and `simctl` are used without one, because they ship with Xcode, which ADR-0002 already requires.

## Decision

We will keep the project in Xcode 27's `project.xcproj` format and make project changes with Apple's `xcodeproj` tool, so agents can make them, on the terms below.

- **The project file is `BikeComponents.xcodeproj/project.xcproj`,** the format Xcode 27.2 writes. There is no `.pbxproj`.
- **Project changes are made with `xcrun xcodeproj`, by agents or by the user, followed by `xcrun xcprojformatter --update BikeComponents.xcodeproj`,** so the file stays in its canonical form and diffs stay small. That covers package links, groups and file references, membership exceptions, base configurations, target settings that have to be unset, build phases and targets. The user may still use Xcode, then runs the formatter or asks an agent to.
- **Hand edits of `project.xcproj` only where `xcodeproj` has no command,** such as renaming a target. The edit is followed by the formatter, and checked with `xcodebuild -list` and a build.
- **No generator.** `xcodeproj` and `xcprojformatter` edit the committed project in place. Nothing is generated from a second manifest, so ADR-0004's rejection of XcodeGen and Tuist stands.
- **The Xcode tools count as part of the toolchain.** `xcodeproj` and `xcprojformatter` ship with Xcode, like `xcodebuild`, so ADR-0006's tool admission doesn't apply. Their behavior moves with each Xcode release, as ADR-0002's toolchain policy already expects.
- **ADR-0013's empty target level is checked with `xcrun xcodeproj setting list --target BikeComponents`,** which must report "(no build settings)" for Debug and Release, with the `.xcconfig` file linked.
- **Schemes are Xcode's automatic ones.** No scheme file is committed: `xcodebuild` creates `BikeComponents` for the app and `BikeComponentsKit` for the package. A scheme is committed only when one needs settings the automatic one lacks. `xcodeproj` can't write schemes, so the user creates it in Xcode, and an `.xcscheme` is never hand-edited.
- **The scene manifest comes from `Info.plist`.** `INFOPLIST_KEY_UIApplicationSceneManifest_Generation = NO` in the `.xcconfig` file. `BikeComponents/Info.plist` holds `UIApplicationSceneManifest` with `UIApplicationSupportsMultipleScenes` set to `false` and an empty `UISceneConfigurations`. The other generated `Info.plist` keys stay generated.
- **The prototype's macOS leftovers are dropped.** It is a multiplatform template, so it sets `ENABLE_APP_SANDBOX`, `ENABLE_USER_SELECTED_FILES`, `LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]` and `REGISTER_APP_GROUPS`. The `.xcconfig` file omits them: without them, a device build's entitlements and every other build setting were unchanged.
- **Capabilities** (iCloud, Background Modes: ADR-0009) need an entitlements file and portal registration that `xcodeproj` doesn't cover, so they stay with the user in Xcode. Whoever adds one moves any target-level setting Xcode writes into the `.xcconfig` file (ADR-0013), and runs the formatter.

### Options considered

- **Keep every project change with the user in Xcode, as ADR-0004 said.** Rejected: Xcode kept locking up, every change waited on the user, and the format no longer needs protecting from hand edits.
- **`xcodeproj` plus the formatter (chosen).** It's Apple's tool for this format, validates what it writes, and covered every change the skeleton needed.
- **Hand-edit `project.xcproj` freely.** The file is readable, but its format isn't documented, and the tool already knows the keys (`specialized-configurations`, `membership-exceptions`, `package-product-members`). Kept for what the tool can't do.
- **A generator (XcodeGen, Tuist).** ADR-0004's reasons still hold, and the format it would hide is now readable on its own.
- **Commit the app's shared scheme.** ADR-0004 planned it. Rejected for now: the automatic schemes build and test, and a scheme file would be an `.xcscheme` only Xcode should write.
- **Keep scene-manifest generation and add only the key in `Info.plist`.** Rejected: the generated manifest's `true` won.

## Consequences

- **Easier:** project changes no longer wait on the user or on Xcode's editor, and reviewing them means reading a short JSON-style diff.
- **Harder:** `xcodeproj` and the format are new in Xcode 27 and may change with each release. A command missing from the tool means a hand edit checked by building. The automatic schemes can't carry settings, but none are needed: test arguments go through the `.xctestrun` file (ADR-0012).
- **ADR-0004.** Its rules "change the project in Xcode, never by hand-editing the `.pbxproj`" and "the app's shared scheme is committed" are replaced by this ADR. Its rejection of generators stands.
- **ADR-0013.** Its rules stand, with `.pbxproj` read as `project.xcproj`. The target-level check is `xcodeproj setting list`, and deleting a target-level setting is `xcodeproj setting unset`, which an agent may run. Setting the base configuration is `xcodeproj config set`. Of its two open checks, the target level stayed empty after the tool's edits, and after the author opened, built and ran the project in Xcode 27.2, which left `project.xcproj` unchanged and wrote only git-ignored `xcuserdata`. Which settings a capability writes is still unchecked.
- **ADR-0014.** Its key's check failed with manifest generation on, so the manifest moved to `Info.plist`, as decided above. Its other rules are unchanged.
- **CI (#2)** uses the automatic schemes, and may run `xcodeproj setting list --target BikeComponents` as the target-level check.
- **Agents.** `CLAUDE.md` records the tool and the rules.
