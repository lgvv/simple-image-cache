@testable import Common
import Foundation
import Testing

@Suite
struct JSONFileStoreTests {
    private struct Sample: Codable, Equatable {
        let id: Int
        let name: String
    }

    @Test("값을 저장한 뒤 다시 읽으면 원래 값과 동일")
    func roundTripsSavedValue() async throws {
        // Given
        let directory = makeTempDirectory()
        let sut = try JSONFileStore(directoryURL: directory)
        let payload = Sample(id: 1, name: "App")

        // When
        try await sut.save(payload, to: "sample")
        let loaded = try await sut.load(Sample.self, from: "sample")

        // Then
        #expect(loaded == payload)
    }

    @Test("같은 파일명에 두 번 저장하면 마지막 값으로 덮어씀")
    func overwritesExistingFileWhenSavingTwice() async throws {
        // Given
        let directory = makeTempDirectory()
        let sut = try JSONFileStore(directoryURL: directory)

        // When
        try await sut.save(Sample(id: 1, name: "First"), to: "sample")
        try await sut.save(Sample(id: 2, name: "Second"), to: "sample")
        let loaded = try await sut.load(Sample.self, from: "sample")

        // Then
        #expect(loaded == Sample(id: 2, name: "Second"))
    }

    @Test("파일을 삭제하면 이후 로드는 fileNotFound 발생")
    func throwsFileNotFoundAfterDeletingFile() async throws {
        // Given
        let directory = makeTempDirectory()
        let sut = try JSONFileStore(directoryURL: directory)
        try await sut.save(Sample(id: 1, name: "App"), to: "sample")

        // When
        try await sut.delete(filename: "sample")

        // Then
        await #expect {
            _ = try await sut.load(Sample.self, from: "sample")
        } throws: { error in
            guard let storeError = error as? JSONFileStoreError else { return false }
            return storeError == .fileNotFound
        }
    }

    @Test("유효하지 않은 JSON 파일을 읽으면 decodingFailed 발생")
    func throwsDecodingFailedForInvalidJSON() async throws {
        // Given
        let directory = makeTempDirectory()
        let sut = try JSONFileStore(directoryURL: directory)
        let fileURL = directory.appendingPathComponent("broken.json")
        try Data("not-json".utf8).write(to: fileURL, options: [.atomic])

        // When / Then
        await #expect {
            _ = try await sut.load(Sample.self, from: "broken")
        } throws: { error in
            guard let storeError = error as? JSONFileStoreError else { return false }
            return storeError == .decodingFailed
        }
    }

    @Test("없는 파일명을 읽으면 fileNotFound 발생")
    func throwsFileNotFoundForMissingFilename() async throws {
        // Given
        let directory = makeTempDirectory()
        let sut = try JSONFileStore(directoryURL: directory)

        // When / Then
        await #expect {
            _ = try await sut.load(Sample.self, from: "nonexistent")
        } throws: { error in
            guard let storeError = error as? JSONFileStoreError else { return false }
            return storeError == .fileNotFound
        }
    }

    @Test("빈 값도 저장 후 다시 읽기 가능")
    func roundTripsEmptyValue() async throws {
        // Given
        let directory = makeTempDirectory()
        let sut = try JSONFileStore(directoryURL: directory)
        let payload = Sample(id: 0, name: "")

        // When
        try await sut.save(payload, to: "empty")
        let loaded = try await sut.load(Sample.self, from: "empty")

        // Then
        #expect(loaded == payload)
    }
}

private func makeTempDirectory() -> URL {
    let base = FileManager.default.temporaryDirectory
    let directory = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
