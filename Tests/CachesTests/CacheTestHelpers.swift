@testable import Caches
import Foundation

func makeDiskCache(
    directory: String = "CacheTests.\(UUID().uuidString)",
    writeBuffer: DiskCache.WriteBufferConfiguration? = nil
) throws -> DiskCache {
    try DiskCache(configuration: .init(directoryName: directory, writeBuffer: writeBuffer))
}
