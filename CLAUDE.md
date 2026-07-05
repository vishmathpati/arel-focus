# CLAUDE.md - Arel Focus

> Always loaded by every agent. Rules, product boundaries, and folder map.

## Coding Standards

**1. Think Before Coding** - State assumptions. Surface tradeoffs. Ask when unclear.
**2. Simplicity First** - Minimum code. No speculative features. No unnecessary abstractions.
**3. Surgical Changes** - Touch only what you must. Match existing style.
**4. Verify Before Closing** - Define done before touching code. Build/test native changes.

## What This Is

Arel Focus is a local-first macOS menu bar app that quietly records where attention went across apps and Chrome tabs, then helps review and assign that time to personal projects.

## Tech Stack

- SwiftPM macOS app targeting macOS 14+.
- SwiftUI for native dashboard, menu bar extra, settings, and review surfaces.
- AppKit, NSWorkspace, Accessibility, CoreGraphics, and ServiceManagement for desktop integration.
- Local JSON persistence in Application Support for v1.
- Chrome Manifest V3 extension plus native messaging host for active-tab tracking.

## What NOT To Do

- Do not add screenshots, screen recording, keylogging, or clipboard capture in v1.
- Do not make cloud AI mandatory for tracking or categorization.
- Do not build team surveillance, invoicing, or billing-first workflows into the core app.
- Do not treat Arel OS as mandatory source of truth yet; in-app projects come first.

## Context Files

- Read `agents/BRAND.md` before product or UX changes.
- Read `agents/BRIEF.md` before architecture, tracking, or privacy decisions.
- Read `agents/docs/INDEX.md` before changing tracking, Chrome bridge, persistence, or review behavior.
- Before UI work, read `agents/FUNDAMENTALS.md` and `agents/DESIGN.md`.

## Who Reads What

- **Human** reads `human/agenda.md` to know what to do next.
- **Cowork** reads `cowork/CLAUDE.md` for orchestration discipline.
- **Codex / Claude Code** read this file and the project canon in `agents/`.

## Folder Map

- `cowork/` - orchestration tier.
- `agents/` - project canon and agent-readable docs.
- `human/` - human-facing steering.
- `Sources/ArelFocus/` - native macOS app.
- `Sources/ArelFocusNativeBridge/` - Chrome native messaging host.
- `chrome-extension/` - unpacked Chrome extension for tab activity.
- `native-host/` - native messaging host manifest template and install notes.

## Pre-task Classification

Before any code change, classify the work:

1. NEW standalone feature
2. ADDITION to existing feature
3. UI CHANGE
4. BUG FIX

Check `agents/docs/INDEX.md` dependency entries before classifying.
