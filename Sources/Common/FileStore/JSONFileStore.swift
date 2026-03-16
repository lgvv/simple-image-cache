import Foundation

public protocol JSONFileStoreType: Sendable {
    func load<T: Decodable & Sendable>(_ type: T.Type, from filename: String) async throws -> T
    func save<T: Encodable & Sendable>(_ value: T, to filename: String) async throws
    func delete(filename: String) async throws
}

public enum JSONFileStoreError: Error, Sendable, Equatable {
    case fileNotFound
    case invalidDirectory
    case invalidFilename
    case encodingFailed
    case decodingFailed
    case ioFailed
}

public struct JSONFileStore: JSONFileStoreType, Sendable {
    private let fileManager: @Sendable () -> FileManager
    private let makeEncoder: @Sendable () -> JSONEncoder
    private let makeDecoder: @Sendable () -> JSONDecoder
    private let directoryURL: URL

    public init(
        directoryURL: URL? = nil,
        fileManager: @escaping @Sendable () -> FileManager = { .default },
        encoder: @escaping @Sendable () -> JSONEncoder = { JSONEncoder() },
        decoder: @escaping @Sendable () -> JSONDecoder = { JSONDecoder() }
    ) throws {
        self.fileManager = fileManager
        makeEncoder = encoder
        makeDecoder = decoder
        let fm = fileManager()
        self.directoryURL = try JSONFileStore.resolveDirectoryURL(
            directoryURL,
            fileManager: fm
        )
        try JSONFileStore.ensureDirectoryExists(at: self.directoryURL, fileManager: fm)
    }

    public func load<T: Decodable & Sendable>(_ type: T.Type, from filename: String) async throws -> T {
        let fileURL = try self.fileURL(for: filename)
        let fm = fileManager()
        guard fm.fileExists(atPath: fileURL.path) else {
            throw JSONFileStoreError.fileNotFound
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = makeDecoder()
            return try decoder.decode(type, from: data)
        } catch is DecodingError {
            throw JSONFileStoreError.decodingFailed
        } catch {
            throw JSONFileStoreError.ioFailed
        }
    }

    public func save<T: Encodable & Sendable>(_ value: T, to filename: String) async throws {
        let fileURL = try self.fileURL(for: filename)
        do {
            let encoder = makeEncoder()
            let data = try encoder.encode(value)
            try data.write(to: fileURL, options: [.atomic])
        } catch is EncodingError {
            throw JSONFileStoreError.encodingFailed
        } catch {
            throw JSONFileStoreError.ioFailed
        }
    }

    public func delete(filename: String) async throws {
        let fileURL = try self.fileURL(for: filename)
        let fm = fileManager()
        guard fm.fileExists(atPath: fileURL.path) else {
            throw JSONFileStoreError.fileNotFound
        }
        do {
            try fm.removeItem(at: fileURL)
        } catch {
            throw JSONFileStoreError.ioFailed
        }
    }
}

private extension JSONFileStore {
    static func resolveDirectoryURL(
        _ customURL: URL?,
        fileManager: FileManager
    ) throws -> URL {
        if let customURL { return customURL }
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let bundleID = Bundle.main.bundleIdentifier ?? "DefaultApp"
        return appSupport
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("JSON", isDirectory: true)
    }

    static func ensureDirectoryExists(at url: URL, fileManager: FileManager) throws {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if exists {
            guard isDirectory.boolValue else { throw JSONFileStoreError.invalidDirectory }
            return
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func fileURL(for filename: String) throws -> URL {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = trimmed.isEmpty ? "data" : trimmed
        if !isValidFilename(safeName) {
            throw JSONFileStoreError.invalidFilename
        }
        let finalName = safeName.hasSuffix(".json") ? safeName : "\(safeName).json"
        let baseURL = directoryURL.standardizedFileURL
        let fileURL = baseURL.appendingPathComponent(finalName).standardizedFileURL
        let basePath = baseURL.path.hasSuffix("/") ? baseURL.path : baseURL.path + "/"
        guard fileURL.path.hasPrefix(basePath) else {
            throw JSONFileStoreError.invalidFilename
        }
        return fileURL
    }

    func isValidFilename(_ name: String) -> Bool {
        if name.contains("..") { return false }
        if name.contains("/") { return false }
        if name.contains("\\") { return false }
        return true
    }
}
