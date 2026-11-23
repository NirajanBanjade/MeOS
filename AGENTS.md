# MeOS Agent Instructions

## Mission

Build the MeOS app described by `PRD.md` and the ordered specifications in
`features/`. Work autonomously from the earliest incomplete feature whose
dependencies are satisfied. Do not ask which feature to implement next when the
repository contains enough evidence to decide.

## Sources of truth

1. `PRD.md` defines product scope and release constraints.
2. `features/01-*.md` through `features/11-*.md` define the acceptance criteria.
3. The implementation and its passing tests are the evidence of what is actually
   complete.
4. Checked boxes in a feature file are a useful progress record, but they are not
   proof when the code or tests disagree.

When requirements conflict, follow the more specific feature specification while
preserving the PRD's product scope. Never weaken an acceptance criterion merely to
mark a feature complete.

## Required startup discovery

At the beginning of every task, discover progress again; do not rely on a status
remembered from an earlier agent or session.

1. Read this file, `PRD.md`, and the names of all files in `features/`.
2. Inspect the repository structure, implementation, tests, build configuration,
   and current working-tree changes before editing.
3. Review feature files in numeric order. For each feature, inspect its
   `Dependencies`, `Requirements`, `Test Requirements`, and `Complete When`
   sections.
4. Classify every feature as:
   - **Done**: every `Complete When` item is supported by implementation and the
     relevant automated checks pass.
   - **In progress**: some required implementation or tests exist, but at least
     one acceptance item is not yet verified.
   - **Not started**: no meaningful implementation exists beyond scaffolding or
     placeholders.
   - **Blocked**: an unmet dependency or external requirement prevents useful
     progress. Record the exact blocker.
5. Treat placeholder views, stubs, TODOs, disabled tests, and unchecked acceptance
   items as incomplete unless repository evidence proves otherwise.
6. Select the earliest numeric feature that is not Done and whose dependencies
   are Done. If it is In progress, resume its earliest unmet requirement. If no
   feature is eligible, work on the earliest unmet dependency instead.
7. Before changing code, state briefly which feature and requirement you selected
   and the evidence used to select it.

On the current documentation-only baseline, no feature is complete, so work starts
with `features/01-visual-design-and-app-shell.md`. This sentence is only an initial
observation; the discovery procedure above always overrides it as the repository
evolves.

## Implementation loop

For the selected feature:

1. Read the entire feature file and any dependency contracts it uses.
2. Break the next unmet requirement into the smallest coherent vertical slice that
   includes production code and proportionate tests.
3. Reuse shared models, components, fixtures, and design tokens. Do not create
   mission-specific duplicates of concepts that belong in Features 01-05.
4. Keep architectural boundaries from the specifications:
   - Pure Swift owns deterministic simulation and mission correctness.
   - SpriteKit renders the laboratory and event-driven simulation visuals.
   - SwiftUI owns navigation, panels, controls, charts, and results.
   - Rendering, animation timing, frame rate, and wall-clock time must never decide
     simulation or mission outcomes.
5. Implement all relevant validation, accessibility, offline behavior, lifecycle
   handling, and edge cases as part of the slice, not as optional cleanup.
6. Run the narrowest relevant tests first, then the broader available suite. Build
   the affected target whenever build tooling is available.
7. Compare the result against every affected requirement and test requirement.
   Do not claim completion based only on a successful compile.
8. Continue with the next unmet requirement while it is safe and within the user's
   request. Stop only for a real blocker, a required external decision, or a fully
   completed requested scope.

## Recording progress

Keep progress recoverable from the repository itself.

- Change a `Complete When` checkbox from `[ ]` to `[x]` only after implementation
  exists and the supporting checks pass.
- If an item is only partially implemented or cannot be verified, leave it
  unchecked.
- When useful, add a short indented evidence note immediately below a checked item,
  naming the relevant source/test files and verification command. Do not add vague
  percentage estimates.
- If tests cannot run because required tooling or a simulator is unavailable,
  report that limitation and leave test-dependent criteria unchecked.
- Do not create a separate progress file whose status can drift from the feature
  specifications, unless the user explicitly requests one.

At handoff, report:

- the feature and requirements completed;
- the verification commands and their results;
- remaining incomplete criteria or blockers; and
- the exact next eligible feature/requirement discovered from the repository.

## Project-wide constraints

- Target iPadOS landscape using Swift 6, SwiftUI, SpriteKit, Foundation, XCTest,
  and XCUITest with Xcode 27 or later.
- Remain fully offline. Add no network calls, analytics, authentication, cloud
  dependency, downloaded content, or third-party runtime package.
- Use bundled or Apple-provided assets and keep user-facing content in English.
- Preserve deterministic integer-millisecond simulation, stable IDs, stored seeds,
  and defined event tie-breaking.
- Status and gameplay cannot depend on color, sound, spatial input, or animation
  alone. Support VoiceOver, readable text, Reduce Motion, and direct accessible
  interaction paths.
- Preserve user-authored work and unrelated working-tree changes. Never discard or
  rewrite them to simplify implementation.
- Do not silently change constants, fixtures, budgets, timings, or victory rules
  specified in `features/`.

## Completion standard

A feature is complete only when all of its `Complete When` criteria are met, its
required tests pass, its dependencies remain passing, and no known placeholder or
contradictory behavior remains. After completing a feature, rerun startup discovery
and proceed to the next dependency-ready feature rather than assuming the next file
is ready.
