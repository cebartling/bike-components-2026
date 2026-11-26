# 1. Record architecture decisions

- Status: Accepted
- Date: 2026-11-26

## Context

This project is at its first commit. Several early, hard-to-reverse choices are coming up: target platforms and minimum OS versions, persistence, project structure, concurrency model, testing approach and more. Both humans and AI agents work on the codebase. Without a written record, the reasons behind a choice get lost, and settled questions get reopened.

## Decision

We will record architecturally significant decisions as Architecture Decision Records (ADRs), in the format Michael Nygard described in [Documenting Architecture Decisions](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions).

- **Location.** ADRs live in `docs/adr/`.
- **File naming.** `NNNN-kebab-case-title.md`, where `NNNN` is a zero-padded, sequential number. Numbers are never reused.
- **Format.** Each ADR has a title, a status, a date, and Context, Decision and Consequences sections. New ADRs start from [`template.md`](template.md).
- **Index.** Every ADR is listed in [`README.md`](README.md) with its number, title, status and date.
- **Status lifecycle.**
  - `Proposed`: under discussion, not yet in force.
  - `Accepted`: in force.
  - `Deprecated`: no longer in force, with nothing replacing it.
  - `Superseded by ADR-NNNN`: replaced by a later ADR, which links back with `Supersedes ADR-NNNN`.
- **Immutability.** Once an ADR is accepted, we don't rewrite its decision. To change a decision, we write a new ADR that supersedes it and update the old ADR's status. Fixing typos and broken links is fine.
- **Scope.** We write an ADR for decisions that are expensive to reverse or that shape how the code is written, such as platforms, persistence, module structure, concurrency, state management, testing and dependencies. Routine implementation choices don't need one.

## Consequences

- Contributors and agents can learn why the project is the way it is by reading `docs/adr/`.
- Each significant decision costs a short write-up. Keeping ADRs small keeps that cost low.
- Decisions listed as open in `CLAUDE.md` stay open until an accepted ADR records them. When one is accepted, `CLAUDE.md` and `README.md` are updated to match.
- Superseded ADRs stay in the repository, so the history of a decision remains readable.
