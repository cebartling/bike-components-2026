# 8. Sync and backup with CloudKit

- Status: Accepted
- Date: 2026-11-27

## Context

Users put real effort into recording components and service history. Losing it to a lost or replaced device is the worst outcome the app can have. The app is universal (ADR-0002), so a rider with an iPhone and an iPad will expect the same data on both. This ADR covers the app's own data across the user's devices. Keeping that data up to date with Strava is #3's sync model.

ADR-0007 settles the store: one SwiftData store, `BikeComponents.store` in Application Support, behind Core's repository ports, with every `ModelConfiguration` passing `cloudKitDatabase: .none` until this ADR. It already keeps the schema within CloudKit's rules (every attribute optional or defaulted, every relationship optional with an explicit inverse, no unique constraints, no `.deny` delete rules), so turning CloudKit on needs no schema migration. Core enforces that Strava gear IDs are unique, writes upsert by the domain `UUID`, and the adapter also checks a bike's gear ID when it saves one. ADR-0007 left to this ADR how duplicates that arrive from another device are reconciled.

Forces at play:

- **Device backup alone covers a lost device, not a second one.** iOS backs up Application Support with the device, so a restore brings the store back. It doesn't put the data on the rider's other device, and it is only as recent as the last backup.
- **SwiftData mirrors to CloudKit itself.** Apple's article [Syncing model data across a person's devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices) says it "requires two separate capabilities": iCloud with CloudKit and a container, and Background Modes with Remote notifications, so the app hears about changes from CloudKit. A `ModelConfiguration` can name the container with `cloudKitDatabase: .private("iCloud.…")`. The SDK's `CloudKitDatabase` offers `.automatic`, `.none` and `.private(_:)` only: SwiftData has no public or shared database.
- **The schema becomes additive once it reaches production.** The same article: "CloudKit schemas are additive only, which means you're unable to delete model types or change existing model attributes after you promote a schema to production." Apple's [Creating a Core Data model for CloudKit](https://developer.apple.com/documentation/coredata/creating-a-core-data-model-for-cloudkit) adds that "you can't rename or delete CloudKit record types and fields in production". The development schema is "a draft schema that you can rewrite as often as necessary". Development builds can use either environment; App Store builds use production only ([Deploying an iCloud container's schema](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema)). TestFlight builds are signed for distribution and use production too. The schema reaches production only when someone deploys it in the CloudKit Console, which copies record types, fields and indexes, not records. SwiftData's article initializes the development schema by hand from a debug build.
- **Conflicts are the framework's.** SwiftData's CloudKit sync is built on `NSPersistentCloudKitContainer`. Apple's documentation doesn't describe how it resolves conflicting changes from two devices. Developer reports, citing a WWDC session, describe last writer wins, and SwiftData offers no hook to change it.
- **Duplicates are certain, not rare.** Bikes and rides are created by Strava imports (#3, #4), and each device can import. Two devices that import the same Strava bike before syncing each create a record with its own `UUID`. The store has no unique constraints, so CloudKit keeps both. A second device that backfills rides before the first device's rides arrive duplicates them all. Checking the local store before inserting can't prevent this, because the other device's records haven't arrived yet. An Apple engineer's answer in the developer forums is to deduplicate after changes are imported.
- **Relationships can't cross stores.** "Entities in a configuration must not have relationships to entities in another configuration" (Creating a Core Data model for CloudKit). Components are installed on bikes, so keeping Strava-sourced bikes in a local store and app-owned data in a synced one would turn those relationships into references by ID.
- **The adapter sees other writers' changes, checked with Xcode 27.2 and Swift 6.4.2.** No iOS Simulator runtime was installed, so this ran on macOS 27.2 with the same SwiftData, in a scratch package with our Swift settings, in debug and release builds. A plain actor holding one long-lived `ModelContext` (ADR-0007) fetched a record, then a second context on the same container, standing in for CloudKit's importer, renamed it, inserted a duplicate and deleted it. Each fetch from the actor's context returned the current rows. So did a write through a second `ModelContainer` on the same file. `ModelContext.fetchHistory` with a predicate on the transaction author and on a saved `DefaultHistoryToken` (which is `Codable`) returned only the other writer's transactions. CloudKit's real importer was not tested.
- **Strava tokens rotate.** A refreshed refresh token invalidates the old one at once (#3). Two devices sharing one set of tokens would invalidate each other's.
- **Reference project.** investment-simulator-2026 is local-only ([ADR-0021](https://github.com/cebartling/investment-simulator-2026/blob/main/docs/adr/0021-sqlite-library-replaces-document-persistence.md)): its database lives in Application Support, covered by device backups (Time Machine on the Mac), with no sync. Deleting is permanent: no undo, no trash. It is one Mac.

## Decision

We will sync the whole store across the user's devices with SwiftData's CloudKit mirroring, to the user's private CloudKit database, and reconcile duplicate Strava records in Core after changes arrive.

### Scope

- **CloudKit mirroring of the whole store.** Bikes, rides, components, installations and service records all sync. A new or replaced device gets the data back from iCloud once the user signs in with the same Apple Account. Device backup still covers Application Support, as before.
- **The private database only.** No sharing between users and no public data.
- **No export yet.** There is no user-initiated export or import file. See Consequences.

### Configuration

- **The container is named, not inferred.** Every `ModelConfiguration` for the app's store passes `cloudKitDatabase: .private(<container identifier>)`, the iCloud container in the app's entitlements, instead of `.automatic`, so the store syncs to that container and no other. The identifier is chosen when the capability is added.
- **Tests never sync.** Adapter tests keep `cloudKitDatabase: .none` with in-memory or temporary-file stores (ADR-0007).
- **Capabilities.** The app target gets iCloud (CloudKit, with the container) and Background Modes (Remote notifications). These are Xcode project changes, which the user makes (ADR-0004).
- **The store opens without iCloud.** If the user isn't signed in to iCloud, the store works locally and mirroring starts when they sign in. Apple treats a signed-out user as a transient error that needs no action. Signing out later is different: developer forum answers, not Apple's documentation, say that signing out of iCloud or turning iCloud off for the app removes the local copy, which returns from iCloud on sign-in, and that changes not yet uploaded can be lost. This is checked on a device (see Consequences). ADR-0007's fail-fast rule still applies to a store that can't be opened or migrated.
- **Only the persistence module knows about CloudKit.** It may import Core Data for the debug-only schema initialization below. Core, `BikeComponentsUI` and the app target see neither.

### Duplicates

- **Core reconciles.** Reconciling duplicate Strava records is part of Core's import reconciliation (ADR-0003). Bikes that share a Strava gear ID, or rides that share a Strava activity ID, are duplicates.
- **The winner is the smallest `UUID`.** Of a set of duplicates, the record with the smallest `UUID` is kept. The rule depends only on the records, so every device picks the same winner, and two devices reconciling at once converge instead of deleting each other's winners.
- **App-owned data moves to the winner.** Components installed on a losing bike, its installations, service records and any other app-owned data move to the winner. The winner's Strava-sourced fields stay as they are; the next import refreshes them. Then the losers are deleted.
- **Rides follow their bike.** Bikes are reconciled before rides. Rides linked to a losing bike move to the winning bike in the same merge. A ride keeps the Strava gear ID it was recorded on, so reconciliation also links any ride whose bike is missing to the bike that holds that gear ID. An incremental import never fetches old rides again, so it can't repair a lost link.
- **A merge is one port call and one save,** so the store is never left half-merged, and the adapter's gear ID check (ADR-0007) never sees a winner and a loser it would reject. The port method's shape is designed with the first code.
- **A failed gear ID check is expected for a while.** Between a CloudKit import and the next reconciliation, two bikes can hold one gear ID, so ADR-0007's check can fail a bike save, from an import or a user's edit, without any Core bug. The adapter's error identifies that case (its form is decided with #18). Core then reconciles and retries the save once. A second failure is a real error.
- **When it runs.** Reconciliation runs at launch, when the app becomes active, at the start of every import (before its upserts), and when the adapter reports changes imported from CloudKit. It scans the whole store: one athlete's bikes and a few thousand rides are cheap to compare, so no history token is kept for it. How the adapter learns of imported changes (persistent history, as checked in Context, or the store's remote-change notification) is settled with the first sync code, on a device.
- **Reconciliation and imports never overlap on a device.** Reconciliation runs under the same one-at-a-time guard as imports (#3), so an import never holds bikes that a merge has since deleted. Changes that arrive from CloudKit during an import are reconciled after the import's current page is saved, and the import reloads its bikes before the next page. Triggers that arrive while a reconciliation is running or waiting are combined into one run, because a first sync arrives in many batches.
- **ADR-0007's "one import at a time"** still holds per device. Across devices it can't, and reconciliation covers the difference.

### Conflicts

- **The framework resolves conflicts.** We accept its last-writer-wins behaviour and add no conflict handling of our own. One person edits the data, and editing the same component on two devices within the sync delay is rare. The data that changes most, rides, comes from Strava and is reconciled as above.
- **Deletes propagate.** Deleting on one device deletes on every device. Deleting stays permanent, as in the reference project. A record deleted on one device while it is edited on another follows the framework's behaviour. A component whose bike was deleted as a duplicate loser is left on no bike (ADR-0003 allows that) rather than lost.

### Schema evolution

- **A production schema is additive.** Once a schema version is deployed to CloudKit's production environment, later versions only add models and attributes. They never delete, rename or change the type of what is already there. This tightens ADR-0007's rule that a version that has reached a TestFlight build is frozen: a shipped version now also limits every version after it.
- **Development schema by hand.** The development schema is initialized from a debug build, as Apple's SwiftData article shows, when the schema changes, not on every launch. Before a TestFlight build that carries a new schema version, the schema is deployed to production in the CloudKit Console. That step belongs to the release checklist (#21).
- **Devices can run different app versions.** A tester's second device may still run an older build. We follow the approach Apple's Core Data article calls "incrementally add new fields to existing record types": older versions see every record but not every field. So a new attribute's default must map to a valid Core value, because records an older version writes leave it at that default.
- **Records can arrive before their parents.** Apple's SwiftData article says "CloudKit processes changes in an indeterminate order" and "the iCloud servers don't guarantee atomic processing of relationship changes". An installation or service record can arrive before its component or bike. A read skips a record whose required relationship hasn't arrived yet, instead of throwing, and reconciliation never matches records on a missing Strava ID. This narrows ADR-0007's "mapping fails loudly" for that case only: a record missing a required relationship is incomplete, not invalid. Any other record that can't make a valid Core value still throws.

### Strava tokens

- **Tokens never sync.** Each device that imports connects to Strava itself and keeps its own tokens in its own Keychain, not marked synchronizable (#3). A device that never connects still sees every bike and ride through CloudKit.

### Options considered

Scope:

- **CloudKit mirroring through SwiftData (chosen).** Multi-device sync and an off-device copy with no server, no package and little code, on the path ADR-0007 kept open. It costs duplicate reconciliation, an additive-only schema once in production, conflict rules we can't change, and a manual deployment step.
- **Local-only, relying on device backup, with sync later.** No new code, and the schema stays free to change. Rejected: an iPad and an iPhone would hold different data, and the restore is only as recent as the last backup. Turning sync on later would need the same reconciliation code anyway.
- **Local plus export files.** An independent copy the user controls. Rejected for now: no multi-device data, and a file format to version and maintain. It remains a possible addition (see Consequences).
- **Our own sync with `CKSyncEngine`.** Full control of conflicts and of which records sync. Rejected: by far the most code, for an outcome the framework already provides.

Strava-sourced data:

- **Sync everything and reconcile duplicates (chosen).** One store, relationships between components and bikes stay relationships, and a device that never connects to Strava still has the rides.
- **Sync only app-owned data and re-import Strava data on each device.** No duplicate Strava records in CloudKit. Rejected: two configurations, with components referring to bikes by gear ID instead of a relationship, every device needing its own Strava connection and backfill, and a SwiftData forum report that a store without iCloud still synced when another configuration in the container had it.
- **Derive record IDs from Strava IDs.** Duplicates would share a `UUID`. Rejected: Core is Foundation only and has no name-based UUID, and CloudKit would still hold two records, so reconciliation would still be needed.
- **Import on one designated device.** Fewer duplicates. Rejected: losing that device stops imports until another is designated, and duplicates can still arrive during a change of device.

Conflicts:

- **Accept the framework's resolution (chosen).** Nothing to build.
- **Field-level merging.** Not available through SwiftData. It would mean `CKSyncEngine`, rejected above.

### Where this diverges from the reference project

- **Sync.** The reference project is one Mac and syncs nothing. This app runs on iPhone and iPad, so CloudKit mirroring syncs the whole store.
- **Uniqueness.** The reference project's SQLite constraints keep duplicates out. Here duplicates arrive from other devices, and Core reconciles them.
- **Kept:** the store in Application Support covered by device backup, permanent deletes, and failing fast when the store can't be opened.

## Consequences

- **Easier:** the same data on every device with no server; a lost or replaced device recovers from iCloud; no package and no sync code beyond reconciliation.
- **Harder:** every schema change after the first production deployment is additive, so mistakes in a shipped schema stay; each new schema version needs a CloudKit Console deployment before its TestFlight build; conflict handling can't be tuned; Core carries a reconciliation rule and its tests.
- **No independent copy.** A delete, or a bug that corrupts data, reaches every device, and a restored device backup can't be relied on to bring it back, because the restored store syncs with iCloud again. If that proves a problem, a later ADR adds an export file.
- **Verify on devices.** The cross-context checks ran on macOS without CloudKit. Before the first TestFlight build with sync, the persistence adapter is checked on two devices signed in to the same Apple Account (Apple advises devices, and warns that push notifications may be dropped or deferred): the adapter's context sees CloudKit's imported changes, reconciliation merges a bike imported on both devices, a record that arrives before its parent is skipped and then shown once the parent arrives, a signed-out device works locally, what signing out and back in with changes not yet uploaded does to the local data, and the store still opens when iCloud is unavailable or full. A forum report says a `ModelContainer` failed to open when the user's iCloud storage was full. If that holds on iOS 27.2, this ADR is revisited before sync reaches testers.
- **Project changes.** The iCloud and Background Modes capabilities, and the container, are added by the user in Xcode when the persistence module's first code lands. Builds with the iCloud capability need a development team in the Apple Developer Program, which TestFlight needs already (ADR-0002).
- **ADR-0007.** Its "`cloudKitDatabase: .none` until #13" becomes `.private(<container identifier>)` for the app's store. Its other rules are unchanged.
- **Strava (#3).** Each device connects separately, and whether Strava issues separate tokens to a second authorization is checked there. Disconnecting Strava on one device leaves other devices connected. If disconnecting deletes imported data, the delete syncs to every device, so #3's decision on whether imported data stays has to account for that.
- **Testing (#16).** Reconciliation is tested in Core with fakes, and the merge port method in the adapter against in-memory stores. CloudKit itself isn't unit-tested.
- **Error model (#18) and UI.** Whether and how the app shows iCloud sync status or errors is decided with them.
- **Agents.** `CLAUDE.md` records the sync rules.
