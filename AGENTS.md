# Loupe Project Instructions

These instructions apply to any coding agent (Claude, Codex, or others). `CLAUDE.md` only imports this file; edit this file, not that one.

## Product purpose

Loupe is a native macOS accessibility utility for inspecting and annotating interface elements. Changes must remain dependable in the real app, where macOS Accessibility permission, overlay behavior, signing, and coordinate conversion all affect what the user experiences.

## Project boundaries

- Open and build `Loupe.xcworkspace`; do not substitute the `.xcodeproj`.
- Keep the app shell in `Loupe/` and feature implementation in `LoupePackage/Sources/LoupeFeature/` consistent with the existing workspace and Swift package boundary.
- Types consumed by the app target must remain accessible across that package boundary (mark them `public`, with a `public init()`).
- Accessibility coordinates use a top-left origin while AppKit screen coordinates use a bottom-left origin. Preserve and verify the existing conversion whenever selection, positioning, or overlays are involved.
- Package dependencies belong in `LoupePackage/Package.swift`; build settings belong in the XCConfig files in `Config/` (Shared, Debug, Release, Tests) unless the established project structure requires otherwise.

## Working agreements

- Inspect Git status before working. Preserve unrelated changes and untracked build output; do not clean, delete, pull, or rewrite repository state unless asked.
- Treat signing, entitlements, App Sandbox, Accessibility permission, window level, and overlay event handling as sensitive boundaries. Inspect their current behavior before changing them, and do not broaden permissions merely to make a test pass.
- Keep the experience native and accessible. Avoid changes that interfere with other apps, trap input, or leave overlays active unexpectedly.
- Do not confuse a successful build with successful accessibility behavior. Permission prompts, first-run state, multi-display coordinates, and the actual overlay must be checked when relevant.
- Do not turn conversational promises into standing instructions or memory automatically. Propose additions to this file and make them only when the user approves.

## Verification and handoff

Choose verification for the affected behavior. Documentation-only changes do not require a build or launch. Changes to selection, overlays, coordinates, permissions, or interaction require relevant real-app checks as well as appropriate automated checks.

- Build: `xcodebuild -workspace Loupe.xcworkspace -scheme Loupe -configuration Debug build`
- Test (unit + UI): `xcodebuild -workspace Loupe.xcworkspace -scheme Loupe -configuration Debug test`
- Package unit tests only: `swift test --package-path LoupePackage`
- UI tests only: `xcodebuild -workspace Loupe.xcworkspace -scheme Loupe -only-testing:LoupeUITests test`
- Clean build (only when asked, per the working agreements): `xcodebuild -workspace Loupe.xcworkspace -scheme Loupe clean`
- For visible or interaction changes, verify the running app with the relevant Accessibility permission state and on the affected display arrangement.
- Report user impact, checks performed, permission or signing assumptions, and anything that still requires a real-device or packaged-app check.

## Architecture

Workspace + Swift package: `Loupe.xcodeproj` is a minimal app shell (`Loupe/LoupeApp.swift` is the entry point) that imports the `LoupeFeature` package, where all feature code lives.

`LoupePackage/Sources/LoupeFeature/` is organized by folder:
- `Models/`: value types such as `AXElementInfo` (extracted accessibility metadata: role, identifier, title, value, frame, hierarchy path, plus `searchPatterns` that help AI agents locate an element in code), annotations, selection regions, and settings.
- `Services/`: `AccessibilityInspector` (wraps the macOS Accessibility APIs: permission checks, app enumeration, element inspection at screen coordinates), app coordination and lifecycle, feedback output generation, and rich clipboard export.
- `Views/`: the inspection overlay (`OverlayWindowController`, a transparent borderless window floating above the target app that tracks position and draws highlight rectangles around hovered elements), floating toolbar, annotation popover and list, onboarding, and settings.
- `Theme/`: shared colors.

Coordinate conversion between the Accessibility API and AppKit lives in `OverlayWindowController` and `Views/NSScreen+CoordinateHelpers.swift`.

App Sandbox is currently disabled in `Config/Loupe.entitlements` to allow Accessibility API access.

## Reference docs

`docs/` holds the brand guidelines, release plan, past handoff notes, and demo assets.

## Platform

- macOS 14.0+ (Sonoma)
- Swift 6.1
- Swift Testing for unit tests, XCUITest for UI tests
