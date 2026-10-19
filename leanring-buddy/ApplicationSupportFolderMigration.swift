//
//  ApplicationSupportFolderMigration.swift
//  leanring-buddy
//
//  The app was renamed from Clicky to Lumen. Everything it keeps on disk
//  (the memory profile and notes, the ~380 MB Kokoro voice models) lived under
//  ~/Library/Application Support/Clicky, so on first launch that folder is
//  moved to .../Lumen instead of leaving the user's data behind and
//  re-downloading the models.
//

import Foundation

nonisolated enum ApplicationSupportFolderMigration {
    static let currentFolderName = "Lumen"
    static let legacyFolderName = "Clicky"

    enum Outcome: Equatable {
        case moved
        case nothingToMigrate
        /// Both folders exist, so nothing is moved: overwriting the current
        /// folder could destroy newer data, and the legacy one is left for the
        /// user to inspect.
        case bothFoldersExist
        case failed(String)
    }

    /// The current app folder. The first access runs the one-time migration, so
    /// every storage path derived from this value is evaluated after the move
    /// and nothing can create an empty current folder ahead of it.
    static let currentFolderURL: URL = {
        let applicationSupportDirectoryURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let outcome = migrateLegacyFolderIfNeeded(applicationSupportDirectoryURL: applicationSupportDirectoryURL)
        if outcome != .nothingToMigrate {
            print("📦 Lumen: moved the old Clicky data folder: \(outcome)")
        }
        return applicationSupportDirectoryURL.appendingPathComponent(currentFolderName, isDirectory: true)
    }()

    static func migrateLegacyFolderIfNeeded(
        applicationSupportDirectoryURL: URL,
        fileManager: FileManager = .default
    ) -> Outcome {
        let legacyFolderURL = applicationSupportDirectoryURL.appendingPathComponent(legacyFolderName, isDirectory: true)
        let currentFolderURL = applicationSupportDirectoryURL.appendingPathComponent(currentFolderName, isDirectory: true)

        guard fileManager.fileExists(atPath: legacyFolderURL.path) else {
            return .nothingToMigrate
        }
        guard !fileManager.fileExists(atPath: currentFolderURL.path) else {
            return .bothFoldersExist
        }

        do {
            try fileManager.moveItem(at: legacyFolderURL, to: currentFolderURL)
            return .moved
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
