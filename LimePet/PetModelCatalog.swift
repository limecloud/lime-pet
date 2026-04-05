import CryptoKit
import Foundation

private let petModelCatalogBundle: Bundle = {
    #if SWIFT_PACKAGE
    return .module
    #else
    return .main
    #endif
}()

struct PetModelCatalogResponse: Codable {
    let version: Int
    let generatedAt: String?
    let assetBaseURL: URL?
    let items: [PetModelCatalogItem]

    private enum CodingKeys: String, CodingKey {
        case version
        case generatedAt
        case assetBaseURL
        case items
    }

    init(
        version: Int,
        generatedAt: String?,
        assetBaseURL: URL?,
        items: [PetModelCatalogItem]
    ) {
        self.version = version
        self.generatedAt = generatedAt
        self.assetBaseURL = assetBaseURL
        self.items = items
    }

    func resolved() -> PetModelCatalogResponse {
        let resolvedItems = items.map { $0.resolved(assetBaseURL: assetBaseURL) }
        return PetModelCatalogResponse(
            version: version,
            generatedAt: generatedAt,
            assetBaseURL: assetBaseURL,
            items: resolvedItems
        )
    }
}

struct PetModelCatalogItem: Identifiable, Codable, Hashable {
    let id: String
    let version: String
    let character: PetCharacterTheme
    let install: PetModelInstallManifest

    func resolved(assetBaseURL: URL?) -> PetModelCatalogItem {
        PetModelCatalogItem(
            id: id,
            version: version,
            character: character,
            install: install.resolved(assetBaseURL: assetBaseURL)
        )
    }
}

struct PetModelInstallManifest: Codable, Hashable {
    let assets: [PetModelAsset]

    func resolved(assetBaseURL: URL?) -> PetModelInstallManifest {
        PetModelInstallManifest(assets: assets.map { $0.resolved(assetBaseURL: assetBaseURL) })
    }
}

struct PetModelAsset: Codable, Hashable {
    let relativePath: String
    let downloadPath: String?
    let downloadURL: URL?
    let size: Int64?
    let sha256: String?

    private enum CodingKeys: String, CodingKey {
        case relativePath
        case downloadPath
        case downloadURL = "downloadUrl"
        case size
        case sha256
    }

    func resolved(assetBaseURL: URL?) -> PetModelAsset {
        guard downloadURL == nil, let assetBaseURL, let downloadPath else { return self }
        return PetModelAsset(
            relativePath: relativePath,
            downloadPath: downloadPath,
            downloadURL: PetURLBuilder.appendingPath(downloadPath, to: assetBaseURL),
            size: size,
            sha256: sha256
        )
    }
}

struct PetInstalledModelRegistry: Codable {
    let items: [PetInstalledModelRecord]
}

struct PetInstalledModelRecord: Identifiable, Codable, Hashable {
    let id: String
    let version: String
    let installedAt: String
    let character: PetCharacterTheme
    let assets: [String]
}

enum PetCurrentModelInstallState: Equatable {
    case bundled
    case installable
    case installing(progress: Double)
    case installed
    case updateAvailable
    case failed(message: String)

    var canInstall: Bool {
        switch self {
        case .installable, .updateAvailable, .failed:
            return true
        case .bundled, .installing, .installed:
            return false
        }
    }

    var isRenderable: Bool {
        switch self {
        case .bundled, .installed, .updateAvailable:
            return true
        case .installable, .installing, .failed:
            return false
        }
    }

    var actionTitle: String {
        switch self {
        case .bundled:
            return "内置"
        case .installable:
            return "安装"
        case .installing(let progress):
            return "安装 \(Int(progress * 100))%"
        case .installed:
            return "已安装"
        case .updateAvailable:
            return "更新"
        case .failed:
            return "重试"
        }
    }
}

enum PetModelStorage {
    static let fileManager = FileManager.default

    static var applicationSupportRootURL: URL {
        let baseDirectory =
            (try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ??
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)

        return baseDirectory
            .appendingPathComponent("LimePet", isDirectory: true)
            .standardizedFileURL
    }

    static var installRegistryURL: URL {
        applicationSupportRootURL.appendingPathComponent("model-installs.json")
    }

    static func resourceRoots(bundle: Bundle) -> [URL] {
        [
            bundle.bundleURL.standardizedFileURL,
            applicationSupportRootURL
        ]
    }
}

enum PetURLBuilder {
    static func appendingPath(_ path: String, to baseURL: URL) -> URL {
        let components = path
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }

        return components.reduce(baseURL) { partial, component in
            partial.appendingPathComponent(component, isDirectory: false)
        }
    }
}

struct PetHTTPEnvelope<Payload: Decodable>: Decodable {
    let code: Int
    let message: String
    let data: Payload
}

enum PetModelCatalogClientError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "模型目录响应无效"
        case .httpStatus(let statusCode):
            return "模型目录请求失败（HTTP \(statusCode)）"
        }
    }
}

final class PetModelCatalogClient {
    private let decoder = JSONDecoder()

    func loadBundledCatalog(bundle: Bundle = petModelCatalogBundle) -> PetModelCatalogResponse? {
        let bundledCatalog =
            loadCatalogFile(bundle: bundle, subdirectory: nil) ??
            loadCatalogFile(bundle: bundle, subdirectory: "Resources")

        return bundledCatalog?.resolved()
    }

    func fetchRemoteCatalog(baseURL: URL, tenantID: String) async throws -> PetModelCatalogResponse {
        let endpoint = PetURLBuilder.appendingPath(
            "api/v1/public/tenants/\(tenantID)/client/model-catalog",
            to: baseURL
        )

        let (data, response) = try await URLSession.shared.data(from: endpoint)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PetModelCatalogClientError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw PetModelCatalogClientError.httpStatus(httpResponse.statusCode)
        }

        let envelope = try decoder.decode(PetHTTPEnvelope<PetModelCatalogResponse>.self, from: data)
        return envelope.data.resolved()
    }

    private func loadCatalogFile(bundle: Bundle, subdirectory: String?) -> PetModelCatalogResponse? {
        guard
            let url = bundle.url(
                forResource: "live2d-model-catalog",
                withExtension: "json",
                subdirectory: subdirectory
            ),
            let data = try? Data(contentsOf: url),
            let catalog = try? decoder.decode(PetModelCatalogResponse.self, from: data)
        else {
            return nil
        }

        return catalog
    }
}

enum PetModelInstallServiceError: LocalizedError {
    case missingDownloadURL(String)
    case invalidHTTPStatus(Int, String)
    case checksumMismatch(String)

    var errorDescription: String? {
        switch self {
        case .missingDownloadURL(let path):
            return "模型资源缺少下载地址：\(path)"
        case .invalidHTTPStatus(let statusCode, let path):
            return "下载模型资源失败（HTTP \(statusCode)）：\(path)"
        case .checksumMismatch(let path):
            return "模型资源校验失败：\(path)"
        }
    }
}

final class PetModelInstallService {
    private let fileManager = FileManager.default
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadInstalledModels() -> [PetInstalledModelRecord] {
        let registry = loadRegistry()
        let records = registry.items.filter { record in
            guard let live2D = record.character.live2d else {
                return false
            }
            return live2D.availableModelPaths.allSatisfy { modelPath in
                fileManager.fileExists(atPath: targetURL(for: modelPath).path)
            }
        }

        if records.count != registry.items.count {
            try? writeRegistry(PetInstalledModelRegistry(items: records))
        }

        return records.sorted { $0.character.displayName.localizedStandardCompare($1.character.displayName) == .orderedAscending }
    }

    func install(
        item: PetModelCatalogItem,
        progress: @Sendable @escaping (Double) async -> Void
    ) async throws -> PetInstalledModelRecord {
        try ensureBaseDirectories()

        let uniqueAssets = deduplicatedAssets(item.install.assets)
        let total = max(uniqueAssets.count, 1)

        for (index, asset) in uniqueAssets.enumerated() {
            try Task.checkCancellation()
            try await install(asset: asset)
            await progress(Double(index + 1) / Double(total))
        }

        let record = PetInstalledModelRecord(
            id: item.id,
            version: item.version,
            installedAt: ISO8601DateFormatter().string(from: Date()),
            character: item.character,
            assets: uniqueAssets.map(\.relativePath)
        )

        var records = loadRegistry().items.filter { $0.id != record.id }
        records.append(record)
        try writeRegistry(PetInstalledModelRegistry(items: records))
        return record
    }

    private func install(asset: PetModelAsset) async throws {
        guard let downloadURL = asset.downloadURL else {
            throw PetModelInstallServiceError.missingDownloadURL(asset.relativePath)
        }

        let targetURL = targetURL(for: asset.relativePath)
        if fileManager.fileExists(atPath: targetURL.path),
           try matchesChecksum(for: targetURL, expectedSHA256: asset.sha256) {
            return
        }

        let (data, response) = try await URLSession.shared.data(from: downloadURL)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PetModelCatalogClientError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw PetModelInstallServiceError.invalidHTTPStatus(httpResponse.statusCode, asset.relativePath)
        }

        if let expectedSHA256 = asset.sha256,
           sha256(for: data) != expectedSHA256.lowercased() {
            throw PetModelInstallServiceError.checksumMismatch(asset.relativePath)
        }

        let parentDirectory = targetURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true, attributes: nil)
        try data.write(to: targetURL, options: .atomic)
    }

    private func loadRegistry() -> PetInstalledModelRegistry {
        guard
            let data = try? Data(contentsOf: PetModelStorage.installRegistryURL),
            let registry = try? decoder.decode(PetInstalledModelRegistry.self, from: data)
        else {
            return PetInstalledModelRegistry(items: [])
        }

        return registry
    }

    private func writeRegistry(_ registry: PetInstalledModelRegistry) throws {
        try ensureBaseDirectories()
        let data = try encoder.encode(registry)
        try data.write(to: PetModelStorage.installRegistryURL, options: .atomic)
    }

    private func ensureBaseDirectories() throws {
        try fileManager.createDirectory(
            at: PetModelStorage.applicationSupportRootURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private func targetURL(for relativePath: String) -> URL {
        PetURLBuilder.appendingPath(relativePath, to: PetModelStorage.applicationSupportRootURL)
            .standardizedFileURL
    }

    private func matchesChecksum(for fileURL: URL, expectedSHA256: String?) throws -> Bool {
        guard let expectedSHA256, !expectedSHA256.isEmpty else {
            return true
        }

        let data = try Data(contentsOf: fileURL)
        return sha256(for: data) == expectedSHA256.lowercased()
    }

    private func sha256(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func deduplicatedAssets(_ assets: [PetModelAsset]) -> [PetModelAsset] {
        var seen = Set<String>()
        return assets
            .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
            .filter { asset in
                seen.insert(asset.relativePath).inserted
            }
    }
}
