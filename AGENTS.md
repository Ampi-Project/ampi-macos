# Ampi macOS contributor instructions

Read [CONTRIBUTING.md](CONTRIBUTING.md) before changing code.

Every handwritten Swift type, enum case, function, method, initializer, property, constant, and local variable must have meaningful `///` documentation. This applies to private code, overrides, protocol requirements, tests, and `Package.swift` as well as public APIs. Place documentation immediately before the declaration. Explain optional/loop bindings above their statements and closure inputs at the closure or in enclosing documentation.

Document parameter meaning, returned values, errors, units, bounds, actor requirements, callbacks, and state changes as relevant. Keep comments consistent with implementation. Generated SwiftPM sources and build artifacts are excluded. Shell code uses valid `# ///` comments.

Preserve the independent macOS build. After Swift changes, run `swift build` and `swift test`; run native smoke checks when playback or rendering behavior changes.
