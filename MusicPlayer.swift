import AVFoundation
import Combine
import Foundation

final class MusicPlayer: ObservableObject {
    enum PlaybackState: Equatable {
        case idle
        case playing
        case paused
        case finished
    }

    enum PlayerError: LocalizedError, Identifiable {
        case unableToLoad
        case engineUnavailable

        var id: String { errorDescription ?? "player-error" }
        var errorDescription: String? {
            switch self {
            case .unableToLoad: return "This track could not be loaded. Try importing it again."
            case .engineUnavailable: return "Audio is unavailable right now. Try pressing play again."
            }
        }
    }

    @Published private(set) var currentSong: Song?
    @Published private(set) var playbackState: PlaybackState = .idle
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var currentTime: TimeInterval = 0
    @Published var lastError: PlayerError?

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let varispeed = AVAudioUnitVarispeed()
    private let reverb = AVAudioUnitReverb()
    private var audioFile: AVAudioFile?
    private var observers: [NSObjectProtocol] = []
    private var progressTimer: Timer?
    private var progressOffset: TimeInterval = 0
    private var loadGeneration = 0

    init() {
        configureSession()
        setupAudioGraph()
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let interruption = AVAudioSession.InterruptionType(rawValue: type) else { return }
            if interruption == .began { self?.pause() }
            else if interruption == .ended { try? self?.audioEngine.start() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            try? self?.audioEngine.start()
        })
    }

    deinit {
        progressTimer?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private func configureSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch { lastError = .engineUnavailable }
    }

    private func setupAudioGraph() {
        audioEngine.attach(playerNode)
        audioEngine.attach(varispeed)
        audioEngine.attach(reverb)
        audioEngine.connect(playerNode, to: varispeed, format: nil)
        audioEngine.connect(varispeed, to: reverb, format: nil)
        audioEngine.connect(reverb, to: audioEngine.mainMixerNode, format: nil)
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 0
        do { try audioEngine.start() } catch { lastError = .engineUnavailable }
    }

    func load(_ song: Song) {
        AspaltVision.shared.analyzeAndLog(song: song)
        do {
            let file = try AVAudioFile(forReading: song.fileURL)
            loadGeneration += 1
            let generation = loadGeneration
            stopProgressUpdates()
            playerNode.stop()
            audioFile = file
            currentSong = song
            duration = file.processingFormat.sampleRate > 0
                ? Double(file.length) / file.processingFormat.sampleRate
                : 0
            currentTime = 0
            progressOffset = 0
            playerNode.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, self.loadGeneration == generation else { return }
                    self.currentTime = self.duration
                    self.stopProgressUpdates()
                    self.playbackState = .finished
                }
            }
            playerNode.play()
            playbackState = .playing
            startProgressUpdates()
            lastError = nil
        } catch {
            loadGeneration += 1
            stopProgressUpdates()
            audioFile = nil
            duration = 0
            currentTime = 0
            progressOffset = 0
            playbackState = .idle
            lastError = .unableToLoad
        }
    }

    func play() {
        guard audioFile != nil else { lastError = .unableToLoad; return }
        do {
            if !audioEngine.isRunning { try audioEngine.start() }
            playerNode.play()
            playbackState = .playing
            startProgressUpdates()
        } catch { lastError = .engineUnavailable }
    }

    func pause() {
        playerNode.pause()
        stopProgressUpdates()
        if playbackState == .playing { playbackState = .paused }
    }

    func seek(to time: TimeInterval) {
        guard let file = audioFile, duration > 0, time.isFinite else { return }
        let target = min(max(time, 0), duration)
        let wasPlaying = playbackState == .playing
        let sampleRate = file.processingFormat.sampleRate
        loadGeneration += 1
        let generation = loadGeneration
        playerNode.stop()

        let startFrame = AVAudioFramePosition(target * sampleRate)
        let remainingFrames = max(0, file.length - startFrame)
        guard remainingFrames > 0 else {
            progressOffset = duration
            currentTime = duration
            stopProgressUpdates()
            playbackState = .finished
            return
        }

        progressOffset = target
        playerNode.scheduleSegment(file, startingFrame: startFrame, frameCount: AVAudioFrameCount(min(remainingFrames, AVAudioFramePosition(AVAudioFrameCount.max))), at: nil, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.loadGeneration == generation else { return }
                self.currentTime = self.duration
                self.stopProgressUpdates()
                self.playbackState = .finished
            }
        })
        currentTime = target
        if wasPlaying {
            playerNode.play()
            startProgressUpdates()
        } else {
            playbackState = .paused
        }
    }

    private func startProgressUpdates() {
        guard progressTimer == nil else { return }
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }

    private func stopProgressUpdates() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func updateProgress() {
        guard playbackState == .playing,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0 else { return }
        let time = progressOffset + Double(playerTime.sampleTime) / playerTime.sampleRate
        currentTime = min(max(time, 0), duration)
    }

    func setSpeed(_ speed: Float) { varispeed.rate = min(max(speed, 0.5), 2.0) }
    func setReverb(amount: Float) { reverb.wetDryMix = min(max(amount, 0), 100) }
}
