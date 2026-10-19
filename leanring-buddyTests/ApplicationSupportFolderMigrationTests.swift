import Foundation
import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

struct ApplicationSupportFolderMigrationTests {

    private func makeTemporaryApplicationSupportDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("app-support-migration-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private func writeFile(_ text: String, at fileURL: URL) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    @Test func legacyFolderIsMovedWithAllOfItsContents() throws {
        let applicationSupportDirectoryURL = try makeTemporaryApplicationSupportDirectory()
        defer { try? FileManager.default.removeItem(at: applicationSupportDirectoryURL) }
        let legacyFolderURL = applicationSupportDirectoryURL.appendingPathComponent("Clicky", isDirectory: true)
        try writeFile("- likes zed", at: legacyFolderURL.appendingPathComponent("Memory/PROFILE.md"))
        try writeFile("model bytes", at: legacyFolderURL.appendingPathComponent("Models/kokoro/model.bin"))

        let outcome = ApplicationSupportFolderMigration.migrateLegacyFolderIfNeeded(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL
        )

        #expect(outcome == .moved)
        let currentFolderURL = applicationSupportDirectoryURL.appendingPathComponent("Lumen", isDirectory: true)
        #expect(try String(contentsOf: currentFolderURL.appendingPathComponent("Memory/PROFILE.md"), encoding: .utf8) == "- likes zed")
        #expect(try String(contentsOf: currentFolderURL.appendingPathComponent("Models/kokoro/model.bin"), encoding: .utf8) == "model bytes")
        #expect(!FileManager.default.fileExists(atPath: legacyFolderURL.path))
    }

    @Test func nothingHappensWhenThereIsNoLegacyFolder() throws {
        let applicationSupportDirectoryURL = try makeTemporaryApplicationSupportDirectory()
        defer { try? FileManager.default.removeItem(at: applicationSupportDirectoryURL) }

        let outcome = ApplicationSupportFolderMigration.migrateLegacyFolderIfNeeded(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL
        )

        #expect(outcome == .nothingToMigrate)
        #expect(!FileManager.default.fileExists(atPath: applicationSupportDirectoryURL.appendingPathComponent("Lumen").path))
    }

    @Test func anExistingCurrentFolderIsNeverOverwrittenAndTheLegacyFolderIsLeftAlone() throws {
        let applicationSupportDirectoryURL = try makeTemporaryApplicationSupportDirectory()
        defer { try? FileManager.default.removeItem(at: applicationSupportDirectoryURL) }
        let legacyFolderURL = applicationSupportDirectoryURL.appendingPathComponent("Clicky", isDirectory: true)
        let currentFolderURL = applicationSupportDirectoryURL.appendingPathComponent("Lumen", isDirectory: true)
        try writeFile("old notes", at: legacyFolderURL.appendingPathComponent("Memory/PROFILE.md"))
        try writeFile("new notes", at: currentFolderURL.appendingPathComponent("Memory/PROFILE.md"))

        let outcome = ApplicationSupportFolderMigration.migrateLegacyFolderIfNeeded(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL
        )

        #expect(outcome == .bothFoldersExist)
        #expect(try String(contentsOf: currentFolderURL.appendingPathComponent("Memory/PROFILE.md"), encoding: .utf8) == "new notes")
        #expect(try String(contentsOf: legacyFolderURL.appendingPathComponent("Memory/PROFILE.md"), encoding: .utf8) == "old notes")
    }

    @Test func migrationRunsOnlyOnceBecauseTheSecondCallFindsNothingLeftToMove() throws {
        let applicationSupportDirectoryURL = try makeTemporaryApplicationSupportDirectory()
        defer { try? FileManager.default.removeItem(at: applicationSupportDirectoryURL) }
        try writeFile("- fact", at: applicationSupportDirectoryURL.appendingPathComponent("Clicky/Memory/PROFILE.md"))

        _ = ApplicationSupportFolderMigration.migrateLegacyFolderIfNeeded(applicationSupportDirectoryURL: applicationSupportDirectoryURL)
        let secondOutcome = ApplicationSupportFolderMigration.migrateLegacyFolderIfNeeded(applicationSupportDirectoryURL: applicationSupportDirectoryURL)

        #expect(secondOutcome == .nothingToMigrate)
    }
}
