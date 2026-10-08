# Third-party notices

Ampi's original code remains GPL-3.0-only. ZIPFoundation 0.9.20 is a statically linked Swift Package Manager dependency used for read-only, in-memory ZIP/DEFLATE inspection. Its original MIT license is preserved in [licenses/ZIPFoundation.txt](licenses/ZIPFoundation.txt) and copied into the packaged app's resource directory. The exact version and resolved revision are tracked by the package manifest and `Package.resolved`.

Upstream source and documentation: [ZIPFoundation](https://github.com/weichsel/ZIPFoundation/tree/0.9.20). On macOS it uses Apple's Compression framework; Ampi does not invoke external archive executables or install a shared cross-platform runtime.

Classic fixtures are original Ampi geometric artwork under GPL-3.0-only; see their [provenance](Tests/AmpiCoreTests/Fixtures/README.md). Locally inspected user skins retain their existing copyright and license. Previewing them does not upload, redistribute, or install them.
