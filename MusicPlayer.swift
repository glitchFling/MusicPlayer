// MusicPlayer.swift
import Foundation
import AVFoundation
import SwiftUI

class MusicPlayer: ObservableObject {
    // List of song filenames bundled with the app. Add your .mp3 files to the project.
    private let songFiles = ["song1.mp3", "song2.mp3", "song3.mp3", "song4.mp3"]
    
    private var audioEngine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var timePitch = AVAudioUnitTimePitch()
    private var reverb = AVAudioUnitReverb()
    private var audioFile: AVAudioFile?
    
    @Published var currentSong: String?
    
    init() {
        setupAudioGraph()
    }
    
    private func setupAudioGraph() {
        // Attach nodes
        audioEngine.attach(playerNode)
        audioEngine.attach(timePitch)
        audioEngine.attach(reverb)
        
        // Connect nodes: Player -> TimePitch -> Reverb -> Output
        audioEngine.connect(playerNode, to: timePitch, format: nil)
        audioEngine.connect(timePitch, to: reverb, format: nil)
        audioEngine.connect(reverb, to: audioEngine.mainMixerNode, format: nil)
        
        // Default reverb settings (dry)
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 0
        
        // Start engine
        do {
            try audioEngine.start()
        } catch {
            print("AudioEngine start error: \(error)")
        }
    }
    
    func playRandomSong() {
        guard let randomName = songFiles.randomElement() else { return }
        guard let url = Bundle.main.url(forResource: randomName, withExtension: nil) else {
            print("Unable to locate \(randomName) in bundle")
            return
        }
        do {
            audioFile = try AVAudioFile(forReading: url)
            scheduleFile()
            playerNode.play()
            currentSong = randomName.replacingOccurrences(of: ".mp3", with: "")
        } catch {
            print("Failed to load audio file: \(error)")
        }
    }
    
    private func scheduleFile() {
        guard let audioFile = audioFile else { return }
        playerNode.stop()
        playerNode.scheduleFile(audioFile, at: nil, completionHandler: nil)
    }
    
    func play() {
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }
    
    func pause() {
        if playerNode.isPlaying {
            playerNode.pause()
        }
    }
    
    func setSpeed(_ speed: Float) {
        // speed range 0.5x – 2.0x
        timePitch.rate = speed
    }
    
    func setReverb(enabled: Bool) {
        reverb.wetDryMix = enabled ? 50 : 0 // 0% dry, 100% wet max; 50 gives a lush feel
    }
}
