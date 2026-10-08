// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Checks the bounded ZIP32 directory before ZIPFoundation's fallible entry iterator is used.
enum ClassicZIPPreflight {
    /// Validates every declared header and rejects encryption, ZIP64, spanning, and special files.
    /// - Returns: Exact entry count that the library must subsequently yield.
    /// - Throws: `ThemeError` for malformed metadata or an unsupported ZIP feature.
    static func validate(_ data: Data) throws -> Int {
        guard data.count >= 22 else { throw ThemeError.invalid("Skin package is not a complete ZIP archive.") }
        /// End record candidate, located by signature and its exact trailing comment length.
        var end: Int?
        /// Possible end-record offsets within the ZIP comment's maximum 65,535-byte range.
        for offset in stride(from: data.count - 22, through: max(0, data.count - 22 - 65_535), by: -1) {
            if try data.zipUInt32(at: offset) == 0x06054b50,
               Int(try data.zipUInt16(at: offset + 20)) == data.count - offset - 22 { end = offset; break }
        }
        /// Valid terminal directory record; arbitrary file extensions do not prove ZIP structure.
        guard let end else { throw ThemeError.invalid("Skin package has no valid ZIP directory.") }
        /// Total declared entries, bounded before constructing the library's iterator.
        let count = Int(try data.zipUInt16(at: end + 10))
        /// Byte offset and byte length of the central directory within this payload.
        let start = Int(try data.zipUInt32(at: end + 16))
        /// Central directory length, which must end exactly at the terminal record.
        let size = Int(try data.zipUInt32(at: end + 12))
        guard (1...ClassicSkinPackage.maximumEntries).contains(count),
              try data.zipUInt16(at: end + 4) == 0, try data.zipUInt16(at: end + 6) == 0,
              Int(try data.zipUInt16(at: end + 8)) == count, start <= end, size == end - start else {
            throw ThemeError.invalid("Unsupported ZIP directory: use a single-disk ZIP32 skin with at most 512 entries.")
        }
        /// Central header cursor advanced using each record's validated variable-length fields.
        var cursor = start
        /// Declared entry index; every header is checked, including entries the library might skip.
        for _ in 0..<count {
            guard cursor <= end - 46, try data.zipUInt32(at: cursor) == 0x02014b50 else {
                throw ThemeError.invalid("Corrupt ZIP entry directory.")
            }
            /// Feature flags checked before any decompression; encryption is unsupported.
            let flags = try data.zipUInt16(at: cursor + 8)
            /// Compression method: only stored and DEFLATE Classic packages are accepted.
            let method = try data.zipUInt16(at: cursor + 10)
            /// Central filename byte count, compared with the local header's original bytes.
            let nameLength = Int(try data.zipUInt16(at: cursor + 28))
            /// Current record length including filename, extra fields, and comment.
            let length = 46 + nameLength + Int(try data.zipUInt16(at: cursor + 30)) + Int(try data.zipUInt16(at: cursor + 32))
            /// Offset of the matching local header, constrained to precede the central directory.
            let local = Int(try data.zipUInt32(at: cursor + 42))
            /// Unix type bits, when supplied by a Unix/macOS archive producer.
            let fileType = (try data.zipUInt32(at: cursor + 38) >> 16) & 0xf000
            /// Producer OS code determines whether the Unix mode bits are authoritative.
            let producer = try data.zipUInt16(at: cursor + 4) >> 8
            guard flags & 0x41 == 0, method == 0 || method == 8,
                  try data.zipUInt16(at: cursor + 6) <= 20, try data.zipUInt16(at: cursor + 34) == 0,
                  nameLength > 0, length <= end - cursor, local <= start - 30,
                  try data.zipUInt32(at: local) == 0x04034b50,
                  try data.zipUInt16(at: local + 6) == flags, try data.zipUInt16(at: local + 8) == method,
                  Int(try data.zipUInt16(at: local + 26)) == nameLength,
                  try data.zipUInt32(at: cursor + 24) <= ClassicSkinPackage.maximumFileBytes,
                  (producer != 3 && producer != 19) || [0, 0x8000, 0x4000].contains(fileType) else {
                throw ThemeError.invalid("ZIP entry uses unsupported features or has inconsistent headers.")
            }
            /// First compressed-data byte after the local filename and extra fields.
            let payload = local + 30 + nameLength + Int(try data.zipUInt16(at: local + 28))
            guard payload <= start, Int(try data.zipUInt32(at: cursor + 20)) <= start - payload,
                  data.subdata(in: local + 30..<local + 30 + nameLength) == data.subdata(in: cursor + 46..<cursor + 46 + nameLength) else {
                throw ThemeError.invalid("ZIP entry extends outside its package or its filename is inconsistent.")
            }
            cursor += length
        }
        guard cursor == end else { throw ThemeError.invalid("ZIP entry count does not match the directory length.") }
        return count
    }
}

extension Data {
    /// Reads a checked little-endian 16-bit ZIP field without unaligned pointer access.
    func zipUInt16(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset <= count - 2 else { throw ThemeError.invalid("Truncated ZIP header.") }
        return UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    /// Reads a checked little-endian 32-bit ZIP field without unaligned pointer access.
    func zipUInt32(at offset: Int) throws -> UInt32 {
        UInt32(try zipUInt16(at: offset)) | UInt32(try zipUInt16(at: offset + 2)) << 16
    }
}
