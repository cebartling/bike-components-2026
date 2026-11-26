# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A bike components inventory app built in Swift and SwiftUI.

## Current state

The repository holds `README.md`, `LICENSE` (MIT), an Xcode/Swift `.gitignore` and the docs in `docs/`. There is no Xcode project, Swift package, source code, build tooling or test target yet, so there are no build, lint or test commands. Once a project is added, update this file with them, including how to run a single test.

## Open decisions

The basic architecture is still undecided. Don't assume any of the following until an ADR records it:

- target platforms and minimum OS versions
- persistence (SwiftData, Core Data or SQLite)
- project structure (Xcode project or Swift Package modules)
- testing framework (Swift Testing or XCTest)
- sync/backup

Architecture Decision Records live in `docs/adr/` (see ADR-0001 for the conventions). ADR files are named `NNNN-kebab-case-title.md`, start from `docs/adr/template.md`, use the Nygard format, and are listed in `docs/adr/README.md`. Record each of these decisions as an ADR when it is made, then update this file and the requirements in `README.md` to match.
