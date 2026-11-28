# 13. Build configuration and secrets

- Status: Accepted
- Date: 2026-11-27

## Context

The skeleton (ADR-0004) is next. It creates `BikeComponents.xcodeproj`, and the app target's build settings have to live somewhere from its first commit. The Strava integration (#3) needs per-developer values, at least the Strava client ID, inside the app without committing them. #21 asks for both decisions, plus CI scope, signing and release. This ADR settles only the build configuration layout and secrets. The rest stays with #21, because nothing reaches TestFlight yet.

Earlier ADRs already settle part of it:

- **ADR-0002.** Each OS release raises the deployment target "of every app target and local Swift package" in the same change as the toolchain.
- **ADR-0004.** The project is changed in Xcode, never by hand-editing the `.pbxproj` or with a generator. Package targets' Swift settings go in `Package.swift`. App target settings go "in the Xcode project or in files it references", and whether they live in `.xcconfig` files was left to #21. App resources (asset catalog, `Info.plist`, entitlements) live in `BikeComponents/`, a buildable folder.
- **ADR-0005.** The app target sets `SWIFT_VERSION = 6` and the `SWIFT_UPCOMING_FEATURE_*` settings for the three upcoming features, and the template's `SWIFT_APPROACHABLE_CONCURRENCY` is removed. Today each of these is a project change, so the user makes it.
- **ADR-0006.** A tool, a project generator included, needs an accepted ADR.
- **ADR-0010.** Only the composition root uses system shared instances such as `Bundle.main` (Core does no `Bundle` I/O), and it passes values to adapters through their initializers, with no defaults.
- **ADR-0011.** The client secret and authorization codes never appear in URLs or error details.

Forces at play:

- **The repository is public** (MIT, on GitHub). Anything committed is published, and an OAuth client secret is meant to stay confidential.
- **#3 hasn't decided whether the client secret ships in the app.** Strava's token exchange and refresh both need it, and Strava documents no PKCE. #3 weighs embedding it, which ADR-0002 allows only for a TestFlight audience, against a small backend. Either way the client ID ships in the app, and it is public anyway: it appears in every authorize URL.
- **A value in an app's `Info.plist` isn't secret.** Anyone with the `.ipa` can read it. Keeping a value out of the repository keeps it off GitHub, not out of the build.
- **The `.pbxproj` is hard to review and only the user edits it.** Every changed setting is a project change, and its diff sits among object IDs.
- **Xcode's iOS App template (Xcode 27.2)** writes settings at two levels. The project level gets the compiler warnings, and the Debug and Release differences (optimization, debug information, testability). The target level gets the product name, bundle identifier, versions, generated `Info.plist` keys, device family, `IPHONEOS_DEPLOYMENT_TARGET`, asset catalog names, `ENABLE_PREVIEWS`, `SWIFT_VERSION`, `SWIFT_APPROACHABLE_CONCURRENCY` and `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY`.
- **Checked with Xcode 27.2** in a scratch iOS app outside the repository. The scratch project was generated with XcodeGen, which ran only for this check. It had a buildable folder holding an `Info.plist`, and its target used an `.xcconfig` file as the base configuration for Debug and Release:
  - **Precedence.** A setting at the target level of the `.pbxproj` beats the target's `.xcconfig` (`SWIFT_VERSION` 5.0 in the project beat 6 in the file). The target's `.xcconfig` beats the project level (`IPHONEOS_DEPLOYMENT_TARGET` 27.2 in the file beat 26.0 in the project). An `.xcconfig` only takes effect for settings the target level leaves unset.
  - **Optional include.** `#include? "Secrets.xcconfig"` with the file missing builds without a warning, and settings the file would set keep their earlier value, here empty. With the file present, its values win over earlier lines, and a line after the include wins over it.
  - **`//` starts a comment.** `URL_VALUE = https://www.strava.com/oauth` became `https:`.
  - **Into the app.** With `GENERATE_INFOPLIST_FILE = YES` and `INFOPLIST_FILE` pointing at an `Info.plist` holding `<key>StravaClientID</key><string>$(STRAVA_CLIENT_ID)</string>`, the built `Info.plist` merged both and held the substituted value, or an empty string with no secrets file. `plutil -p` read it in plain text.
  - **Not copied.** An `.xcconfig` file placed inside the buildable folder wasn't copied into the `.app`. Neither was `Info.plist`, which had a membership exception.
  - A simulator build with `CODE_SIGNING_ALLOWED=NO` succeeded without the secrets file.
- **Reference project.** investment-simulator-2026 builds with SwiftPM alone ([ADR-0006](https://github.com/cebartling/investment-simulator-2026/blob/main/docs/adr/0006-swiftpm-only-build-and-hand-assembled-app-bundle.md)), so it has no Xcode build settings. Its `Info.plist` is a committed file, and `just bundle` stamps the version into the bundled copy ([ADR-0018](https://github.com/cebartling/investment-simulator-2026/blob/main/docs/adr/0018-release-and-distribution.md)). Its one secret, a market-data API key, belongs to the user: it is entered in a Settings scene and stored in the Keychain behind a port ([ADR-0012](https://github.com/cebartling/investment-simulator-2026/blob/main/docs/adr/0012-market-data-and-secrets.md)).

## Decision

We will keep the app target's build settings in one committed `.xcconfig` file. Per-developer values go in a git-ignored `.xcconfig` it includes, and reach the code through `Info.plist`, on the terms below.

### Configuration layout

- **One file for the app target: `Config/BikeComponents.xcconfig`,** at the repository root, set in Xcode as the `BikeComponents` target's base configuration for both Debug and Release. It is outside the buildable folder because it is build input, not an app resource.
- **The target level of the `.pbxproj` holds no build settings.** Every app target setting is in `Config/BikeComponents.xcconfig`. That covers everything Xcode's template writes at the target level, ADR-0005's Swift settings, and the signing settings (`CODE_SIGN_STYLE`, `DEVELOPMENT_TEAM`; the team ID isn't secret, since every signed build carries it). The skeleton moves the template's target settings into the file. In Xcode, the user then deletes them at the target level so the file's values show through.
- **The deployment target is set only in the file.** `IPHONEOS_DEPLOYMENT_TARGET` is a target setting in the template, so it moves with the others. If the project level sets it too, the skeleton deletes it there, so ADR-0002's OS bump edits one line for the app.
- **The rest of the project level stays as Xcode's template wrote it:** compiler warnings, the Debug and Release differences, `SDKROOT`. None of them is a decision of ours, and moving them would only copy Xcode's defaults into a file.
- **Two build configurations, Debug and Release.** No others: there is one Strava application and one CloudKit container, and CloudKit picks its development or production environment from how the app is signed and distributed, not from a configuration. Add a per-configuration file (for example `Config/BikeComponents-Debug.xcconfig` including the shared one) only when a target setting first has to differ between Debug and Release.
- **Settings are changed by editing the file, as text.** Agents may edit `Config/*.xcconfig` like any source file. Changes in Xcode's Build Settings editor land at the target level of the `.pbxproj`, so settings aren't changed there. When Xcode writes a target-level setting anyway (adding a capability writes `CODE_SIGN_ENTITLEMENTS`, and may write `INFOPLIST_KEY_*` settings), the same change moves it into the file, and the user deletes it at the target level in Xcode. Review checks that the target's `buildSettings` in the `.pbxproj` stay empty.
- **What still goes through the user in Xcode:** setting the base configuration, capabilities, package links, membership exceptions, schemes and anything else in the `.pbxproj` or a scheme (ADR-0004).
- **Values containing `//` are written with an empty substitution,** `https:/$()/www.strava.com`, because `//` starts a comment.

### Per-developer values and secrets

- **Values that differ between developers, or must not be published, go in `Config/Secrets.xcconfig`,** which git ignores. `Config/BikeComponents.xcconfig` declares each such setting with an empty value, which documents the keys, and ends with `#include? "Secrets.xcconfig"`. The include is the file's last line, so the secrets file overrides the empty values and nothing after it overrides the secrets.
- **The Strava values are the first.** #3 names them and decides whether the client secret is one of them. The expected settings are `STRAVA_CLIENT_ID` and, if #3 embeds the secret, `STRAVA_CLIENT_SECRET`. The client ID is public, but it belongs to whoever registered the Strava application, so it goes in the secrets file with the secret.
- **Values reach the code through `Info.plist`.** `BikeComponents/Info.plist` holds one key per value, set to the build setting (`<key>StravaClientID</key><string>$(STRAVA_CLIENT_ID)</string>`). Xcode merges it with the generated `Info.plist`. Adding the file and its membership exception is a project change (ask the user). The composition root reads each key with `Bundle.main.object(forInfoDictionaryKey:)` and passes the string, empty if missing, to the adapter's initializer. Nothing else reads `Info.plist`.
- **The adapter checks the values, not the composition root** (ADR-0010 keeps decisions out of it). The Strava adapter's public initializer, or the configuration type it takes, throws a typed error naming the missing key when a value is empty (#3 designs the type). `start` passes the error on, and the launch fails and shows it (ADR-0010, ADR-0011). A build without the secrets file still compiles and its tests still pass, and its first launch says which key is missing.
- **Secrets never get committed, logged or put in a URL.** ADR-0011's rules apply, and #20 decides logging with them in mind. `Config/Secrets.xcconfig` is listed in `.gitignore` before the file is first created.
- **The `.ipa` exposes every value.** Testers can read anything in `Info.plist`. Whether that is acceptable for the client secret is #3's decision. If #3 chooses a backend, the secret never enters this file.
- **CI doesn't get the secrets.** CI builds and tests without `Config/Secrets.xcconfig`. Tests use fakes and fixtures (ADR-0012), so none needs a real value. If a later release ADR has CI archive TestFlight builds, it decides how CI writes the file from a protected secret.

### Options considered

Where target settings live:

- **In the `.pbxproj`, as Xcode leaves them.** No setup. Rejected: every setting change, including ADR-0002's bump at each OS release and ADR-0005's Swift settings, is a project change only the user can make, reviewed as a `.pbxproj` diff.
- **`.xcconfig` for the target, project level left as is (chosen).** Every setting we decide is readable text, and agents can change it.
- **`.xcconfig` for both levels.** The project's own settings would move to a second file too. Rejected for now: dozens of template defaults to move by hand, with no decision of ours among them.
- **Per-configuration files from the start.** No target setting differs between Debug and Release yet. Added when one does.
- **A project generator (XcodeGen, Tuist).** ADR-0004 rejected generating the project. Each is also a tool under ADR-0006.

Where the files live:

- **`Config/` at the root (chosen).** Build input stays apart from app sources and resources. Nothing in it can become a resource.
- **Inside `BikeComponents/`.** The check showed an `.xcconfig` there isn't copied into the app, but the folder's members are app sources and resources, and a secrets file next to them is one wrong file type or exception away from shipping.

How per-developer values get into the app:

- **A git-ignored `.xcconfig`, included optionally, read through `Info.plist` (chosen).** Built into Xcode, a fresh clone and CI build without it, and no build phase or script is needed.
- **Commit the values.** Rejected: the repository is public, and the secret must stay confidential. The client ID is harmless, but it is tied to one developer's Strava application.
- **Scheme environment variables.** Rejected: they reach the app only when Xcode launches it, never from the home screen or TestFlight.
- **A git-ignored Swift file with constants.** Rejected: a fresh clone and CI fail to compile unless something generates a stub, and a stub that compiles hides the missing value until launch anyway.
- **A build phase script that generates Swift from the environment.** Rejected: a project change, a script under Xcode's user script sandboxing, and generated code to keep out of git, for what `Info.plist` substitution does already.
- **The user enters the value at runtime, as the reference project does.** Rejected: the Strava client credentials belong to the app's registration, not to the user, and testers would need the secret.
- **Obfuscating the value in the binary.** Rejected: it can still be extracted, and it adds code.

### Where this diverges from the reference project

- **Build settings.** The reference project builds with SwiftPM alone and has no Xcode build settings. Its `Info.plist` is committed and the version is stamped when the bundle is built. Here an Xcode project generates `Info.plist`, so the versions and every other target setting live in `Config/BikeComponents.xcconfig`.
- **Secrets.** The reference project's secret is the user's own API key, entered at runtime and kept in the Keychain. Here the secrets belong to the app's Strava registration, so they go in at build time. Strava's OAuth tokens are still the user's, and stay in the Keychain inside the Strava adapter (ADR-0003, ADR-0009).

## Consequences

- **Easier:** reading and reviewing the app's settings, which are one short text file; ADR-0002's OS bump and ADR-0005's Swift settings, which become text edits an agent can make; adding a per-developer value without touching the project.
- **Harder:** the skeleton has an extra setup step in Xcode (set the base configuration and delete the target-level settings). Settings Xcode writes later have to be moved by hand. A typo in the include's file name, or a missing file, isn't a build error, so empty values only show at launch. A `//` in a value is silently cut. Without a Strava application of their own, a developer can build and test but not launch the app.
- **ADR-0004.** Its rule against hand-editing the `.pbxproj` stands. Target settings are no longer a project change: they are edits to `Config/BikeComponents.xcconfig`. Setting the base configuration, capabilities, package links, membership exceptions and schemes still are.
- **ADR-0005.** The app target's `SWIFT_VERSION` and `SWIFT_UPCOMING_FEATURE_*` settings are lines in `Config/BikeComponents.xcconfig`. `SWIFT_APPROACHABLE_CONCURRENCY` isn't set anywhere.
- **ADR-0002.** A minimum-OS bump edits `IPHONEOS_DEPLOYMENT_TARGET` in `Config/BikeComponents.xcconfig` and the `platforms` in `Package.swift`.
- **Skeleton.** It creates `Config/BikeComponents.xcconfig` with the template's target settings and ADR-0005's, and adds `Config/Secrets.xcconfig` to `.gitignore`. The user sets the base configuration and deletes the target-level settings in Xcode. The skeleton checks with `xcodebuild -showBuildSettings` that the app target reads its values from the file. `BikeComponents/Info.plist` and the empty Strava settings arrive with #3, the first code that reads them.
- **Strava (#3)** names the settings and `Info.plist` keys, decides whether the client secret is embedded, and designs the adapter's configuration check and its error. `README.md` then says how to create `Config/Secrets.xcconfig`.
- **CI (#2)** builds the app without secrets. It may add a check that the app target's `buildSettings` in the `.pbxproj` are empty, so a setting changed in Xcode's editor fails the build instead of waiting for review.
- **#21 stays open** for CI scope, signing and release. Signing is automatic, as Xcode's template sets it, until that ADR decides. A release ADR that has CI archive builds also decides how CI gets the secrets file.
- **Logging (#20)** keeps the values out of logs.
- **Not checked in Xcode's own project.** The checks used a generated scratch project. That Xcode's editor leaves an emptied target level empty, and which settings adding a capability writes, are checked during the skeleton.
- **Agents.** `CLAUDE.md` records the layout and the secrets rule.
