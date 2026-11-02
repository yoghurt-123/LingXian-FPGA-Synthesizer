import Foundation
import CryptoKit

enum MusicHallConfiguration {
    static let catalogURLKey = "MusicHallCatalogURL"
    static let catalogCacheName = "catalog-cache.json"

    static var catalogURLText: String {
        get { UserDefaults.standard.string(forKey: catalogURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: catalogURLKey) }
    }

    static var catalogURL: URL? {
        let text = catalogURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil else {
            return nil
        }
        return url
    }
}

struct MusicHallInstallRecord: Codable {
    let songId: String
    let origin: MusicHallPackOrigin
    let installedAt: Date
    let archiveSha256: String?
    let archiveBytes: Int64?
}

private struct MusicHallPackLayout {
    let score: String
    let performance: String
    let stage: String
    let report: String?

    static func resolve(files: Set<String>) -> MusicHallPackLayout? {
        let score = ["score/score.json", "score.json"].first { files.contains($0) }
        let performance = ["score/performance.bin", "performance.bin"].first { files.contains($0) }
        let stage = ["score/stage.json", "stage.json"].first { files.contains($0) }
        guard let score, let performance, let stage else { return nil }
        let report = ["score/report.json", "report.json"].first { files.contains($0) }
        return MusicHallPackLayout(
            score: score,
            performance: performance,
            stage: stage,
            report: report
        )
    }
}
enum MusicHallPackValidator {
    static let packDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    static var catalogDecoder: JSONDecoder {
        JSONDecoder()
    }

    static func validate(
        directory: URL,
        origin: MusicHallPackOrigin,
        archiveSHA256: String?,
        archiveBytes: Int64?
    ) throws -> MusicHallLocalPack {
        let manifestData = try data(named: "manifest.json", in: directory)
        let manifest: MusicHallManifest
        do {
            manifest = try packDecoder.decode(MusicHallManifest.self, from: musicHallJSONData(manifestData))
        } catch {
            throw MusicHallError.invalidPack("manifest JSON 解析失败：\(error.localizedDescription)")
        }

        guard manifest.format == "fpgasong" else {
            throw MusicHallError.invalidPack("format 不是 fpgasong")
        }
        guard manifest.formatVersion == "0.1" || manifest.formatVersion == "1.0" else {
            throw MusicHallError.invalidPack("App 暂不支持 format_version \(manifest.formatVersion)")
        }
        guard let layout = MusicHallPackLayout.resolve(files: Set(manifest.files.keys)) else {
            throw MusicHallError.missingFile("manifest.files 缺少 score/performance/stage")
        }

        let scoreData = try data(named: layout.score, in: directory)
        let performanceData = try data(named: layout.performance, in: directory)
        let stageData = try data(named: layout.stage, in: directory)

        let score: MusicHallScoreInfo
        let stage: MusicHallStage
        do {
            score = try packDecoder.decode(MusicHallScoreInfo.self, from: musicHallJSONData(scoreData))
            stage = try packDecoder.decode(MusicHallStage.self, from: musicHallJSONData(stageData))
        } catch {
            throw MusicHallError.invalidPack("score/stage JSON 解析失败：\(error.localizedDescription)")
        }

        guard !manifest.songId.isEmpty, manifest.songId == score.songId else {
            throw MusicHallError.invalidPack("manifest/score song_id 不一致")
        }
        if let stageSong = stage.songId, !stageSong.isEmpty, stageSong != manifest.songId {
            throw MusicHallError.invalidPack("stage song_id 不一致")
        }

        for required in [layout.score, layout.performance, layout.stage] {
            guard manifest.files[required] != nil else {
                throw MusicHallError.missingFile("manifest.files.\(required)")
            }
        }
        for (name, _) in manifest.files {
            guard MusicHallArchive.isAllowedFileName(name) else {
                throw MusicHallError.unsafePath(name)
            }
            let fileData = try data(named: name, in: directory)
            try verifyFile(
                name: name,
                data: fileData,
                manifest: manifest,
                required: true
            )
        }

        let performance: MusicHallPerformance
        do {
            performance = try MusicHallPerformance.parse(performanceData)
        } catch {
            throw error
        }
        if let target = manifest.target,
           let numerator = target.sampleRateNum,
           let denominator = target.sampleRateDen,
           numerator > 0,
           denominator > 0 {
            guard let safeNumerator = UInt32(exactly: numerator),
                  let safeDenominator = UInt16(exactly: denominator),
                  safeNumerator == performance.sampleRateNumerator,
                  safeDenominator == performance.sampleRateDenominator else {
                throw MusicHallError.invalidPack("manifest 与 performance 采样率不一致")
            }
        }
        guard performance.eventCount > 0, performance.durationSeconds > 0 else {
            throw MusicHallError.invalidPack("歌曲没有有效演奏事件")
        }
        if let targetPPQN = manifest.target?.ppqn,
           let scorePPQN = score.ppqn,
           targetPPQN != scorePPQN {
            throw MusicHallError.invalidPack("manifest/score PPQN 不一致")
        }

        let coverData = (try? data(named: "cover.png", in: directory))
            ?? (try? data(named: "cover.jpg", in: directory))
            ?? (try? data(named: "cover.jpeg", in: directory))

        return MusicHallLocalPack(
            id: manifest.songId,
            manifest: manifest,
            score: score,
            stage: stage,
            performance: performance,
            performanceData: performanceData,
            directoryURL: directory,
            coverData: coverData,
            origin: origin,
            installedAt: Date(),
            archiveSHA256: archiveSHA256,
            archiveBytes: archiveBytes
        )
    }

    private static func verifyFile(
        name: String,
        data: Data,
        manifest: MusicHallManifest,
        required: Bool
    ) throws {
        guard let record = manifest.files[name] else {
            if required {
                throw MusicHallError.missingFile("manifest.files.\(name)")
            }
            return
        }
        guard Int64(data.count) == record.bytes else {
            throw MusicHallError.invalidPack("\(name) 大小与 manifest 不一致")
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", Int($0)) }.joined()
        guard digest.caseInsensitiveCompare(record.sha256) == .orderedSame else {
            throw MusicHallError.digestMismatch(name)
        }
    }

    private static func data(named name: String, in directory: URL) throws -> Data {
        guard MusicHallArchive.isAllowedFileName(name) else {
            throw MusicHallError.unsafePath(name)
        }
        let url = directory.appendingPathComponent(name, isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MusicHallError.missingFile(name)
        }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }
}

final class MusicHallStore {
    let packsRoot: URL
    private let catalogCacheURL: URL
    private let fileManager = FileManager.default

    init() {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        let base = support.appendingPathComponent("FPGAInstrument/MusicHall", isDirectory: true)
        packsRoot = base.appendingPathComponent("Packs", isDirectory: true)
        catalogCacheURL = base.appendingPathComponent(MusicHallConfiguration.catalogCacheName)
        try? FileManager.default.createDirectory(
            at: packsRoot,
            withIntermediateDirectories: true
        )
    }

    func scanInstalled() -> [MusicHallLocalPack] {
        guard let directories = try? fileManager.contentsOfDirectory(
            at: packsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var result: [MusicHallLocalPack] = []
        for directory in directories {
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }
            let recordURL = directory.appendingPathComponent("installation.json")
            let record = (try? Data(contentsOf: recordURL))
                .flatMap { try? JSONDecoder().decode(MusicHallInstallRecord.self, from: $0) }
            let pack = try? MusicHallPackValidator.validate(
                directory: directory,
                origin: record?.origin ?? .imported,
                archiveSHA256: record?.archiveSha256,
                archiveBytes: record?.archiveBytes
            )
            if let pack {
                result.append(pack)
            }
        }
        return result.sorted {
            if $0.installedAt == $1.installedAt { return $0.title < $1.title }
            return $0.installedAt > $1.installedAt
        }
    }

    func install(
        archiveData: Data,
        origin: MusicHallPackOrigin,
        expectedSHA256: String?,
        expectedBytes: Int64?
    ) throws -> MusicHallLocalPack {
        let limits = MusicHallArchiveLimits()
        guard Int64(archiveData.count) <= limits.maxArchiveBytes else {
            throw MusicHallError.tooLarge("压缩包超过 32 MB")
        }
        if let expectedBytes, Int64(archiveData.count) != expectedBytes {
            throw MusicHallError.invalidPack("下载大小与目录不符")
        }
        let actualSHA = SHA256.hash(data: archiveData).map { String(format: "%02x", Int($0)) }.joined()
        if let expectedSHA256, !expectedSHA256.isEmpty,
           actualSHA.caseInsensitiveCompare(expectedSHA256) != .orderedSame {
            throw MusicHallError.digestMismatch("整包 SHA-256")
        }

        let incoming = packsRoot.appendingPathComponent(".incoming-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: incoming) }
        try fileManager.createDirectory(at: incoming, withIntermediateDirectories: true)
        try MusicHallArchive.extract(archive: archiveData, to: incoming, limits: limits)
        let provisional = try MusicHallPackValidator.validate(
            directory: incoming,
            origin: origin,
            archiveSHA256: actualSHA,
            archiveBytes: Int64(archiveData.count)
        )

        let finalDirectory = packsRoot.appendingPathComponent(safeDirectoryName(provisional.id), isDirectory: true)
        if fileManager.fileExists(atPath: finalDirectory.path) {
            try fileManager.removeItem(at: finalDirectory)
        }
        try fileManager.moveItem(at: incoming, to: finalDirectory)

        let record = MusicHallInstallRecord(
            songId: provisional.id,
            origin: origin,
            installedAt: Date(),
            archiveSha256: actualSHA,
            archiveBytes: Int64(archiveData.count)
        )
        let recordData = try JSONEncoder().encode(record)
        try recordData.write(
            to: finalDirectory.appendingPathComponent("installation.json"),
            options: .atomic
        )

        return try MusicHallPackValidator.validate(
            directory: finalDirectory,
            origin: origin,
            archiveSHA256: actualSHA,
            archiveBytes: Int64(archiveData.count)
        )
    }

    func remove(_ pack: MusicHallLocalPack) throws {
        try fileManager.removeItem(at: pack.directoryURL)
    }

    func loadCatalogCache() -> MusicHallCatalog? {
        guard let data = try? Data(contentsOf: catalogCacheURL) else { return nil }
        return try? MusicHallPackValidator.catalogDecoder.decode(MusicHallCatalog.self, from: data)
    }

    func saveCatalogCache(_ catalog: MusicHallCatalog) {
        guard let data = try? JSONEncoder().encode(catalog) else { return }
        try? data.write(to: catalogCacheURL, options: .atomic)
    }

    private func safeDirectoryName(_ songId: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = songId.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(String(scalar)) : "_"
        }
        let raw = String(scalars).prefix(80)
        return raw.isEmpty ? "song-\(UUID().uuidString.prefix(8))" : String(raw)
    }
}

final class MusicHallDownloadClient: NSObject, URLSessionDownloadDelegate {
    typealias ProgressHandler = (Int64, Int64, Double) -> Void
    typealias CompletionHandler = (Result<URL, Error>) -> Void

    private let expectedBytes: Int64
    private var session: URLSession!
    private var task: URLSessionDownloadTask?
    private var delivered = false
    private var finished = false
    private let progressHandler: ProgressHandler
    private let completionHandler: CompletionHandler

    init(
        expectedBytes: Int64,
        progress: @escaping ProgressHandler,
        completion: @escaping CompletionHandler
    ) {
        self.expectedBytes = expectedBytes
        self.progressHandler = progress
        self.completionHandler = completion
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func start(url: URL) {
        var request = URLRequest(url: url)
        request.setValue("FPGAInstrument/0.14.0", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let task = session.downloadTask(with: request)
        self.task = task
        task.resume()
    }

    func cancel() {
        finish()
        task?.cancel()
        session.invalidateAndCancel()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedBytes
        let fraction: Double
        if total > 0 {
            fraction = min(max(Double(totalBytesWritten) / Double(total), 0), 1)
        } else {
            fraction = 0
        }
        progressHandler(totalBytesWritten, total, fraction)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard !finished else { return }
        if let response = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            finishFailure(MusicHallError.network("HTTP \(response.statusCode)"))
            return
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("MusicHallDownload-\(UUID().uuidString).fpgasong")
        do {
            try FileManager.default.copyItem(at: location, to: destination)
            delivered = true
            finishSuccess(destination)
        } catch {
            finishFailure(error)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard !finished else { return }
        if let error {
            finishFailure(error)
        } else if !delivered {
            finishFailure(MusicHallError.network("下载完成但没有文件"))
        }
    }

    private func finishSuccess(_ url: URL) {
        guard !finished else { return }
        finished = true
        session.finishTasksAndInvalidate()
        completionHandler(.success(url))
    }

    private func finishFailure(_ error: Error) {
        guard !finished else { return }
        finished = true
        session.invalidateAndCancel()
        completionHandler(.failure(error))
    }

    private func finish() {
        finished = true
    }
}

@MainActor
final class MusicHallLibrary: ObservableObject {
    @Published private(set) var catalog: MusicHallCatalog?
    @Published private(set) var catalogBaseURL: URL?
    @Published private(set) var localPacks: [String: MusicHallLocalPack] = [:]
    @Published private(set) var downloadProgress: [String: MusicHallDownloadProgress] = [:]
    @Published private(set) var catalogState: String = "尚未读取在线曲库"
    @Published var catalogURLText: String = MusicHallConfiguration.catalogURLText
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshingCatalog = false

    private let store = MusicHallStore()
    private var downloaders: [String: MusicHallDownloadClient] = [:]

    init() {
        let cachedCatalog = store.loadCatalogCache()
        catalog = cachedCatalog
        catalogBaseURL = MusicHallConfiguration.catalogURL
        for pack in store.scanInstalled() {
            localPacks[pack.id] = pack
        }
        catalogState = catalog == nil ? "未配置在线曲库；可导入 .fpgasong" : "已载入本地曲库缓存"
    }

    var songs: [MusicHallSong] {
        var seen = Set<String>()
        var result: [MusicHallSong] = []
        let remote = catalog?.songs ?? []
        let seed = MusicHallSeedCatalog.songs
        for item in remote + seed where !seen.contains(item.songId) {
            seen.insert(item.songId)
            result.append(MusicHallSong(catalog: item, local: localPacks[item.songId], catalogBaseURL: catalogBaseURL))
        }
        for pack in localPacks.values.sorted(by: { $0.installedAt > $1.installedAt })
            where !seen.contains(pack.id) {
            seen.insert(pack.id)
            result.append(MusicHallSong(catalog: nil, local: pack, catalogBaseURL: catalogBaseURL))
        }
        if let rockIndex = result.firstIndex(where: { $0.id == MusicHallSeedCatalog.rockTheme3.songId }), rockIndex > 0 {
            let rock = result.remove(at: rockIndex)
            result.insert(rock, at: 0)
        }
        return result
    }

    var cachedSongs: [MusicHallSong] {
        songs.filter(\.isCached)
    }

    var onlineSongs: [MusicHallSong] {
        songs.filter { !$0.isCached }
    }

    func progress(for id: String) -> MusicHallDownloadProgress {
        downloadProgress[id] ?? MusicHallDownloadProgress()
    }

    func cachedPack(id: String) -> MusicHallLocalPack? {
        localPacks[id]
    }

    func refreshCatalog() {
        guard let url = MusicHallConfiguration.catalogURL else {
            catalogState = "未配置在线曲库地址；当前只显示内置目录与本地导入包"
            return
        }
        isRefreshingCatalog = true
        catalogState = "正在读取在线曲库…"
        lastError = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 25
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    throw MusicHallError.network("曲库 HTTP 状态异常")
                }
                let decoded = try MusicHallPackValidator.catalogDecoder.decode(
                    MusicHallCatalog.self,
                    from: data
                )
                let valid = decoded.songs.filter {
                    !$0.songId.isEmpty && !$0.title.isEmpty && !$0.artist.isEmpty
                }
                guard !valid.isEmpty else {
                    throw MusicHallError.invalidPack("在线曲库没有有效曲目")
                }
                self.catalog = MusicHallCatalog(
                    schemaVersion: decoded.schemaVersion,
                    generatedAt: decoded.generatedAt,
                    songs: valid
                )
                self.catalogBaseURL = url
                self.store.saveCatalogCache(self.catalog!)
                self.catalogState = "在线曲库已更新 · \(valid.count) 首"
            } catch {
                self.lastError = error.localizedDescription
                self.catalogState = "在线曲库读取失败；仍可导入"
            }
            self.isRefreshingCatalog = false
        }
    }

    func saveCatalogURL(_ text: String) {
        catalogURLText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        MusicHallConfiguration.catalogURLText = catalogURLText
        refreshCatalog()
    }

    func download(_ song: MusicHallSong) {
        guard let item = song.catalog, let packURL = song.downloadURL else {
            lastError = "该曲目尚未配置真实在线包地址或相对路径无法解析"
            return
        }
        guard let expectedHash = item.packSha256, !expectedHash.isEmpty,
              let expectedBytes = item.packBytes, expectedBytes > 0 else {
            lastError = "在线目录缺少包大小或 SHA-256，App 拒绝下载"
            return
        }
        guard localPacks[item.songId] == nil else { return }
        guard downloaders[item.songId] == nil else { return }

        var progress = MusicHallDownloadProgress()
        progress.phase = .downloading
        progress.totalBytes = expectedBytes
        progress.message = "下载中"
        downloadProgress[item.songId] = progress
        lastError = nil

        let client = MusicHallDownloadClient(
            expectedBytes: expectedBytes,
            progress: { [weak self] received, total, fraction in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    var value = self.downloadProgress[item.songId] ?? MusicHallDownloadProgress()
                    value.phase = .downloading
                    value.receivedBytes = received
                    value.totalBytes = total
                    value.fraction = fraction
                    value.message = "下载 \(Int(fraction * 100))%"
                    self.downloadProgress[item.songId] = value
                }
            },
            completion: { [weak self] result in
                Task { @MainActor [weak self] in
                    self?.finishDownload(item: item, result: result)
                }
            }
        )
        downloaders[item.songId] = client
        client.start(url: packURL)
    }

    func cancelDownload(_ id: String) {
        downloaders[id]?.cancel()
        downloaders.removeValue(forKey: id)
        var progress = downloadProgress[id] ?? MusicHallDownloadProgress()
        progress.phase = .idle
        progress.message = "已取消"
        downloadProgress[id] = progress
    }

    func retry(_ song: MusicHallSong) {
        cancelDownload(song.id)
        download(song)
    }

    func delete(_ song: MusicHallSong) {
        guard let pack = localPacks[song.id] else { return }
        do {
            try store.remove(pack)
            localPacks.removeValue(forKey: song.id)
            downloadProgress.removeValue(forKey: song.id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setImportError(_ message: String) {
        lastError = message
    }

    func importPack(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let pack = try store.install(
                archiveData: data,
                origin: .imported,
                expectedSHA256: nil,
                expectedBytes: Int64(data.count)
            )
            localPacks[pack.id] = pack
            var progress = MusicHallDownloadProgress()
            progress.phase = .cached
            progress.fraction = 1
            progress.receivedBytes = Int64(data.count)
            progress.totalBytes = Int64(data.count)
            progress.message = "已从文件导入"
            downloadProgress[pack.id] = progress
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func finishDownload(item: MusicHallCatalogSong, result: Result<URL, Error>) {
        downloaders.removeValue(forKey: item.songId)
        switch result {
        case .failure(let error):
            var progress = downloadProgress[item.songId] ?? MusicHallDownloadProgress()
            progress.phase = .failed(error.localizedDescription)
            progress.message = "下载失败"
            downloadProgress[item.songId] = progress
            lastError = error.localizedDescription
        case .success(let fileURL):
            var progress = downloadProgress[item.songId] ?? MusicHallDownloadProgress()
            progress.phase = .verifying
            progress.message = "校验大小与 SHA-256"
            downloadProgress[item.songId] = progress
            do {
                let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
                try? FileManager.default.removeItem(at: fileURL)
                progress.phase = .installing
                progress.message = "写入 iPad 缓存"
                downloadProgress[item.songId] = progress
                let pack = try store.install(
                    archiveData: data,
                    origin: .online,
                    expectedSHA256: item.packSha256,
                    expectedBytes: item.packBytes
                )
                guard pack.id == item.songId else {
                    try? store.remove(pack)
                    throw MusicHallError.invalidPack("包 song_id 与在线目录不一致")
                }
                localPacks[item.songId] = pack
                progress.phase = .cached
                progress.fraction = 1
                progress.receivedBytes = Int64(data.count)
                progress.totalBytes = Int64(data.count)
                progress.message = "已缓存到 iPad"
                downloadProgress[item.songId] = progress
                lastError = nil
            } catch {
                try? FileManager.default.removeItem(at: fileURL)
                progress.phase = .failed(error.localizedDescription)
                progress.message = "校验或安装失败"
                downloadProgress[item.songId] = progress
                lastError = error.localizedDescription
            }
        }
    }
}

// Remove a UTF-8 BOM only for decoding; hash validation keeps original bytes.
private func musicHallJSONData(_ data: Data) -> Data {
    if data.starts(with: [UInt8(0xEF), UInt8(0xBB), UInt8(0xBF)]) {
        return Data(data.dropFirst(3))
    }
    return data
}
