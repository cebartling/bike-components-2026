# 7. Persistence with SwiftData

- Status: Accepted
- Date: 2026-11-27

## Context

The app keeps bikes and rides imported from Strava (#3, #4), and the data it owns: components, installations and service records. Users put real effort into recording components and service history, so losing it is the worst outcome the app can have (#13). The store is the decision hardest to reverse: changing it later means migrating every user's data.

ADR-0003 already settles the boundary. Core's domain types are plain `Sendable` value types. `@Model` classes, managed objects and SQLite records live only in the persistence adapter, `BikeComponentsPersistence` (ADR-0004), which maps them to Core types. Core enforces that a Strava gear ID is unique across bikes, and left open whether the store enforces it too. ADR-0005 makes ports `Sendable` and `async`, says adapters never block their caller, and leaves the persistence adapter's isolation to this ADR.

Forces at play:

- **The data is a small relational library.** One athlete: a handful of bikes, tens of components, and up to a few thousand rides. A bike has rides and installed components, and a component has service records. Imports upsert bikes and rides by their Strava IDs.
- **The app is universal** (ADR-0002). A rider with an iPhone and an iPad will expect the same data on both. Sync is decided in #13, but the store decides which sync options are practical. Apple's CloudKit mirroring, built into SwiftData and Core Data, requires every attribute to be optional or have a default, every relationship to be optional with an inverse, no unique constraints and no `.deny` delete rules.
- **The SwiftData convenience is already gone.** ADR-0003 keeps `@Model` objects out of the UI, so views can't use `@Query`, and the adapter maps either way.
- **The dependency policy** (ADR-0006) admits a package only when the SDK can't do the job.
- **SwiftData behaviour, checked with Xcode 27.2 and Swift 6.4.2.** A scratch package with our Swift settings (Swift 6 mode, the three upcoming features of ADR-0005, a nonisolated module) builds for the iOS Simulator with `@Model` classes, a `@ModelActor` and an actor holding a `ModelContext`, with no warnings and no concurrency escapes. `ModelContainer`, `ModelConfiguration` and `PersistentIdentifier` are `Sendable`. No iOS Simulator runtime was installed, so the runtime checks ran on macOS 27.2 with the same SwiftData:
  - A `@ModelActor`'s executor ran each job synchronously on the thread that hopped to it, on its context's queue. Called from the main actor, its methods ran on the main thread, five out of five calls, wherever the actor and its container were created. Called from a nonisolated task, they ran off the main thread. A `@concurrent` function between the two didn't reliably help: one that only forwards the call skipped the hop off the main actor and ran on the main thread, and one that did work before the call ran off the main thread in a debug build but on it in a release build. A plain actor that creates its own `ModelContext(container)` in its initializer ran off the main thread from both. With a file-backed store and the context created on the main thread, 200 concurrent insert-and-save calls into it triggered no Core Data concurrency assertion (`-com.apple.CoreData.ConcurrencyDebug 1`) in debug or release builds, and no Thread Sanitizer report. The assertions are the check that matters: the actor serializes its own calls, so Thread Sanitizer can't see a misuse of the context's queue.
  - Inserting a second object with the same `@Attribute(.unique)` value didn't fail: after both saves there was one object, holding the second object's values.
  - A `ModelConfiguration`'s `cloudKitDatabase` defaults to `.automatic`. Apple's documentation says it then mirrors to CloudKit when the app has the iCloud entitlement.
  - A `ModelContext` created by a `@ModelActor` has `autosaveEnabled` set to `false`.
  - Two in-memory containers don't share data.
- **Reference project.** investment-simulator-2026 first stored versioned JSON documents ([ADR-0005](https://github.com/cebartling/investment-simulator-2026/blob/main/docs/adr/0005-scenario-persistence-and-document-based-app.md)), then replaced them with one app-wide SQLite database through GRDB ([ADR-0021](https://github.com/cebartling/investment-simulator-2026/blob/main/docs/adr/0021-sqlite-library-replaces-document-persistence.md)). It rejected SwiftData because its model types would pull persistence into the domain or force a mapping layer, because it hides the stored shape, and because a `ModelContext` must not outlive its `ModelContainer`. If its database can't be opened or migrated, the app stops with a clear message and never silently recreates it. It is a single-user Mac app with no sync.

## Decision

We will store the app's data in one app-wide SwiftData store, behind Core's repository ports, in `BikeComponentsPersistence` only, on the terms below.

### Store

- **One SwiftData store** in the app's Application Support directory, at an explicit file name, `BikeComponents.store`, so its path doesn't depend on SwiftData's default. iOS backs that directory up with the device.
- **CloudKit stays off until #13.** Every `ModelConfiguration` passes `cloudKitDatabase: .none`, so adding an iCloud entitlement for another reason can't turn sync on.
- **Only the persistence module imports SwiftData.** Not Core (ADR-0003), not `BikeComponentsUI`, not the app target. The module's public API opens the store and returns the adapter, so the composition root never sees a `ModelContainer`.
- **Fail fast.** If the store can't be opened or migrated, opening it throws an error naming the path and the underlying error, and the app shows that message instead of continuing. The adapter never deletes or recreates a store it can't open, and never falls back to an empty or in-memory store.

### Persistence types and mapping

- **`@Model` classes are internal to the adapter** and never leave it (ADR-0003). Port methods take and return Core value types.
- **Identity is Core's.** Each stored record keeps the domain value's `UUID` as an attribute, and the adapter finds records by it. `persistentModelID` stays inside the adapter.
- **The schema follows CloudKit's rules from the start,** so #13 can choose CloudKit mirroring without a schema migration: every attribute optional or defaulted, every relationship optional with an explicit inverse, no unique constraints and no `.deny` delete rules.
- **Mapping fails loudly.** A stored record that can't become a valid Core value, such as a bike with an empty gear ID left by a default, makes the read throw a descriptive error. The adapter doesn't invent or drop data to make it fit.

### Uniqueness and upserts

- **Core enforces uniqueness** (ADR-0003). The store has no `@Attribute(.unique)` or `#Unique`: CloudKit rejects them, and a duplicate insert silently overwrites the earlier object (see Context), which would hide a Core bug instead of catching it.
- **Writes upsert by the domain ID.** Saving a value fetches the record with its `UUID`, updates it if found and inserts it otherwise. Core's import reconciles Strava gear and activity IDs with what it loaded through the ports, and then saves.
- **One import at a time.** Core's check and its save are separate port calls, so two overlapping imports could each insert a bike for the same new gear ID. Only one import runs at a time. Whoever starts imports guarantees that, decided with #3's sync model.
- **The adapter checks gear IDs too.** Saving a bike also fetches by its gear ID in the same actor call, and throws a descriptive error if a bike with another `UUID` holds it. This is a fetch, not a store constraint, so CloudKit stays open. ADR-0003 allows the store to enforce uniqueness as well as Core.

### Threading

- **The adapter is one actor that owns its context.** It creates a `ModelContext` from the container in its initializer and keeps both the container and the context, so the context never outlives the container. It is the only code that touches either. It is a plain actor, not a `@ModelActor`, because a `@ModelActor` ran on the main thread when called from the main actor (see Context), which would break ADR-0005's rule that adapters never block their caller.
- **One actor implements every repository port** (`BikeRepository`, `RideRepository` and any added later), so all reads and writes go through one context, one at a time. Its methods are synchronous inside the actor, and callers reach them with `await` through the `Sendable`, `async` ports.
- **Every write saves before it returns.** Autosave is off, and each port method that writes calls `save()` once. A port call that returns has written to disk, which is what an interrupted import relies on to resume (ADR-0003, ADR-0005). A page of rides is one call and one save.
- **No undo manager.** The context's `undoManager` stays `nil`.

### Migrations

- **Versioned from the first schema.** The schema is a `VersionedSchema` (`SchemaV1`) with a `SchemaMigrationPlan` from the start, so the first change adds a version instead of retrofitting one.
- **Lightweight by default.** A stage is lightweight unless data has to be transformed. Then it is a custom stage.
- **Shipped versions are frozen.** A schema version that has reached a TestFlight build stays in the plan unchanged. Until then, the current version may be edited in place.
- **Every stage is tested.** The test writes a store at the old version to a file in a temporary directory, reopens it with the current plan, and checks the Core values it reads back. These are the only persistence tests that touch disk, because an in-memory store disappears with its container. All other adapter tests use an in-memory configuration, with a container per test.

### Options considered

- **SwiftData (chosen).** First-party, so no package or dependency check. Its CloudKit mirroring keeps multi-device sync between iPhone and iPad within reach for #13, and following CloudKit's schema rules now costs only defaults and optional relationships inside the adapter. Its model types stay in the adapter, as with any store (ADR-0003). It costs a `ModelActor` we can't use as designed, migrations that are less transparent than SQL, and a framework that is younger and changes with each OS release.
- **GRDB on SQLite.** The reference project's choice, with code to reuse: an explicit schema, `UNIQUE` indexes, `ON CONFLICT` upserts, readable migrations and `Sendable` database types. Rejected: SwiftData can do this job, so ADR-0006's default stance says no package. Sync across devices would mean writing CloudKit sync ourselves with `CKSyncEngine`, the most work of any option for the outcome #13 most likely wants.
- **Core Data.** Mature, with `NSPersistentCloudKitContainer` and well-known migrations. Rejected: the same CloudKit path as SwiftData, with more code. Managed objects aren't `Sendable`, so every call goes through `perform`, and the model lives in an `.xcdatamodeld` that is edited in Xcode, not in code.
- **System SQLite C API.** No package, full control. Rejected: we would write connection handling, statements, migrations and concurrency ourselves, and still have no sync.
- **Codable files (JSON).** Simple and readable. Rejected: the data is relational and edited a record at a time, every change rewrites the file, and the reference project moved off documents to a database for the same kind of library.

Store isolation:

- **A plain actor owning a `ModelContext` (chosen).** Measured off the main thread from any caller, with no Core Data concurrency assertion under concurrent writes. It isn't the pattern Apple's documentation shows, so it has to be checked on iOS (see Consequences).
- **A `@ModelActor`.** Apple's pattern, and less code. Rejected: it ran on the main thread when called from the main actor, and a `@concurrent` function in between didn't reliably move it.
- **A separate context per call.** No shared state, but each call pays for a new context, and two concurrent writes could interleave their fetch-then-insert upserts and create duplicates.

### Where this diverges from the reference project

- **Store.** The reference project uses GRDB. Here SwiftData wins because the SDK can do the job (ADR-0006) and because this app runs on two kinds of device, where CloudKit sync matters. The reference project is one Mac with no sync. Its objection that SwiftData pulls persistence into the domain doesn't apply here: ADR-0003 maps at the adapter, as it does with GRDB.
- **Uniqueness.** The reference project can rely on SQLite constraints. Here the store has none, to keep CloudKit open. Core enforces uniqueness, and the adapter checks gear IDs with a fetch when it saves a bike.
- **Kept:** one app-wide store, the store's types only in the persistence adapter, and failing fast without recreating the store.
- **ADR-0005's example.** ADR-0005 named SwiftData's `ModelActor` as an example of the adapter's isolation. This ADR uses a plain actor instead, for the reason above.

## Consequences

- **Easier:** no package to pin or check at each toolchain move; a direct path to CloudKit sync for #13; in-memory adapter tests that touch no disk.
- **Harder:** every schema attribute needs a default or an optional, and the mapping must reject records that don't make valid Core values. Upserts are fetch-then-write code in the adapter instead of a store constraint. SwiftData migrations hide the SQL, so their tests carry more weight. SwiftData changes with each OS release, and the toolchain moves with each one (ADR-0002).
- **Verify on iOS.** The thread checks ran on macOS. The persistence adapter's first tests run on the iOS Simulator and include one that a port method called from the main actor runs off the main thread. The adapter's tests run with Core Data's concurrency assertions on (`com.apple.CoreData.ConcurrencyDebug` set to 1), so a misused context fails them. How the setting reaches the package's generated test scheme is worked out with #16. If either check fails, this ADR's threading decision is revisited before more adapter code is written.
- **Sync and backup (#13)** chooses between CloudKit mirroring, device backup only, or something else. With CloudKit, duplicates can also arrive through merges from another device, so #13 decides how they are reconciled. CloudKit schemas can only grow once deployed, which constrains later migrations.
- **Testing (#16)** decides the framework. This ADR settles that adapter tests use in-memory stores, one container per test, and that migration tests use temporary files.
- **Error model (#18)** decides how port methods report store errors. This ADR requires only that they are descriptive and never swallowed.
- **Skeleton.** `BikeComponentsPersistence` and its test target are created with the first adapter code, and import SwiftData. The app target opens the store through the module's public API and shows the error if that fails.
- **Agents.** `CLAUDE.md` records the persistence rules.
