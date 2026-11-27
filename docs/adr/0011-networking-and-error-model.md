# 11. Networking and error model

- Status: Accepted
- Date: 2026-11-27

## Context

The Strava adapter (#3) is the app's first network code. It needs OAuth token refresh with rotating refresh tokens, rate-limit handling, resumable paging and tests against fixture JSON. Several accepted ADRs leave their error questions here: how port methods report errors and cancellation, and how back-off waits are tested (ADR-0005), how store errors are reported (ADR-0007), how errors become a model's display state (ADR-0008), how a duplicate gear ID is identified (ADR-0009), and how a failed launch is worded (ADR-0010).

Forces at play:

- **Strava's API.** From developers.strava.com (Nov 2026):
  - Access tokens last six hours. The refresh endpoint returns a new access token only when the current one "will expire in one hour (3,600 seconds) or less", and returns the existing one otherwise. A rotated refresh token invalidates the old one at once (#3).
  - Requests made with invalidated tokens get `401 Unauthorized`. What the refresh endpoint returns for a rejected refresh token isn't documented.
  - Rate limits are reported in `X-RateLimit-Limit`, `X-RateLimit-Usage`, `X-ReadRateLimit-Limit` and `X-ReadRateLimit-Usage`, each "two comma-separated values": the 15-minute window, then the day. Going over returns `429`. The 15-minute limits "reset at natural 15-minute intervals corresponding to 0, 15, 30 and 45 minutes after the hour", and the daily limit "resets at midnight UTC". No `Retry-After` header is documented.
  - The docs' samples show `"start_date": "2018-05-02T12:15:09Z"` beside `"start_date_local": "2018-05-02T05:15:09Z"` and `"utc_offset": -25200`: the local time is a wall-clock time sent with a `Z`.
- **Checked with Xcode 27.2 (Swift 6.4.2), in Swift 6 mode with ADR-0005's upcoming features, on macOS:**
  - An actor or a struct can implement a `Sendable` protocol requirement declared `async throws(SourceError)`, and the caller's `catch` gets a `SourceError`, not `any Error`.
  - Cancelling a task awaiting `URLSession.data(from:)` throws `URLError(.cancelled)` (`-999`), not `CancellationError`. `Task.sleep` throws `CancellationError`.
  - A task stored by an actor keeps running when a caller awaiting its value is cancelled. The caller resumes once the task finishes, with its own cancellation flag set.
  - `Task` accepts only `any Error` or `Never` as its failure type: `Task<Int, SourceError>` doesn't compile. A `Task { () async throws(E) -> Int in … }` closure crashes the compiler (signal 11 in IR generation) whenever `E` carries a value: an enum case with an associated value, `String` or `Int` alike, or a struct with a stored property. It compiles when `E` is an enum without associated values, and the same closure passed to an ordinary function compiles.
  - `JSONDecoder`'s `.iso8601` date strategy reads `2018-02-16T14:52:54Z` and `2018-02-16T14:52:54.123Z`.
  - With `.convertFromSnakeCase`, `gear_id` becomes the key `gearId`, so a property spelled `gearID: String?` decodes as `nil` without an error.
- **Swift's guidance.** SE-0413, which added typed throws, keeps untyped `throws` as the recommended default. Typed throws makes a change to the error type a source-breaking change for callers. Here every caller of Core is in the same repository, built together.
- **Audience.** The author and TestFlight testers (ADR-0002). A tester's screenshot is the bug report, so it should carry the cause.
- **Reference project.** investment-simulator-2026's [ADR-0012](https://github.com/cebartling/investment-simulator-2026/blob/main/docs/adr/0012-market-data-and-secrets.md) puts the Equibles client in its own adapter target with an injected [`HTTPTransport`](https://github.com/cebartling/investment-simulator-2026/blob/main/Sources/InvestmentSimulatorMarketData/HTTPTransport.swift): one `get(_:)` method, implemented by `URLSessionTransport(session: URLSession = .shared)`. Its ports use typed throws with error enums owned by Core (`QuoteError`, `MarketDataError`), and the adapter maps `401`, `404` and `429` to cases. It catches every transport error as `.unavailable("Couldn't reach Equibles.")`, so the cause is lost and a cancelled request becomes a failure. The adapter makes the Core enums `LocalizedError`, so the wording lives in the adapter. Presentation code switches over every case with no `default:`, which it adopted after a `default` let a new case compile without anyone deciding how to show it. It makes no automatic retries: the UI retries by loading again. Its tests use a `FakeTransport` that answers canned responses by path and query, and records the requests it was sent.

## Decision

We will use `URLSession` behind a transport seam inside the Strava adapter, and typed throws with error enums owned by Core at every port and use case, following the reference project, on the terms below.

### HTTP layer

- **No networking package.** The Strava adapter uses `URLSession`'s `async` API.
- **One transport seam, inside the adapter.** `BikeComponentsStrava` declares `HTTPTransport`, a `Sendable` protocol with one method, `send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)`, used for every method (OAuth needs `POST`). `URLSessionTransport` implements it and takes its `URLSession` through its initializer, with no default (ADR-0010). Both are `public`, because the composition root builds the transport and passes it to the adapter's initializer (ADR-0010). The transport throws whatever `URLSession` throws. Mapping happens above it.
- **An ephemeral session.** The composition root builds one `URLSession` with `URLSessionConfiguration.ephemeral`, so the URL loading system writes no responses, cookies or credentials to disk. Strava responses hold personal data, and requests carry tokens.
- **One request layer does the rest.** An internal client in the adapter builds each request from the API's base URL, adds `Authorization: Bearer` with a token from the token actor (ADR-0005), sends it through the transport, reads the rate-limit headers, maps the status, decodes the body and applies the retry rules below. The adapter's port implementations call the client and never build a `URLRequest` or touch the transport.
- **Work runs off the caller's actor.** The client's request function is `@concurrent`, so encoding, decoding and mapping never run on the main actor when a main-actor model calls a port (ADR-0005). The transport and client are stateless `Sendable` structs. The only mutable state is the tokens, in the token actor.
- **Token refresh lives in the token actor.** Before each request, the client asks the actor for an access token. The actor refreshes when the stored token expires within the next hour, Strava's own threshold for issuing a new one, and keeps the refresh in progress as a stored task (ADR-0005). The actor and the client take `now: @Sendable () -> Date` through their initializers. The composition root passes `{ Date.now }`.
- **A `401` gets one refresh and one retry.** A request sent with an access token and answered with `401` makes the actor refresh even if the stored expiry says the token is still valid, then the request is sent once more. A second `401`, or a refresh that Strava rejects, reports `authorizationRejected`. What happens to the rejected tokens is decided in #3.

### Error model

- **Typed throws wherever we own both sides.** Every port method that can fail, every use case that can fail and every Core rule that rejects input declares `throws(SomeError)`, where `SomeError` is an error enum owned by Core. Callers switch over every case. There is no `default:` in a switch over one of our error enums, so a new case doesn't compile until each caller decides what it means. Error enums are `Equatable`, so tests compare errors directly. Adding a case needs no ADR.
- **One enum per port family.** The initial ones:
  - `SourceError`, thrown by the Strava ports (`BikeSource`, `RideSource` and the connection port #3 names): `notConnected` (no tokens on this device), `authorizationRejected` (Strava refused the tokens or their scopes: reconnecting fixes it), `rateLimited(resetsAt: Date)`, `offline`, `unavailable(detail: String)`, `unreadableResponse(detail: String)` and `cancelled`. #3 adds the cases its ports need.
  - `RepositoryError`, thrown by the repository ports (ADR-0007): `gearIDTaken(heldBy: UUID)`, the case ADR-0009 asks to identify, naming the bike that holds the gear ID; `unreadableRecord(detail: String)`, ADR-0007's mapping failure; and `storeFailed(detail: String)` for any other store failure. Store calls don't stop for cancellation, so it has no `cancelled` case.
- **Use cases wrap the port errors they pass on.** A use case that calls more than one port family throws its own enum, with one case per port error it passes on, such as `.source(SourceError)` and `.repository(RepositoryError)`, plus its own rules' failures. It doesn't re-spell a port's cases. The import's enum also has its own `cancelled`, for the cancellation check between pages (ADR-0005).
- **Framework errors stop at the adapter.** An adapter catches every error a framework throws (`URLSession`, `JSONDecoder`, SwiftData, the Keychain, `Task.sleep`) and maps it to a case before its port method returns. No `URLError`, `DecodingError` or SwiftData error reaches Core or the UI, and typed throws on the port makes the compiler check that. The Strava client maps, in this order:

  | What happened | Case |
  | --- | --- |
  | The task is cancelled (`Task.isCancelled`), whatever was thrown | `cancelled` |
  | `URLError` `.notConnectedToInternet`, `.dataNotAllowed`, `.internationalRoamingOff` | `offline` |
  | `401`, after the refresh and retry | `authorizationRejected` |
  | `429` | `rateLimited(resetsAt:)` |
  | Any other `URLError`, `5xx` after its retries, or any other status | `unavailable(detail:)` |
  | A body that doesn't decode, or a value Core rejects when it is mapped | `unreadableResponse(detail:)` |

- **Details are for debugging, and never hold secrets.** A `detail` says what failed and where: the request's method and path, the HTTP status, the underlying error's description, or the type and coding path that didn't decode. It never holds request or response headers, bodies, tokens, the client secret or an authorization code. API request URLs carry no tokens, and the OAuth exchange sends its secrets in the body.
- **Models map, views word.** A model switches over the error's cases and turns each one into display state (ADR-0008): a state of the screen (`notConnected` shows the connect prompt, `authorizationRejected` the reconnect prompt, `rateLimited` when the limit resets), a failure the screen shows, or nothing for `cancelled`. Display state holds the Core error, or an enum of the screen's own made from it, never text. The wording lives in views: one function per Core error enum in `BikeComponentsUI`, outside `Presentation/`, so a case reads the same on every screen. Its strings follow #22. Nothing words an error through `localizedDescription` or `LocalizedError`.
- **Where failures appear.** A failed load shows the error in place of the content, with a retry that calls the load intent again. A failed action, such as a save, keeps the screen and shows the error in an alert. A case with a detail shows it under the wording as secondary text, so a tester's screenshot carries the cause.
- **A failed launch is the one untyped error the UI sees.** ADR-0010's `start` throws untyped errors, because they come from the adapters' opening functions, which the UI can't name. The persistence adapter's opening function throws an error of its own that is `CustomStringConvertible`, whose description names the store's path and the underlying error (ADR-0007). The root view shows a fixed sentence saying the app couldn't open its data, then that description.
- **No sync status yet.** The app shows no iCloud sync status or sync errors (ADR-0009): no port reports them, and adding one is a later decision.

### Codable

- **DTOs live in the adapter.** The Strava adapter decodes each response shape into an internal `Decodable` struct with only the fields it maps, and maps that to Core's values (ADR-0003). Unknown fields are ignored. Core has no DTOs.
- **Explicit `CodingKeys`, no key strategy.** Each DTO names its JSON keys in `CodingKeys`, so properties follow Swift's naming (`gearID`) and every JSON name is visible next to its property. `.convertFromSnakeCase` isn't used: it maps `gear_id` to `gearId`, and a property spelled `gearID` then silently decodes as `nil`.
- **Optional only where Strava omits or nulls a field,** such as an activity's `gear_id`. Every other field is required, so a missing one fails the decode and reports `unreadableResponse` instead of a made-up default. A misspelled key on an optional field still decodes as `nil`, so each fixture test checks that the optional fields it contains are read.
- **Open-ended values decode as `String`.** A value from a set Strava can extend, such as `sport_type`, isn't decoded into a Swift enum, so a new sport type doesn't fail a page. The mapping decides what a value means, for example the cycling filter (#3).
- **Dates use `.iso8601`.** Timestamps such as `start_date` decode as `Date`. `start_date_local` is never decoded as a `Date`, because its `Z` is wrong. If the app needs it, #3 decides how it is read.

### Retry, back-off and cancellation

- **Only the Strava client retries, and only briefly.** It retries a `GET` after a transient failure: a `URLError` other than the offline and cancelled ones, or a `500`, `502`, `503` or `504`. It makes at most two retries, after 1 second and then 2 seconds, because each retry counts against Strava's limits. Core, models and views never retry by themselves: the user retries by calling the intent again, and an import resumes from what it saved (ADR-0003).
- **Never retried, apart from the `401` refresh above:** a `POST` after a transient failure (token exchange, refresh, deauthorization: a repeat could act twice), a `429`, any other `4xx`, being offline, a body that doesn't decode, and cancellation. A refresh that fails leaves the stored tokens as they were, so the next request tries it again.
- **Rate limits are reported, not waited out.** On a `429`, the client throws `rateLimited(resetsAt:)`: the next midnight UTC if a daily usage value in the headers has reached its limit, otherwise the next quarter hour (0, 15, 30 or 45 minutes past). The adapter never sleeps until a reset: that could hold a port call until midnight UTC while the UI shows nothing. Whether an import then waits and resumes, or stops until the next sync, is #3's sync model. If it waits, the app-wide import model waits with an injected sleep, shows the reset time, and cancelling the import ends the wait. The client doesn't slow down before a `429`. #3 can add pacing from the usage headers if a backfill keeps hitting the limit.
- **Cancellation is the `cancelled` case.** That answers ADR-0005: a typed error can't carry `CancellationError`, so every error enum for work that can be cancelled has a `cancelled` case. The client checks for cancellation before each attempt, so a cancelled import sends no new request. Cancelling the task cancels the request in flight. A model treats every `cancelled` it gets, including a wrapped one such as `.source(.cancelled)`, as not an error: no message, and the screen goes back to its state before the intent (ADR-0005).
- **A refresh is never cancelled by its callers.** The refresh runs in the token actor's stored task, which a caller's cancellation doesn't reach, so a rotated refresh token is always saved (#3). A cancelled caller resumes when the refresh ends and then reports `cancelled`.
- **Sleeps are injected.** The Strava client takes `sleep: @Sendable (Duration) async throws -> Void` through its initializer, with no default (ADR-0010), and the import model takes one too if #3 has it wait. The composition root passes `{ try await Task.sleep(for: $0) }`. Tests pass a sleep that records the durations and returns at once, or throws `CancellationError` to cancel a wait. An error from the sleep is reported as `cancelled`.
- **`Task` closures don't declare typed throws.** `Task`'s failure type is `any Error` or `Never`, and a typed-throws `Task` closure crashes Swift 6.4.2 for any error type that carries a value. A task that runs typed-throwing work uses a closure that doesn't throw and catches inside it, keeping the outcome in state or returning a `Result`. SwiftUI's `.task` closures don't throw anyway.

### Tests

- **HTTP is faked at the transport.** The Strava adapter's tests use a fake `HTTPTransport` (a final class guarding its state with `Mutex`, ADR-0005) that answers by method, path and query and records every request, so tests can check paths, query items, the `Authorization` header and how many times a request was sent. They pass a fixed `now` and the recording sleep.
- **Fixtures are real responses, scrubbed.** Fixture JSON is captured from Strava and stripped of personal data (names, IDs, coordinates and map polylines). It lives in the Strava test target's resources, `Tests/BikeComponentsStravaTests/Fixtures/`, read through `Bundle.module`.
- **What they cover:** each row of the mapping table, the `401` refresh and retry, the reset time for both rate limits, retry counts and waits, cancellation during a request and during a wait, and decoding of every fixture.
- **Models are tested per case.** Fakes of Core's ports throw each case, and a model's tests cover each case it shows differently (ADR-0010's fakes, #16's framework).
- **`URLSessionTransport` has no unit test.** It is a few lines over `URLSession`, checked by #3's manual end-to-end run against Strava.

### Options considered

HTTP layer:

- **`URLSession` behind a transport seam in the adapter (chosen).** A handful of `GET`s and three `POST`s, which `URLSession`'s `async` API covers.
- **Alamofire or Get.** Request building, retries and interceptors we would configure anyway with our own rules, at the cost of a package under ADR-0006.
- **Swift OpenAPI Generator.** Typed endpoints from a spec, but three packages (generator, runtime and URLSession transport) and a generation step for about five endpoints.
- **A shared HTTP module.** There is one remote API. ADR-0003 keeps an adapter's seams inside it. A second client can extract one then.

Error model:

- **Typed throws with Core-owned enums (chosen).** Exhaustive handling, checked by the compiler, and framework errors can't leak through a port.
- **Untyped throws with error enums,** SE-0413's default. Rejected: models would cast and need a `default:`, a `URLError` or SwiftData error could reach the UI at run time, and a new case would compile unhandled.
- **`Result` return values.** The same exhaustiveness, but every call site unwraps by hand, and `try` no longer marks where a call can fail.
- **One app-wide error enum.** Fewer types, but every caller would handle cases its call can't produce.
- **Wording in `LocalizedError` conformances in the adapter,** as in the reference project. Rejected: how an error reads would depend on adapter code the UI can't import (ADR-0003), ADR-0008 keeps text out of models, and #22 decides localization in the UI.

Cancellation:

- **A `cancelled` case (chosen).** Works with typed throws, and an exhaustive switch makes every caller decide it.
- **`CancellationError`.** Swift's convention, but it needs untyped throws.
- **A returned outcome (`finished` or `cancelled`).** Fits the import, but not port calls.

Coding keys:

- **Explicit `CodingKeys` (chosen).** More lines, but nothing silent.
- **`.convertFromSnakeCase`.** Less code, but acronym properties silently decode as `nil`.
- **Properties spelled like the JSON (`gear_id`).** No keys, but snake case spreads through the mapping code.

Rate limits:

- **Report the reset time (chosen).** The UI can show it, and #3 decides whether to wait.
- **Wait inside the adapter.** Hides a wait of up to a day inside a port call.
- **Pace requests ahead of the limit.** Deferred to #3: a `429` must be handled either way.

Faking HTTP:

- **A transport fake (chosen).** Plain values in, recorded requests out, nothing global.
- **`URLProtocol` stubs.** Registered per class or session, shared by every test in the process, and slower to set up for no extra coverage of our code.
- **The live API.** Network in tests (ADR-0003 rules it out) and Strava's rate limits.

### Where this diverges from the reference project

- **Transport errors keep their cause.** The reference adapter turns every transport error into one message, including a cancelled request. Here cancellation and being offline are their own cases, and other failures keep a detail.
- **Wording lives in the UI,** not in `LocalizedError` conformances in the adapter.
- **Transport.** `send(_:)` for any method instead of `get(_:)`, because OAuth needs `POST`. The session is passed in with no default (ADR-0010), and it is ephemeral.
- **Retries.** The reference project has none. Here the Strava client retries `GET`s on transient failures, and refreshes and retries once on a `401`.
- **Kept:** typed throws on ports with enums owned by Core, the transport seam inside the adapter, a fake transport keyed by path and query that records requests, and switches that list every case.

## Consequences

- **Easier:** handling every error a call can produce, with the compiler pointing at each switch when a case is added; testing the retry, rate-limit and cancellation rules without waiting or touching the network; showing the same wording for a case everywhere; reading a tester's screenshot.
- **Harder:** every adapter writes its mapping to cases. Typed throws adds friction: closures passed to `map` and similar need `throws(SomeError)` spelled out, and tasks need the non-throwing closure above. Adding a case touches every switch over its enum, by design.
- **Answered for earlier ADRs.** ADR-0005: ports report errors with typed throws, cancellation is a `cancelled` case, the transport is a stateless `Sendable` struct behind a `@concurrent` client, and back-off waits are tested through an injected sleep. ADR-0007: store errors are `RepositoryError`. ADR-0008: models map cases to display state, and views word them. ADR-0009: `gearIDTaken(heldBy:)` identifies the duplicate gear ID case, and no sync status is shown yet. ADR-0010: a failed launch shows a fixed sentence and the opening error's description.
- **Strava (#3)** designs the connection port and adds `SourceError` cases its ports need. It checks what the refresh endpoint returns for a rejected refresh token, and what a request with a missing scope returns. It decides what happens to rejected tokens, whether an import waits out a rate limit, whether to pace requests, and how `start_date_local` is read if it is needed. Its client-secret ADR decides where the token exchange runs.
- **Testing (#16)** picks the framework these tests use. The fixtures belong to the Strava test target.
- **Logging (#20)** decides whether details are logged. They already hold no secrets.
- **Localization (#22)** decides how the views' error wording is localized.
- **Toolchain upgrades.** The `Task` crash is recorded so that nobody works around it again by hand. `Task`'s failure type rules out typed-throws tasks whether or not the crash is fixed.
- **Agents.** `CLAUDE.md` records these rules.
