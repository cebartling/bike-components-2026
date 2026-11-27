# Architecture Decision Records

This directory holds the Architecture Decision Records (ADRs) for the project. [ADR-0001](0001-record-architecture-decisions.md) explains why we keep them and the conventions they follow.

## Index

| Number | Title | Status | Date |
| --- | --- | --- | --- |
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions | Accepted | 2026-11-26 |
| [0002](0002-target-platforms-and-minimum-os-versions.md) | Target platforms and minimum OS versions | Accepted | 2026-11-26 |
| [0003](0003-hexagonal-architecture.md) | Hexagonal architecture (ports and adapters) | Accepted | 2026-11-26 |
| [0004](0004-project-structure-and-module-boundaries.md) | Project structure and module boundaries | Accepted | 2026-11-26 |
| [0005](0005-concurrency-model.md) | Concurrency model | Accepted | 2026-11-26 |
| [0006](0006-third-party-dependency-policy.md) | Third-party dependency policy | Accepted | 2026-11-27 |
| [0007](0007-persistence-with-swiftdata.md) | Persistence with SwiftData | Accepted | 2026-11-27 |

## Adding an ADR

1. Copy [`template.md`](template.md) to `NNNN-kebab-case-title.md`, using the next unused number.
2. Fill in the title, date, Context, Decision and Consequences. Set the status to `Accepted`.
3. Add a row to the index above.
4. Open a pull request. Merging it is the agreement: the ADR takes effect, and becomes immutable, when the pull request merges. Until then, review changes go into the ADR in the same pull request. Use `Proposed` only for an ADR merged before it is agreed, for example to discuss it on `main`, and set it to `Accepted` in a later pull request.
5. If the ADR replaces an earlier one, add `Supersedes ADR-NNNN` to the new ADR, and set the earlier ADR's status to `Superseded by ADR-NNNN` in both places.
6. If the decision settles something listed under "Open decisions" in [`CLAUDE.md`](../../CLAUDE.md), or changes requirements or build steps in the top-level [`README.md`](../../README.md), update those files in the same pull request.
