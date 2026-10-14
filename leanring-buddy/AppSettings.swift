//
//  AppSettings.swift
//  leanring-buddy
//
//  User-facing configuration for which AI backends Clicky talks to. Backed by
//  UserDefaults; API keys are NOT stored here (see SecretsStore).
//
//  Defaults are chosen so a fresh install works with zero accounts:
//  Apple Speech (STT) → Ollama on localhost (vision LLM) → Apple voices (TTS).
//

import AVFoundation
import Combine
import Foundation

/// Which service answers the "look at my screen and help" question.
enum ChatProviderKind: String, CaseIterable, Identifiable {
    case openRouter
    case ollama
    case anthropicDirect
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openRouter: return "OpenRouter"
        case .ollama: return "Ollama (local)"
        case .anthropicDirect: return "Anthropic"
        case .custom: return "Custom"
        }
    }

    /// Base URL for OpenAI-compatible providers. Anthropic-direct uses its own
    /// Messages API and ignores this.
    var defaultBaseURL: String {
        switch self {
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .ollama: return "http://localhost:11434/v1"
        case .anthropicDirect: return "https://api.anthropic.com/v1/messages"
        case .custom: return "http://localhost:8080/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .openRouter: return "anthropic/claude-haiku-5.5"
        case .ollama: return "gemma4:26b"
        case .anthropicDirect: return "claude-haiku-5-5"
        case .custom: return ""
        }
    }

    /// Which Keychain entry holds this provider's API key, if it needs one.
    var secretKey: SecretsStore.Key? {
        switch self {
        case .openRouter: return .openRouter
        case .anthropicDirect: return .anthropic
        case .ollama, .custom: return nil
        }
    }

    var usesOpenAICompatibleAPI: Bool {
        self != .anthropicDirect
    }
}

enum SpeechToTextProviderKind: String, CaseIterable, Identifiable {
    case apple
    case assemblyAI = "assemblyai"
    case openAI = "openai"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: return "Apple (local)"
        case .assemblyAI: return "AssemblyAI"
        case .openAI: return "OpenAI"
        }
    }

    var secretKey: SecretsStore.Key? {
        switch self {
        case .apple: return nil
        case .assemblyAI: return .assemblyAI
        case .openAI: return .openAI
        }
    }
}

enum TextToSpeechProviderKind: String, CaseIterable, Identifiable {
    case apple
    case elevenLabs = "elevenlabs"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: return "Apple (local)"
        case .elevenLabs: return "ElevenLabs"
        }
    }

    var secretKey: SecretsStore.Key? {
        switch self {
        case .apple: return nil
        case .elevenLabs: return .elevenLabs
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// UserDefaults keys. Kept in a nonisolated enum so non-main-actor code
    /// (e.g. the transcription provider factory) can read the raw values.
    enum Keys {
        static let chatProvider = "settings.chatProvider"
        static let chatBaseURL = "settings.chatBaseURL"
        static let chatModel = "settings.chatModel"
        static let speechToTextProvider = "settings.speechToTextProvider"
        static let textToSpeechProvider = "settings.textToSpeechProvider"
        static let appleVoiceIdentifier = "settings.appleVoiceIdentifier"
        static let elevenLabsVoiceID = "settings.elevenLabsVoiceID"
    }

    /// Voice ID Farza shipped with; kept as the default so ElevenLabs works
    /// the moment a key is pasted.
    static let defaultElevenLabsVoiceID = "kPzsL2i3teMYv0FxEYQ6"

    private let userDefaults = UserDefaults.standard

    @Published var chatProviderKind: ChatProviderKind {
        didSet {
            userDefaults.set(chatProviderKind.rawValue, forKey: Keys.chatProvider)
            // Switching provider resets URL + model to that provider's sensible
            // defaults; the user can still edit them afterwards.
            if oldValue != chatProviderKind {
                chatBaseURL = chatProviderKind.defaultBaseURL
                chatModel = chatProviderKind.defaultModel
            }
        }
    }

    @Published var chatBaseURL: String {
        didSet { userDefaults.set(chatBaseURL, forKey: Keys.chatBaseURL) }
    }

    @Published var chatModel: String {
        didSet { userDefaults.set(chatModel, forKey: Keys.chatModel) }
    }

    @Published var speechToTextProviderKind: SpeechToTextProviderKind {
        didSet { userDefaults.set(speechToTextProviderKind.rawValue, forKey: Keys.speechToTextProvider) }
    }

    @Published var textToSpeechProviderKind: TextToSpeechProviderKind {
        didSet { userDefaults.set(textToSpeechProviderKind.rawValue, forKey: Keys.textToSpeechProvider) }
    }

    /// `AVSpeechSynthesisVoice.identifier`. Empty means "system default voice".
    @Published var appleVoiceIdentifier: String {
        didSet { userDefaults.set(appleVoiceIdentifier, forKey: Keys.appleVoiceIdentifier) }
    }

    @Published var elevenLabsVoiceID: String {
        didSet { userDefaults.set(elevenLabsVoiceID, forKey: Keys.elevenLabsVoiceID) }
    }

    private init() {
        let storedChatProvider = userDefaults.string(forKey: Keys.chatProvider)
            .flatMap(ChatProviderKind.init(rawValue:)) ?? .ollama
        chatProviderKind = storedChatProvider
        chatBaseURL = userDefaults.string(forKey: Keys.chatBaseURL) ?? storedChatProvider.defaultBaseURL
        chatModel = userDefaults.string(forKey: Keys.chatModel) ?? storedChatProvider.defaultModel

        speechToTextProviderKind = userDefaults.string(forKey: Keys.speechToTextProvider)
            .flatMap(SpeechToTextProviderKind.init(rawValue:)) ?? .apple
        textToSpeechProviderKind = userDefaults.string(forKey: Keys.textToSpeechProvider)
            .flatMap(TextToSpeechProviderKind.init(rawValue:)) ?? .apple

        appleVoiceIdentifier = userDefaults.string(forKey: Keys.appleVoiceIdentifier) ?? ""
        elevenLabsVoiceID = userDefaults.string(forKey: Keys.elevenLabsVoiceID) ?? Self.defaultElevenLabsVoiceID

        // The upstream app stored a bare Claude model name here. It doesn't map
        // onto any of the new providers, so just clear it.
        userDefaults.removeObject(forKey: "selectedClaudeModel")
    }

    /// Non-main-actor read used by the transcription provider factory, which
    /// runs during BuddyDictationManager init.
    nonisolated static func storedSpeechToTextProviderKind() -> SpeechToTextProviderKind {
        UserDefaults.standard.string(forKey: Keys.speechToTextProvider)
            .flatMap(SpeechToTextProviderKind.init(rawValue:)) ?? .apple
    }

    /// English-capable Apple voices, best quality first, for the voice picker.
    static func availableAppleVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality {
                    return lhs.quality.rawValue > rhs.quality.rawValue
                }
                return lhs.name < rhs.name
            }
    }
}
