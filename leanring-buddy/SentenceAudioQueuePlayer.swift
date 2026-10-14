//
//  SentenceAudioQueuePlayer.swift
//  leanring-buddy
//
//  Plays synthesized sentence buffers back to back with no gap. Kokoro hands
//  us one PCM buffer per sentence; AVAudioPlayerNode schedules them in order
//  and starts the next the instant the previous one ends, so a multi-sentence
//  reply sounds continuous even though each sentence was synthesized
//  separately. Also used by the transient-cursor logic through `isPlaying`.
//

import AVFoundation
import Foundation

@MainActor
final class SentenceAudioQueuePlayer {
    /// Kokoro's output rate. The mixer resamples to the output device.
    static let sampleRate: Double = 24_000

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let playbackFormat: AVAudioFormat

    /// Buffers scheduled but not yet fully played. `isPlaying` is derived
    /// from it rather than from `playerNode.isPlaying`, which stays true
    /// while the node idles waiting for more data.
    private var scheduledBufferCount = 0

    /// Incremented by `stop()`. Completion callbacks captured with an older
    /// generation are ignored, so a stopped buffer's late callback cannot
    /// decrement the count of a newer queue.
    private var playbackGeneration = 0

    init() {
        playbackFormat = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)!
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playbackFormat)
    }

    /// Wraps float samples in a mono PCM buffer. Returns nil for empty input.
    static func makeBuffer(samples: [Float], sampleRate: Double) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channelData = buffer.floatChannelData else {
            return nil
        }
        samples.withUnsafeBufferPointer { samplePointer in
            channelData[0].update(from: samplePointer.baseAddress!, count: samples.count)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }

    /// Schedules `buffer` after anything already queued and starts playback
    /// if the node is idle. Throws if the audio engine cannot start (no
    /// output device, for example).
    func enqueue(_ buffer: AVAudioPCMBuffer) throws {
        if !audioEngine.isRunning {
            try audioEngine.start()
        }

        scheduledBufferCount += 1
        let generationWhenScheduled = playbackGeneration
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.playbackGeneration == generationWhenScheduled else { return }
                self.scheduledBufferCount = max(0, self.scheduledBufferCount - 1)
            }
        }

        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    var isPlaying: Bool {
        scheduledBufferCount > 0
    }

    /// Drops every queued buffer immediately. The engine stays running so the
    /// next reply starts without engine start-up latency.
    func stop() {
        playbackGeneration += 1
        scheduledBufferCount = 0
        playerNode.stop()
    }
}
