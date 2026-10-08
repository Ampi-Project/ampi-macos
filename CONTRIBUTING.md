# Contributing to Ampi for macOS

Build with `swift build` and run the existing checks with `swift test`. See [README.md](README.md) for local app packaging and [DEVELOPMENT.md](DEVELOPMENT.md) for the current milestone. Changes should keep this repository buildable without sibling projects.

## Required code documentation

Every handwritten Swift function and usable variable must have `///` documentation immediately before its declaration. This includes public and private methods, initializers, overrides, protocol requirements, stored/computed properties, constants, local variables, tests, and the package manifest. Document types and enum cases too.

Explain purpose and behavior rather than repeating the name. Include parameter meaning, return values, thrown errors, units, bounds, actor requirements, callbacks, and state changes where applicable. Optional bindings and loop variables need a comment above their statement; describe closure inputs at the closure or in the enclosing documentation. A property's documentation can cover its getter and setter together. Update documentation whenever the behavior changes.

```swift
/// Current playback offset in seconds, clamped to the loaded track's duration.
var position: Double = 0

/// Seeks within the loaded track, ignoring non-finite input.
/// - Parameter seconds: Requested offset in seconds, clamped to the valid track range.
func seek(to seconds: Double) {
    guard seconds.isFinite else { return }
    /// Bounded offset applied to the audio backend.
    let target = min(duration, max(0, seconds))
    backend.position = target
}
```

For languages that do not accept bare `///`, use their valid comment prefix: shell scripts use `# ///`. Generated SwiftPM files and build products are excluded; do not edit them to satisfy this rule.

Before submitting a change, inspect every new or changed declaration for documentation, run the relevant existing checks, and explain what changed and how it was verified. Run native playback/rendering checks when those behaviors change.
