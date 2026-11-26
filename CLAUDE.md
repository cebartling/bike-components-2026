# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A bike components inventory app built in Swift and SwiftUI.

## Reference project

Use [investment-simulator-2026](https://github.com/cebartling/investment-simulator-2026) (same author, MIT, checked out next to this repo at `../investment-simulator-2026`) for examples and code reuse. Before writing an ADR or a component, check whether it has already solved the same problem:

- ADRs in `docs/adr/`, e.g. hexagonal architecture, Swift 6 concurrency, `@Observable` presentation models and injection, Swift Testing, CI, release
- Code such as the `HTTPTransport` test seam, the Keychain-backed `CredentialStoring` port, the `justfile` and the GitHub Actions workflows

Reuse what fits, and record where this project diverges and why. It is a macOS-only, SwiftPM-only app, so its build, bundle, window and distribution choices may not carry over if this app targets iOS. Each ADR issue (#7 to #22) lists the relevant prior art.

## Current state

The repository holds `README.md`, `LICENSE` (MIT), an Xcode/Swift `.gitignore` and the docs in `docs/`. There is no Xcode project, Swift package, source code, build tooling or test target yet, so there are no build, lint or test commands. Once a project is added, update this file with them, including how to run a single test.

## Decided

- Platforms: iPhone and iPad, one universal iOS app target, minimum iOS/iPadOS 26. Not macOS, visionOS, watchOS or tvOS. Audience is the author plus TestFlight testers. UIKit only where SwiftUI has no equivalent, wrapped in the UI layer. (ADR-0002)

## Open decisions

Much of the architecture is still undecided. Don't assume any of the following until an ADR records it:

- persistence (SwiftData, Core Data or SQLite)
- project structure (Xcode project or Swift Package modules)
- testing framework (Swift Testing or XCTest)
- sync/backup

Architecture Decision Records live in `docs/adr/` (see ADR-0001 for the conventions). ADR files are named `NNNN-kebab-case-title.md`, start from `docs/adr/template.md`, use the Nygard format, and are listed in `docs/adr/README.md`. Record each of these decisions as an ADR when it is made, then update this file and the requirements in `README.md` to match.
