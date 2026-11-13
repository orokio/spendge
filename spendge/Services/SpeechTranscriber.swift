import AVFoundation
import Combine
import Foundation
import Speech

/// 系统语音识别：端侧优先，端侧不支持时回退到苹果服务器。不经过我们自己的服务。
@MainActor
final class SpeechTranscriber: ObservableObject {
    enum State: Equatable {
        case idle
        case listening
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript = ""

    /// 说完（手动停止或静默超时）后回调最终文本。
    var onFinish: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Task<Void, Never>?

    var isListening: Bool { state == .listening }

    func toggle() {
        if isListening { stop() } else { requestPermissionAndStart() }
    }

    // MARK: - 启动

    private func requestPermissionAndStart() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                guard status == .authorized else {
                    self.state = .failed("需要允许语音识别")
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    Task { @MainActor in
                        guard granted else {
                            self.state = .failed("需要允许麦克风")
                            return
                        }
                        self.start()
                    }
                }
            }
        }
    }

    private func start() {
        guard let recognizer, recognizer.isAvailable else {
            state = .failed("这台设备暂时用不了语音")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            state = .failed("麦克风被占用")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // 端侧优先：设备支持时音频不离开手机；不支持时由系统决定
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request
        transcript = ""

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            cleanUpAudio()
            state = .failed("没能打开麦克风")
            return
        }

        state = .listening
        resetSilenceTimer()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    self.resetSilenceTimer()
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.stop()
                }
            }
        }
    }

    // MARK: - 停止

    func stop() {
        guard isListening else { return }
        silenceTimer?.cancel()
        silenceTimer = nil
        cleanUpAudio()
        task?.finish()
        task = nil
        request = nil
        state = .idle
        onFinish?(transcript)
    }

    private func cleanUpAudio() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 两秒没听到新内容就自动结束。
    private func resetSilenceTimer() {
        silenceTimer?.cancel()
        silenceTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.stop() }
        }
    }
}
