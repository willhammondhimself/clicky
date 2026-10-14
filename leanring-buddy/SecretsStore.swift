//
//  SecretsStore.swift
//  leanring-buddy
//
//  Stores API keys in the macOS Keychain so they never live in UserDefaults,
//  Info.plist, or the app binary. Each key is one generic-password item under
//  a single service name, keyed by the provider's account name.
//

import Foundation
import Security

enum SecretsStore {
    /// Every API key the app knows how to store. The raw value is the
    /// Keychain account name, so renaming a case would orphan saved keys.
    enum Key: String, CaseIterable {
        case openRouter = "openrouter"
        case anthropic = "anthropic"
        case assemblyAI = "assemblyai"
        case elevenLabs = "elevenlabs"
        case openAI = "openai"

        var displayName: String {
            switch self {
            case .openRouter: return "OpenRouter"
            case .anthropic: return "Anthropic"
            case .assemblyAI: return "AssemblyAI"
            case .elevenLabs: return "ElevenLabs"
            case .openAI: return "OpenAI"
            }
        }
    }

    /// Keychain service name shared by every item this app stores.
    private static let keychainServiceName = "com.willhammond.clicky"

    /// Returns the stored key, or nil when nothing is saved for it.
    static func read(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var resultItem: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &resultItem)

        guard status == errSecSuccess,
              let secretData = resultItem as? Data,
              let secretString = String(data: secretData, encoding: .utf8) else {
            return nil
        }

        let trimmedSecret = secretString.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedSecret.isEmpty ? nil : trimmedSecret
    }

    /// Saves the key, replacing any existing value. Passing an empty string
    /// deletes the item so the provider reads as "not configured".
    static func write(_ key: Key, value: String) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            delete(key)
            return
        }

        let secretData = Data(trimmedValue.utf8)

        let searchQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: key.rawValue
        ]

        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: secretData
        ]

        let updateStatus = SecItemUpdate(searchQuery as CFDictionary, attributesToUpdate as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var addQuery = searchQuery
            addQuery[kSecValueData as String] = secretData
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                print("⚠️ SecretsStore: failed to add \(key.rawValue) (OSStatus \(addStatus))")
            }
        } else if updateStatus != errSecSuccess {
            print("⚠️ SecretsStore: failed to update \(key.rawValue) (OSStatus \(updateStatus))")
        }
    }

    static func delete(_ key: Key) {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(deleteQuery as CFDictionary)
    }

    static func hasValue(_ key: Key) -> Bool {
        read(key) != nil
    }
}
