// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Darwin
import ImageIO
import ZIPFoundation

/// Validated Classic assets for inspection only; this is not an activated playback skin.
public struct ClassicSkinPackage: Sendable {
    /// Source filename used for the preview title; not inferred authorship metadata.
    public let name: String
    /// Normalized relative directory containing the unique main.bmp asset.
    public let root: String
    /// Case-normalized filenames and original bytes from the selected skin directory.
    public let assets: [String: Data]
    /// Informational diagnostics describing incomplete or unsupported presentation features.
    public let warnings: [String]
    /// Validated 275-by-116-pixel Classic main-window background.
    public var mainBitmap: Data { assets["main.bmp"]! }
    /// Sorted filenames displayed in the inspection report.
    public var assetNames: [String] { assets.keys.sorted() }

    /// Maximum archive size in bytes, limiting the initial in-memory ZIP read.
    public static let maximumArchiveBytes = 16 * 1024 * 1024
    /// Maximum uncompressed bytes per file, checked against metadata and actual output.
    public static let maximumFileBytes = 8 * 1024 * 1024
    /// Maximum total uncompressed bytes across the entire package or folder.
    public static let maximumExpandedBytes = 64 * 1024 * 1024
    /// Maximum directory/file entries inspected, including ignored auxiliary resources.
    public static let maximumEntries = 512

    /// Inspects a local ZIP/.wsz archive or extracted folder without installing or executing it.
    /// - Parameter url: Regular archive file or extracted skin directory.
    /// - Returns: Original asset bytes and an explicitly partial compatibility report.
    /// - Throws: File-access, archive, bitmap-validation, or cancellation errors.
    public static func load(_ url: URL) throws -> ClassicSkinPackage {
        guard url.isFileURL else { throw ThemeError.invalid("Choose a local skin package.") }
        /// Source type checked before selecting archive or folder inspection.
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw ThemeError.invalid("Skin input cannot be a symbolic link.") }
        /// Validated normalized paths and bounded payloads read from the input.
        let files: [String: Data]
        if values.isDirectory == true { files = try readFolder(url) }
        else if values.isRegularFile == true { files = try readArchive(readFile(url, limit: maximumArchiveBytes)) }
        else { throw ThemeError.invalid("Choose a regular ZIP/.wsz file or skin folder.") }
        return try inspect(files, name: url.deletingPathExtension().lastPathComponent)
    }

    /// Validates a bounded in-memory ZIP payload, useful for reproducible conformance tests.
    /// - Throws: An unsupported ZIP profile, path/resource-limit, checksum, or bitmap error.
    public static func decode(_ data: Data, name: String = "Classic skin") throws -> ClassicSkinPackage {
        try inspect(readArchive(data), name: name)
    }

    /// Normalizes legacy backslashes/casing while rejecting absolute and ambiguous paths.
    /// - Parameter path: Original archive entry path or relative folder path.
    /// - Throws: `ThemeError` for traversal, drive paths, empty components, or excessive depth.
    static func normalize(_ path: String) throws -> String {
        /// Slash-normalized relative path; a trailing slash is permitted for directory entries.
        let slashed = path.replacingOccurrences(of: "\\", with: "/")
        /// Component sequence after removing at most one directory suffix.
        let components = (slashed.hasSuffix("/") ? String(slashed.dropLast()) : slashed).split(separator: "/", omittingEmptySubsequences: false)
        guard !slashed.hasPrefix("/"), !slashed.contains(":"), !slashed.contains("\0"), slashed.count <= 1024,
              (1...16).contains(components.count),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ThemeError.invalid("Unsafe or ambiguous skin path: \(path)")
        }
        return components.joined(separator: "/").precomposedStringWithCanonicalMapping.lowercased()
    }

    /// Reads at most the limit plus one byte, avoiding unbounded reads if file metadata changes.
    private static func readFile(_ url: URL, limit: Int) throws -> Data {
        /// Native descriptor refuses symlinks and avoids blocking on a raced-in special file.
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            /// File-system byte path accepted only when Foundation supplies a representation.
            guard let path else { return Int32(-1) }
            return Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        }
        guard descriptor >= 0 else { throw ThemeError.invalid("Cannot read skin file without following a symbolic link.") }
        /// Read-only handle closed on both success and failure.
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        /// Opened object's actual type is checked again after acquiring the descriptor.
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG else {
            throw ThemeError.invalid("Skin assets must be regular files.")
        }
        /// Bounded payload, including one sentinel byte to detect an oversized file.
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw ThemeError.invalid("Skin file exceeds the \(limit / 1024) KiB limit.") }
        return data
    }

    /// Reads ZIP entries into memory only, verifying paths, CRCs, and actual expansion limits.
    private static func readArchive(_ data: Data) throws -> [String: Data] {
        guard data.count <= maximumArchiveBytes else { throw ThemeError.invalid("Skin archives must be at most 16 MiB.") }
        /// Declared entry count from a fully checked ZIP32 central directory.
        let expectedCount = try ClassicZIPPreflight.validate(data)
        /// Read-only parser pinned to the audited ZIPFoundation version.
        let archive = try Archive(data: data, accessMode: .read)
        /// Unique normalized paths, including directories, preventing case collisions.
        var paths = Set<String>()
        /// Bounded file contents; no archive entry is written to the filesystem.
        var files: [String: Data] = [:]
        /// Actual bytes emitted by all decompression consumers.
        var total = 0
        /// Entries actually yielded, compared with metadata to detect silent parser termination.
        var count = 0
        /// Each parsed entry is inspected even when unrelated to the selected skin root.
        for entry in archive {
            try Task.checkCancellation()
            count += 1
            guard count <= maximumEntries, entry.type != .symlink else { throw ThemeError.invalid("Too many skin entries or a symbolic link was found.") }
            /// Canonical entry path used only as a dictionary key.
            let path = try normalize(entry.path)
            guard paths.insert(path).inserted else { throw ThemeError.invalid("Duplicate skin path: \(path)") }
            if entry.type == .directory { continue }
            guard entry.uncompressedSize <= maximumFileBytes else { throw ThemeError.invalid("Skin asset is too large: \(path)") }
            /// Current entry output, bounded before each appended chunk.
            var payload = Data()
            /// CRC computed from actual output; chunk is the bounded decompressor output block.
            let checksum = try archive.extract(entry, bufferSize: 32 * 1024) { chunk in
                try Task.checkCancellation()
                guard chunk.count <= maximumFileBytes - payload.count,
                      chunk.count <= maximumExpandedBytes - total else { throw ThemeError.invalid("Skin expansion exceeds resource limits.") }
                payload.append(chunk)
                total += chunk.count
            }
            guard payload.count == entry.uncompressedSize, checksum == entry.checksum else {
                throw ThemeError.invalid("Corrupt skin asset or checksum mismatch: \(path)")
            }
            files[path] = payload
        }
        guard count == expectedCount else { throw ThemeError.invalid("The ZIP directory contains an unreadable entry.") }
        return files
    }

    /// Recursively inspects regular files in an extracted folder; symlinks are never followed.
    private static func readFolder(_ url: URL) throws -> [String: Data] {
        /// File properties required to reject symlinks and special filesystem entries.
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        /// Enumeration failure captured so unreadable subdirectories cannot be silently skipped.
        var enumerationError: Error?
        /// Enumerator's error argument records a failure before traversal stops.
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, errorHandler: { _, error in
            enumerationError = error; return false
        }) else { throw ThemeError.invalid("Cannot inspect this skin folder.") }
        /// Unique normalized entry paths, including directory entries.
        var paths = Set<String>()
        /// Bounded regular-file contents collected from the folder.
        var files: [String: Data] = [:]
        /// Actual aggregate bytes retained from the folder.
        var total = 0
        /// Actual filesystem entries inspected, including directories.
        var count = 0
        /// Each local entry must remain a directory or regular file without symbolic links.
        for case let file as URL in enumerator {
            try Task.checkCancellation()
            count += 1
            guard count <= maximumEntries else { throw ThemeError.invalid("Skin folders may contain at most 512 entries.") }
            /// Current entry type checked before reading any data.
            let values = try file.resourceValues(forKeys: Set(keys))
            guard values.isSymbolicLink != true else { throw ThemeError.invalid("Skin folders cannot contain symbolic links.") }
            /// Relative path derived from URL components rather than a string prefix.
            let relative = file.pathComponents.dropFirst(url.pathComponents.count).joined(separator: "/")
            /// Canonical path shared with archive-input validation.
            let path = try normalize(relative)
            guard paths.insert(path).inserted else { throw ThemeError.invalid("Duplicate skin path: \(path)") }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true else { throw ThemeError.invalid("Skin folders may contain only regular files and directories.") }
            /// File payload read with the same per-entry cap used by ZIP input.
            let payload = try readFile(file, limit: maximumFileBytes)
            guard payload.count <= maximumExpandedBytes - total else { throw ThemeError.invalid("Skin folder exceeds 64 MiB.") }
            total += payload.count
            files[path] = payload
        }
        /// Deferred filesystem error, if traversal encountered an unreadable directory.
        if let enumerationError { throw enumerationError }
        return files
    }

    /// Selects one Classic root, validates bitmap decoding, and reports optional missing assets.
    private static func inspect(_ files: [String: Data], name: String) throws -> ClassicSkinPackage {
        guard !files.keys.contains(where: { ($0 as NSString).lastPathComponent == "skin.xml" }) else {
            throw ThemeError.invalid("Modern XML/MAKI skins are not supported by this Classic inspector.")
        }
        /// Candidate main-window backgrounds; ambiguity is rejected rather than guessed.
        let mains = files.keys.filter { ($0 as NSString).lastPathComponent == "main.bmp" }
        guard mains.count == 1 else { throw ThemeError.invalid("A Classic preview needs exactly one main.bmp file.") }
        /// Directory containing the unique Classic main background, possibly the archive root.
        let root = (mains[0] as NSString).deletingLastPathComponent
        /// Path and data identify each file; only siblings of main.bmp enter the preview profile.
        let assets = Dictionary(uniqueKeysWithValues: files.compactMap { path, data -> (String, Data)? in
            guard (path as NSString).deletingLastPathComponent == root else { return nil }
            return ((path as NSString).lastPathComponent, data)
        })
        /// Every supplied bitmap beside main.bmp must decode within the configured limits.
        for (filename, data) in assets where filename.hasSuffix(".bmp") {
            try Task.checkCancellation()
            try validateBitmap(data, name: filename)
        }
        /// Common sprites absent from this package, reported without blocking background inspection.
        let missing = ["cbuttons.bmp", "titlebar.bmp", "text.bmp", "volume.bmp", "posbar.bmp", "pledit.bmp", "eqmain.bmp"].filter { assets[$0] == nil }
        /// Honest compatibility diagnostics; a decoded background does not mean a usable full skin.
        var warnings = ["Preview only: the main.bmp background is shown; sprites, playlist, equalizer, and skin controls are not active."]
        if !missing.isEmpty { warnings.append("Missing common assets: " + missing.joined(separator: ", ") + ".") }
        return ClassicSkinPackage(name: name, root: root, assets: assets, warnings: warnings)
    }

    /// Checks BMP identity, dimensions, pixel budget, and actual decoding before preview creation.
    private static func validateBitmap(_ data: Data, name: String) throws {
        try autoreleasepool {
            /// Image source parsed without caching full raster data before dimensions are checked.
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  CGImageSourceGetType(source) as String? == "com.microsoft.bmp",
                  /// Bitmap metadata checked before requesting full raster decoding.
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  /// Declared raster width in pixels, bounded before allocation.
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  /// Declared raster height in pixels, bounded alongside the pixel budget.
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  (1...4096).contains(width), (1...4096).contains(height), width * height <= 4_194_304 else {
                throw ThemeError.invalid("Invalid or oversized Classic bitmap: \(name)")
            }
            guard name != "main.bmp" || (width == 275 && height == 116) else {
                throw ThemeError.invalid("Classic main.bmp must be 275 × 116 pixels.")
            }
            guard CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
                throw ThemeError.invalid("Classic bitmap could not be decoded: \(name)")
            }
        }
    }
}
