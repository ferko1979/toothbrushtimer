import AVFoundation
import Foundation

/// Microphone -> 16 kHz mono Float32 chunks. No audio is ever stored: samples
/// go straight to the detector and are discarded (see PRIVACY.md).
final class AudioCapture {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private(set) var isRunning = false

    static func requestPermission(_ completion: @escaping (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { ok in
            DispatchQueue.main.async { completion(ok) }
        }
    }

    func start(onSamples: @escaping ([Float]) -> Void) throws {
        guard !isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        #if os(watchOS)
        try session.setCategory(.record, mode: .default, options: [])
        #else
        // .measurement turns off the system's voice processing / noise suppression,
        // which would otherwise remove the brushing sound.
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers])
        #endif
        try session.setActive(true)

        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000,
                                            channels: 1, interleaved: false),
              let conv = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw NSError(domain: "AudioCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Nem sikerült a hangformátum beállítása."])
        }
        converter = conv
        let ratio = 16000.0 / inFormat.sampleRate
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { buffer, _ in
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 64)
            guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }
            var consumed = false
            var error: NSError?
            conv.convert(to: out, error: &error) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, let ch = out.floatChannelData, out.frameLength > 0 else { return }
            onSamples(Array(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength))))
        }
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
