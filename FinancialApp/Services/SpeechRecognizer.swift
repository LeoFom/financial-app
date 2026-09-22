import AVFoundation
import Foundation
import Speech
import SwiftUI

@MainActor
final class SpeechRecognizer: NSObject, ObservableObject {
    @Published var transcript = ""
    @Published var isListening = false
    @Published var errorMessage: String?
    @Published var audioLevel: CGFloat = 0.25

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
        ?? SFSpeechRecognizer()

    func toggle() {
        if isListening {
            stop()
        } else {
            start()
        }
    }

    func start() {
        errorMessage = nil
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                switch status {
                case .authorized:
                    self.beginSession()
                case .denied, .restricted:
                    self.errorMessage = "Нет доступа к распознаванию речи. Включите его в Настройках iOS."
                case .notDetermined:
                    self.errorMessage = "Разрешите распознавание речи, чтобы диктовать расход."
                @unknown default:
                    self.errorMessage = "Не удалось включить диктовку."
                }
            }
        }
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        isListening = false
        audioLevel = 0.25
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func beginSession() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] allowed in
            Task { @MainActor in
                guard let self else { return }
                guard allowed else {
                    self.errorMessage = "Нет доступа к микрофону. Включите его в Настройках iOS."
                    return
                }
                self.installTap()
            }
        }
    }

    private func installTap() {
        stop()
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Распознавание речи сейчас недоступно."
            return
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Не удалось включить микрофон."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let level = Self.level(from: buffer)
            Task { @MainActor in
                self?.audioLevel = level
            }
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                if let result {
                    self?.transcript = result.bestTranscription.formattedString
                }
                if error != nil || result?.isFinal == true {
                    self?.stop()
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
        } catch {
            errorMessage = "Не удалось начать запись."
            stop()
        }
    }

    private static func level(from buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let data = buffer.floatChannelData?[0] else { return 0.25 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0.25 }
        var sum: Float = 0
        for i in 0..<count {
            let sample = data[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(count))
        return CGFloat(min(max(rms * 8, 0.18), 1))
    }
}
