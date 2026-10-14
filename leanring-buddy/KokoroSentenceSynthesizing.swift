//
//  KokoroSentenceSynthesizing.swift
//  leanring-buddy
//
//  What KokoroTTSClient needs from the voice engine. KokoroVoiceEngine is
//  the real implementation; tests substitute a fake so the client's
//  queueing and cancellation behaviour can be exercised without the
//  377 MB model.
//

import AVFoundation
import Foundation

@MainActor
protocol KokoroSentenceSynthesizing: AnyObject {
    var loadState: KokoroModelLoadState { get }

    /// Loads the model (first run: download + compile) and `voice`'s pack.
    /// Returns when done or failed; never throws.
    func prepareIfNeeded(preloadingVoice voice: String) async

    /// One sentence → PCM buffer at `SentenceAudioQueuePlayer.sampleRate`.
    func synthesizeSentence(_ sentence: String, voice: String) async throws -> AVAudioPCMBuffer
}
