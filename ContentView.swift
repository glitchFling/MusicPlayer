import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var player = MusicPlayer()
    @State private var isPlaying = false
    @State private var speed: Float = 1.0
    @State private var reverbOn = false
    var body: some View {
        ZStack {
            // Vibrant gradient background
            LinearGradient(gradient: Gradient(colors: [Color.purple, Color.blue]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
                .blur(radius: 30)
                .opacity(0.6)
            VStack(spacing: 30) {
                Text(player.currentSong?.capitalized ?? "Random Song")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .shadow(radius: 10)
                HStack(spacing: 40) {
                    Button(action: togglePlay) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .resizable()
                            .frame(width: 70, height: 70)
                            .foregroundColor(.white)
                    }
                    Button(action: player.playRandomSong) {
                        Image(systemName: "shuffle.circle.fill")
                            .resizable()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.white)
                    }
                }
                VStack(alignment: .leading) {
                    Text("Speed: \(String(format: "%.2fx", speed))")
                        .foregroundColor(.white)
                    Slider(value: $speed, in: 0.5...2.0, step: 0.01, onEditingChanged: { _ in
                        player.setSpeed(speed)
                    })
                }
                Toggle(isOn: $reverbOn) {
                    Text("Reverb")
                        .foregroundColor(.white)
                }
                .onChange(of: reverbOn) { value in
                    player.setReverb(enabled: value)
                }
                .toggleStyle(SwitchToggleStyle(tint: .white))
            }
            .padding()
        }
        .onAppear {
            player.playRandomSong()
        }
    }
    private func togglePlay() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

