# Architecture Decision Records

This directory holds the Architecture Decision Records (ADRs) for the project. [ADR-0001](0001-record-architecture-decisions.md) explains why we keep them and the conventions they follow.

## Index

| Number | Title | Status | Date |
| --- | --- | --- | --- |
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions | Accepted | 2026-11-26 |
| [0002](0002-target-platforms-and-minimum-os-versions.md) | Target platforms and minimum OS versions | Accepted | 2026-11-26 |

## Adding an ADR

1. Copy [`template.md`](template.md) to `NNNN-kebab-case-title.md`, using the next unused number.
2. Fill in the title, date, Context, Decision and Consequences. Set the status to `Proposed`.
3. Add a row to the index above.
4. Open a pull request. When the decision is agreed, set the status to `Accepted` in both the ADR and the index.
5. If the ADR replaces an earlier one, add `Supersedes ADR-NNNN` to the new ADR, and set the earlier ADR's status to `Superseded by ADR-NNNN` in both places.
6. If the decision settles something listed under "Open decisions" in [`CLAUDE.md`](../../CLAUDE.md), or changes requirements or build steps in the top-level [`README.md`](../../README.md), update those files in the same pull request.
