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
    @Published var lastError: PlayerError?

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let varispeed = AVAudioUnitVarispeed()
    private let reverb = AVAudioUnitReverb()
    private var audioFile: AVAudioFile?
    private var observers: [NSObjectProtocol] = []

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

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

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
        do {
            let file = try AVAudioFile(forReading: song.fileURL)
            audioFile = file
            currentSong = song
            playerNode.stop()
            playerNode.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                DispatchQueue.main.async { self?.playbackState = .finished }
            }
            playerNode.play()
            playbackState = .playing
            lastError = nil
        } catch {
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
        } catch { lastError = .engineUnavailable }
    }

    func pause() {
        playerNode.pause()
        if playbackState == .playing { playbackState = .paused }
    }

    func setSpeed(_ speed: Float) { varispeed.rate = min(max(speed, 0.5), 2.0) }
    func setReverb(amount: Float) { reverb.wetDryMix = min(max(amount, 0), 100) }
}
