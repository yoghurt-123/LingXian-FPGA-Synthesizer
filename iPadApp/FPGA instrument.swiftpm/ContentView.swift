import SwiftUI

enum AppDestination: Hashable {
    case home
    case performance
    case guitar
    case drums
    case piano
    case musicHall
    case concert
    case help
    case bluetooth
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var destination: AppDestination = .home
    @State private var blockedFreePlayNotice = false
    @StateObject private var guitarSession = GuitarPracticeSession()
    @StateObject private var drumSession = DrumKitPracticeSession()
    @StateObject private var pianoSession = PianoPracticeSession()
    @StateObject private var musicHallLibrary = MusicHallLibrary()
    @StateObject private var musicHall = MusicHallController()
    @StateObject private var concertPlayback = ConcertPlayback()
    @StateObject private var freePlayAudio = FreePlayAudio()
    @StateObject private var freePlayRouter = FreePlayEventRouter()
    @StateObject private var practicePerformance = PracticePerformanceController()
    @StateObject private var bluetooth = InstrumentBluetooth()

    var body: some View {
        ZStack {
            CosmicBackdrop(scene: cosmicScene)
                .ignoresSafeArea()
            currentPage
        }
        .preferredColorScheme(.light)
        .tint(PaperPalette.red)
        .fontDesign(.serif)
        .foregroundStyle(PaperPalette.ink)
        .environmentObject(bluetooth)
        .environmentObject(freePlayRouter)
        .environmentObject(practicePerformance)
        .onAppear {
            practicePerformance.attach(router: freePlayRouter, bluetooth: bluetooth)
            musicHall.attach(transport: MusicHallBLETransport(bluetooth: bluetooth))
        }
        .onChange(of: bluetooth.isReady) { _, ready in
            if !ready {
                practicePerformance.handleConnectionLost()
                musicHall.handleDisconnect()
                freePlayRouter.handleDisconnect()
            } else if musicHall.stopUnconfirmed {
                musicHall.stop()
            }
        }
        .alert("音乐厅停止未确认", isPresented: $blockedFreePlayNotice) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("ESP/FPGA 停止状态尚未确认。请回到音乐厅重试停止，或断开重连后再试。自由演奏和音游暂不开放。")
        }
        .onChange(of: bluetooth.performanceReady) { _, ready in
            if !ready {
                practicePerformance.handleCapabilityLost()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                pauseForBackground()
            } else if destination == .piano {
                if !freePlayRouter.isHardwareMode {
                    pianoSession.prepareAudio()
                }
            } else if destination == .guitar {
                if !freePlayRouter.isHardwareMode {
                    guitarSession.prepareAudio()
                }
            } else if destination == .drums {
                if !freePlayRouter.isHardwareMode {
                    drumSession.prepareAudio()
                }
            } else if destination == .performance {
                if !freePlayRouter.isHardwareMode {
                    freePlayAudio.prepare()
                }
            }
        }
    }

    @ViewBuilder
    private var currentPage: some View {
        switch destination {
        case .home:
            HomeView(
                onOpenPerformance: openPerformance,
                onOpenGuitar: openGuitar,
                onOpenDrums: openDrums,
                onOpenPiano: openPiano,
                onOpenMusicHall: openMusicHall,
                onOpenConcert: { destination = .concert },
                onOpenBluetooth: { destination = .bluetooth },
                onOpenHelp: { destination = .help }
            )

        case .performance:
            SubpageScaffold(title: "自由演奏", onBackHome: goHome) {
                PerformanceView(audio: freePlayAudio, router: freePlayRouter)
            }

        case .guitar:
            SubpageScaffold(title: "电吉他音游", onBackHome: goHome) {
                GuitarPracticeView(
                    session: guitarSession,
                    audio: guitarSession.audio,
                    onBackHome: goHome
                )
            }

        case .drums:
            SubpageScaffold(title: "架子鼓音游", onBackHome: goHome) {
                DrumKitPracticeView(
                    session: drumSession,
                    audio: drumSession.audio,
                    onBackHome: goHome
                )
            }

        case .piano:
            SubpageScaffold(title: "钢琴音游", onBackHome: goHome) {
                PianoPracticeView(
                    session: pianoSession,
                    audio: pianoSession.audio,
                    onBackHome: goHome
                )
            }

        case .musicHall:
            MusicHallView(
                library: musicHallLibrary,
                controller: musicHall,
                onBackHome: goHome
            )

        case .concert:
            SubpageScaffold(title: "纸上舞台", onBackHome: goHome) {
                ConcertView(playback: concertPlayback)
            }

        case .help:
            SubpageScaffold(title: "使用说明", onBackHome: goHome) {
                HelpView()
            }
        case .bluetooth:
            SubpageScaffold(title: "蓝牙连接与诊断", onBackHome: goHome) {
                BluetoothConnectionView(bluetooth: bluetooth)
            }
        }
    }

    private var cosmicScene: CosmicScene {
        switch destination {
        case .home: return .home
        case .performance: return .performance
        case .guitar: return .guitar
        case .drums: return .drums
        case .piano: return .piano
        case .musicHall: return .musicHall
        case .concert: return .concert
        case .help: return .help
        case .bluetooth: return .bluetooth
        }
    }

    private var freePlayAvailable: Bool {
        !musicHall.blocksFreePlay
    }

    private func openGuitar() {
        guard freePlayAvailable else { blockedFreePlayNotice = true; return }
        destination = .guitar
    }

    private func openDrums() {
        guard freePlayAvailable else { blockedFreePlayNotice = true; return }
        destination = .drums
    }

    private func openPiano() {
        guard freePlayAvailable else { blockedFreePlayNotice = true; return }
        destination = .piano
    }

    private func openPerformance() {
        guard freePlayAvailable else { blockedFreePlayNotice = true; return }
        destination = .performance
    }

    private func openMusicHall() {
        destination = .musicHall
    }

    private func goHome() {
        let blocked = musicHall.blocksFreePlay
        musicHall.stop()
        if !blocked {
            practicePerformance.endPage(reason: .leavePage)
            guitarSession.pause()
            guitarSession.suspendAudioIfLoaded()
            concertPlayback.pause()
            drumSession.pause()
            drumSession.suspendAudioIfLoaded()
            pianoSession.pause()
            pianoSession.suspendAudioIfLoaded()
            freePlayRouter.releaseAll(reason: .leavePage)
            freePlayAudio.stopAll()
            freePlayAudio.suspendAll()
        }
        destination = .home
    }

    private func pauseForBackground() {
        musicHall.handleBackground()
        practicePerformance.releaseCurrentPage(reason: .background)
        freePlayRouter.releaseAll(reason: .background)
        bluetooth.suspend()
        guitarSession.pause()
        guitarSession.suspendAudioIfLoaded()
        concertPlayback.pause()
        drumSession.pause()
        drumSession.suspendAudioIfLoaded()
        pianoSession.pause()
        pianoSession.suspendAudioIfLoaded()
        freePlayAudio.stopAll()
        freePlayAudio.suspendAll()
    }
}
