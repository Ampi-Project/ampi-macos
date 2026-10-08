// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XCTest
import ZIPFoundation
@testable import AmpiCore

/// Verifies Classic input boundaries using original artwork and adversarial in-memory ZIPs.
final class ClassicSkinPackageTests: XCTestCase {
    /// Resolves a checked-in original fixture without depending on sibling repositories.
    private func fixture(_ path: String) throws -> URL {
        try XCTUnwrap(Bundle.module.resourceURL).appendingPathComponent("Fixtures").appendingPathComponent(path)
    }

    /// Loads the original BMP bytes reused by valid and malformed package fixtures.
    private func mainBitmap() throws -> Data { try Data(contentsOf: fixture("OriginalClassic/main.bmp")) }

    /// Creates a ZIP wholly in memory; provider position/size select each requested payload chunk.
    private func archive(_ files: [(String, Data)], method: CompressionMethod = .none,
                         type: Entry.EntryType = .file) throws -> Data {
        /// Temporary writable archive; no test entry is extracted to disk.
        let archive = try Archive(accessMode: .create)
        /// Original entry path and bytes, intentionally permitting malformed paths for tests.
        for (path, data) in files {
            try archive.addEntry(with: path, type: type, uncompressedSize: Int64(data.count), compressionMethod: method) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
        return try XCTUnwrap(archive.data)
    }

    /// Stored archives, DEFLATE archives, and extracted folders must retain identical artwork.
    func testOriginalStoredDeflatedAndFolderInputsAgree() throws {
        /// Stored ZIP input with flat lowercase filenames.
        let stored = try ClassicSkinPackage.load(fixture("original-stored.wsz"))
        /// DEFLATE ZIP input with a wrapper folder and uppercase filenames.
        let nested = try ClassicSkinPackage.load(fixture("nested-deflated.wsz"))
        /// Extracted folder input using the same original source bytes.
        let folder = try ClassicSkinPackage.load(fixture("OriginalClassic"))
        XCTAssertEqual(stored.mainBitmap, nested.mainBitmap)
        XCTAssertEqual(stored.assets, folder.assets)
        XCTAssertEqual(nested.root, "ampi original")
        XCTAssertEqual(nested.assetNames, ["cbuttons.bmp", "main.bmp"])
        XCTAssertTrue(stored.warnings.contains { $0.contains("Preview only") })
        XCTAssertTrue(stored.warnings.contains { $0.contains("eqmain.bmp") })
    }

    /// Historical backslash separators and uppercase filenames normalize consistently.
    func testBackslashAndCaseNormalization() throws {
        /// Single original background under a legacy Windows-style path.
        let skin = try ClassicSkinPackage.decode(archive([("Folder\\MAIN.BMP", mainBitmap())]))
        XCTAssertEqual(skin.root, "folder")
        XCTAssertEqual(skin.mainBitmap, try mainBitmap())
    }

    /// Unsafe entries are rejected even when a valid main background appears elsewhere.
    func testTraversalAbsoluteDriveAndAmbiguousPathsAreRejected() throws {
        /// Original background bytes used to keep the legitimate entry otherwise valid.
        let bitmap = try mainBitmap()
        /// Invalid path forms must not reach filesystem extraction or preview activation.
        for path in ["../bad.txt", "..\\bad.txt", "/bad.txt", "C:\\bad.txt", "a//bad.txt", "./bad.txt"] {
            XCTAssertThrowsError(try ClassicSkinPackage.decode(archive([("main.bmp", bitmap), (path, Data())])), path)
        }
    }

    /// Case-insensitive collisions must not overwrite one entry with another.
    func testDuplicateCaseInsensitivePathsAreRejected() throws {
        /// Same original bytes under two names that normalize to the same key.
        let bitmap = try mainBitmap()
        XCTAssertThrowsError(try ClassicSkinPackage.decode(archive([("main.bmp", bitmap), ("MAIN.BMP", bitmap)])))
    }

    /// Multiple independent Classic roots cannot be selected by guesswork.
    func testAmbiguousSkinRootsAreRejected() throws {
        /// Original background shared by two competing skin roots.
        let bitmap = try mainBitmap()
        XCTAssertThrowsError(try ClassicSkinPackage.decode(archive([("a/main.bmp", bitmap), ("b/main.bmp", bitmap)])))
    }

    /// Modern structure is rejected even when an archive also supplies a Classic background.
    func testModernSkinIsRejectedByStructure() throws {
        XCTAssertThrowsError(try ClassicSkinPackage.decode(archive([("main.bmp", mainBitmap()), ("skin.xml", Data("<skin/>".utf8))])))
    }

    /// A random file, truncated archive, or package without main.bmp cannot be previewed.
    func testInvalidArchivesAndMissingMainAreRejected() throws {
        XCTAssertThrowsError(try ClassicSkinPackage.decode(Data("not a ZIP".utf8)))
        /// Valid fixture truncated inside its terminal ZIP directory record.
        let data = try Data(contentsOf: fixture("original-stored.wsz"))
        XCTAssertThrowsError(try ClassicSkinPackage.decode(Data(data.dropLast(8))))
        XCTAssertThrowsError(try ClassicSkinPackage.decode(archive([("readme.txt", Data())])))
    }

    /// Any supplied BMP must be a real bounded bitmap; main geometry is fixed by the profile.
    func testInvalidAndOversizedBitmapGeometryIsRejected() throws {
        /// Main background with its width changed to violate the Classic profile.
        var wrongWidth = try mainBitmap()
        wrongWidth.writeUInt32(274, at: 18)
        XCTAssertThrowsError(try ClassicSkinPackage.decode(archive([("main.bmp", wrongWidth)])))
        /// Main background declaring an excessive height before any raster allocation.
        var huge = try mainBitmap()
        huge.writeUInt32(50_000, at: 22)
        XCTAssertThrowsError(try ClassicSkinPackage.decode(archive([("main.bmp", huge)])))
        XCTAssertThrowsError(try ClassicSkinPackage.decode(archive([("main.bmp", mainBitmap()), ("volume.bmp", Data("not BMP".utf8))])))
    }

    /// Modified stored pixels must fail their CRC instead of being accepted as valid artwork.
    func testChecksumMismatchIsRejected() throws {
        /// Single-entry stored archive, allowing a payload byte to be changed without moving headers.
        var data = try archive([("main.bmp", mainBitmap())])
        /// Local entry payload offset, after filename and extra fields.
        let payload = 30 + Int(try data.zipUInt16(at: 26)) + Int(try data.zipUInt16(at: 28))
        data[payload + 60] ^= 1
        XCTAssertThrowsError(try ClassicSkinPackage.decode(data))
    }

    /// Encryption and unreadable local headers cannot silently terminate the ZIP iterator.
    func testEncryptedAndInconsistentHeadersAreRejected() throws {
        /// Otherwise valid single-entry archive modified to advertise encryption.
        var encrypted = try archive([("main.bmp", mainBitmap())])
        /// Central-directory offset from the unmodified terminal record.
        let central = Int(try encrypted.zipUInt32(at: encrypted.count - 6))
        encrypted[6] |= 1
        encrypted[central + 8] |= 1
        XCTAssertThrowsError(try ClassicSkinPackage.decode(encrypted))
        /// Valid archive whose local header signature is corrupted.
        var broken = try archive([("main.bmp", mainBitmap())])
        broken[0] = 0
        XCTAssertThrowsError(try ClassicSkinPackage.decode(broken))
    }

    /// Declared entry count, archive bytes, and per-file sizes are checked before expansion.
    func testDeclaredResourceLimitsAreEnforced() throws {
        /// Oversized raw archive payload rejected before ZIP parsing.
        let oversized = Data(repeating: 0, count: ClassicSkinPackage.maximumArchiveBytes + 1)
        XCTAssertThrowsError(try ClassicSkinPackage.decode(oversized))
        /// Valid fixture whose terminal record falsely declares 513 entries.
        var tooMany = try archive([("main.bmp", mainBitmap())])
        tooMany[tooMany.count - 12] = 1
        tooMany[tooMany.count - 11] = 2
        XCTAssertThrowsError(try ClassicSkinPackage.decode(tooMany))
        /// Valid fixture whose central header declares a file above the 8 MiB cap.
        var tooLarge = try archive([("main.bmp", mainBitmap())])
        /// Central header to mutate without changing the small actual payload.
        let central = Int(try tooLarge.zipUInt32(at: tooLarge.count - 6))
        tooLarge.writeUInt32(UInt32(ClassicSkinPackage.maximumFileBytes + 1), at: central + 24)
        XCTAssertThrowsError(try ClassicSkinPackage.decode(tooLarge))
    }

    /// A DEFLATE stream exceeding its declared size still hits the actual output cap.
    func testActualExpansionCannotBypassDeclaredSize() throws {
        /// Highly compressible payload just above the per-file resource ceiling.
        let payload = Data(repeating: 65, count: ClassicSkinPackage.maximumFileBytes + 1)
        /// Small compressed archive with lying uncompressed-size fields.
        var data = try archive([("main.bmp", payload)], method: .deflate)
        /// Central header whose declared size is reduced alongside the local header.
        let central = Int(try data.zipUInt32(at: data.count - 6))
        data.writeUInt32(1, at: central + 24)
        data.writeUInt32(1, at: 22)
        XCTAssertThrowsError(try ClassicSkinPackage.decode(data)) { error in
            XCTAssertTrue(error.localizedDescription.contains("expansion"))
        }
    }

    /// Neither archive symlinks nor extracted-folder symlinks are eligible skin resources.
    func testSymbolicLinksAreRejected() throws {
        XCTAssertThrowsError(try ClassicSkinPackage.decode(archive([("main.bmp", Data("/tmp/outside.bmp".utf8))], type: .symlink)))
        /// Isolated test directory removed after its symlink validation check.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try mainBitmap().write(to: folder.appendingPathComponent("main.bmp"))
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("volume.bmp"), withDestinationURL: folder.appendingPathComponent("main.bmp"))
        XCTAssertThrowsError(try ClassicSkinPackage.load(folder))
    }
}

private extension Data {
    /// Replaces a checked four-byte fixture field with a little-endian test value.
    mutating func writeUInt32(_ value: UInt32, at offset: Int) {
        /// Each field byte is written explicitly, avoiding native-endian alignment assumptions.
        for byte in 0..<4 { self[offset + byte] = UInt8(truncatingIfNeeded: value >> (byte * 8)) }
    }
}
