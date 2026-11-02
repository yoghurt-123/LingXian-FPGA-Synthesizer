import Foundation
import Compression

struct MusicHallArchiveLimits {
    var maxArchiveBytes: Int64 = 32 * 1024 * 1024
    var maxUncompressedBytes: Int64 = 24 * 1024 * 1024
    var maxSingleFileBytes: Int64 = 12 * 1024 * 1024
    var maxEntries: Int = 64
    var maxCompressionRatio: Int = 300
}

enum MusicHallArchive {
    private struct Entry {
        let name: String
        let method: UInt16
        let crc32: UInt32
        let compressedSize: Int
        let uncompressedSize: Int
        let dataOffset: Int
    }

    private static let allowedFiles: Set<String> = [
        "manifest.json",
        "score/score.json",
        "score/performance.bin",
        "score/stage.json",
        "score/report.json",
        "score.json",
        "performance.bin",
        "stage.json",
        "report.json",
        "cover.png",
        "cover.jpg",
        "cover.jpeg",
        "preview.png",
        "source.mid",
        "source.midi",
        "source.musicxml",
        "LICENSE_SOURCE.md",
        "credits.json",
        "LICENSE",
        "LICENSE.txt",
        "README.md"
    ]

    static func isAllowedFileName(_ name: String) -> Bool {
        allowedFiles.contains(name)
    }

    static func extract(
        archive data: Data,
        to destination: URL,
        limits: MusicHallArchiveLimits = MusicHallArchiveLimits()
    ) throws {
        guard Int64(data.count) <= limits.maxArchiveBytes else {
            throw MusicHallError.tooLarge("压缩包超过 \(limits.maxArchiveBytes / 1024 / 1024) MB")
        }
        let entries = try parseEntries(data, limits: limits)

        let expectedNames = Set(entries.filter { !$0.name.hasSuffix("/") }.map(\.name))
        guard expectedNames.contains("manifest.json") else {
            throw MusicHallError.missingFile("manifest.json")
        }

        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )

        var totalWritten: Int64 = 0
        for entry in entries {
            if entry.name.hasSuffix("/") {
                continue
            }
            let payload = try decode(entry, archive: data)
            guard MusicHallCRC32.checksum(payload) == entry.crc32 else {
                throw MusicHallError.invalidArchive("\(entry.name) CRC32 不匹配")
            }
            totalWritten += Int64(payload.count)
            guard totalWritten <= limits.maxUncompressedBytes else {
                throw MusicHallError.tooLarge("解压后超过 \(limits.maxUncompressedBytes / 1024 / 1024) MB")
            }
            let fileURL = destination.appendingPathComponent(entry.name, isDirectory: false)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try payload.write(to: fileURL, options: .atomic)
        }
    }

    private static func parseEntries(
        _ data: Data,
        limits: MusicHallArchiveLimits
    ) throws -> [Entry] {
        guard data.count >= 22 else {
            throw MusicHallError.invalidArchive("文件过短")
        }
        let eocd = try findEndOfCentralDirectory(data)
        let diskNumber = readUInt16(data, eocd + 4)
        let centralDisk = readUInt16(data, eocd + 6)
        let entriesOnDisk = readUInt16(data, eocd + 8)
        let totalEntries = readUInt16(data, eocd + 10)
        let centralSize = Int(readUInt32(data, eocd + 12))
        let centralOffset = Int(readUInt32(data, eocd + 16))
        let commentLength = Int(readUInt16(data, eocd + 20))

        guard diskNumber == 0, centralDisk == 0, entriesOnDisk == totalEntries else {
            throw MusicHallError.invalidArchive("不支持分卷 ZIP")
        }
        guard totalEntries > 0, Int(totalEntries) <= limits.maxEntries else {
            throw MusicHallError.tooLarge("条目数超过 \(limits.maxEntries)")
        }
        guard Int64(centralSize) <= limits.maxArchiveBytes,
              centralOffset >= 0,
              centralSize >= 0,
              centralOffset + centralSize <= eocd else {
            throw MusicHallError.invalidArchive("中央目录越界")
        }
        guard eocd + 22 + commentLength <= data.count else {
            throw MusicHallError.invalidArchive("ZIP 注释长度异常")
        }

        var entries: [Entry] = []
        var seen = Set<String>()
        var cursor = centralOffset
        var totalUncompressed: Int64 = 0

        for _ in 0..<totalEntries {
            guard cursor + 46 <= data.count,
                  readUInt32(data, cursor) == 0x02014B50 else {
                throw MusicHallError.invalidArchive("中央目录记录损坏")
            }
            let flags = readUInt16(data, cursor + 8)
            let method = readUInt16(data, cursor + 10)
            let crc = readUInt32(data, cursor + 16)
            let compressedSizeRaw = readUInt32(data, cursor + 20)
            let uncompressedSizeRaw = readUInt32(data, cursor + 24)
            let nameLength = Int(readUInt16(data, cursor + 28))
            let extraLength = Int(readUInt16(data, cursor + 30))
            let commentLength = Int(readUInt16(data, cursor + 32))
            let diskStart = readUInt16(data, cursor + 34)
            let externalAttributes = readUInt32(data, cursor + 38)
            let localOffset = Int(readUInt32(data, cursor + 42))
            let recordLength = 46 + nameLength + extraLength + commentLength
            guard cursor + recordLength <= data.count else {
                throw MusicHallError.invalidArchive("中央目录名称越界")
            }
            guard (flags & 0x0001) == 0, (flags & 0x0040) == 0 else {
                throw MusicHallError.invalidArchive("不支持加密 ZIP")
            }
            guard diskStart == 0 else {
                throw MusicHallError.invalidArchive("不支持跨磁盘条目")
            }
            guard compressedSizeRaw != 0xFFFFFFFF,
                  uncompressedSizeRaw != 0xFFFFFFFF,
                  localOffset != 0xFFFFFFFF,
                  localOffset >= 0 else {
                throw MusicHallError.invalidArchive("不支持 ZIP64")
            }
            let unixMode = UInt16((externalAttributes >> 16) & 0xFFFF)
            guard (unixMode & 0xF000) != 0xA000 else {
                throw MusicHallError.unsafePath("符号链接")
            }

            let nameData = data.subdata(in: (cursor + 46)..<(cursor + 46 + nameLength))
            guard let rawName = String(data: nameData, encoding: .utf8) else {
                throw MusicHallError.invalidArchive("文件名不是 UTF-8")
            }
            let name = rawName.replacingOccurrences(of: "\\", with: "/")
            try validateName(name)
            if !name.hasSuffix("/") {
                let allowed = allowedFiles.contains(name)
                guard allowed else {
                    throw MusicHallError.invalidArchive("不允许的包内文件：\(name)")
                }
                guard seen.insert(name).inserted else {
                    throw MusicHallError.invalidArchive("重复文件：\(name)")
                }
            }

            let compressedSize = Int(compressedSizeRaw)
            let uncompressedSize = Int(uncompressedSizeRaw)
            guard compressedSize >= 0, uncompressedSize >= 0 else {
                throw MusicHallError.invalidArchive("文件大小异常")
            }
            guard Int64(uncompressedSize) <= limits.maxSingleFileBytes else {
                throw MusicHallError.tooLarge("\(name) 单文件过大")
            }
            totalUncompressed += Int64(uncompressedSize)
            guard totalUncompressed <= limits.maxUncompressedBytes else {
                throw MusicHallError.tooLarge("解压总大小超限")
            }
            if uncompressedSize > 4096, compressedSize > 0 {
                guard uncompressedSize / max(compressedSize, 1) <= limits.maxCompressionRatio else {
                    throw MusicHallError.tooLarge("\(name) 压缩比异常")
                }
            }
            guard method == 0 || method == 8 else {
                throw MusicHallError.invalidArchive("不支持的压缩方法 \(method)")
            }

            guard localOffset + 30 <= data.count,
                  readUInt32(data, localOffset) == 0x04034B50 else {
                throw MusicHallError.invalidArchive("本地文件头损坏")
            }
            let localFlags = readUInt16(data, localOffset + 6)
            let localMethod = readUInt16(data, localOffset + 8)
            let localNameLength = Int(readUInt16(data, localOffset + 26))
            let localExtraLength = Int(readUInt16(data, localOffset + 28))
            guard (localFlags & 0x0001) == 0, (localFlags & 0x0040) == 0 else {
                throw MusicHallError.invalidArchive("不支持加密条目")
            }
            guard localMethod == method else {
                throw MusicHallError.invalidArchive("本地头与中央目录压缩方法不一致")
            }
            guard localOffset + 30 + localNameLength + localExtraLength <= data.count else {
                throw MusicHallError.invalidArchive("本地文件名越界")
            }
            let localNameStart = localOffset + 30
            let localNameEnd = localNameStart + localNameLength
            guard localNameEnd <= data.count else {
                throw MusicHallError.invalidArchive("本地文件名越界")
            }
            let localNameData = data.subdata(in: localNameStart..<localNameEnd)
            guard let localName = String(data: localNameData, encoding: .utf8),
                  localName.replacingOccurrences(of: "\\", with: "/") == name else {
                throw MusicHallError.invalidArchive("本地头与中央目录文件名不一致")
            }
            let dataOffset = localNameEnd + localExtraLength
            guard dataOffset + compressedSize <= data.count else {
                throw MusicHallError.invalidArchive("压缩数据越界")
            }

            if !name.hasSuffix("/") {
                entries.append(
                    Entry(
                        name: name,
                        method: method,
                        crc32: crc,
                        compressedSize: compressedSize,
                        uncompressedSize: uncompressedSize,
                        dataOffset: dataOffset
                    )
                )
            }
            cursor += recordLength
        }
        return entries
    }

    private static func findEndOfCentralDirectory(_ data: Data) throws -> Int {
        let minimum = max(0, data.count - 65_557)
        var cursor = data.count - 22
        while cursor >= minimum {
            if readUInt32(data, cursor) == 0x06054B50 {
                let commentLength = Int(readUInt16(data, cursor + 20))
                if cursor + 22 + commentLength == data.count {
                    return cursor
                }
            }
            cursor -= 1
        }
        throw MusicHallError.invalidArchive("找不到 ZIP 中央目录结尾")
    }

    private static func validateName(_ name: String) throws {
        guard !name.isEmpty, !name.hasPrefix("/"), !name.hasPrefix("~") else {
            throw MusicHallError.unsafePath(name)
        }
        guard !name.contains(":") else {
            throw MusicHallError.unsafePath(name)
        }
        let trimmedName = name.hasSuffix("/") ? String(name.dropLast()) : name
        let components = trimmedName.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw MusicHallError.unsafePath(name)
        }
        if components.count > 1 {
            guard components.count == 2, String(components[0]) == "score" else {
                throw MusicHallError.unsafePath("只允许 score/ 下的已知文件：\(name)")
            }
        }
    }

    private static func decode(_ entry: Entry, archive: Data) throws -> Data {
        let compressed = archive.subdata(
            in: entry.dataOffset..<(entry.dataOffset + entry.compressedSize)
        )
        if entry.method == 0 {
            guard compressed.count == entry.uncompressedSize else {
                throw MusicHallError.invalidArchive("\(entry.name) 存储长度不一致")
            }
            return compressed
        }
        guard entry.uncompressedSize > 0 else {
            return Data()
        }
        guard !compressed.isEmpty else {
            throw MusicHallError.invalidArchive("\(entry.name) 压缩数据为空")
        }
        var output = Data(count: entry.uncompressedSize)
        let written = output.withUnsafeMutableBytes { destinationBuffer -> Int in
            guard let destination = destinationBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return 0
            }
            return compressed.withUnsafeBytes { sourceBuffer -> Int in
                guard let source = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }
                return compression_decode_buffer(
                    destination,
                    entry.uncompressedSize,
                    source,
                    compressed.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard written == entry.uncompressedSize else {
            throw MusicHallError.invalidArchive("\(entry.name) deflate 解压失败")
        }
        return output
    }
}
