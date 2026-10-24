import SwiftUI

@main
struct TraceApp: App {
    @State private var studio = StudioModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup(id: "studio") {
            WelcomeView(studio: studio)
                .task { await studio.loadLibrary() }
                .preferredColorScheme(.light)
        }
        .defaultSize(width: 620, height: 620)
        .windowResizability(.contentSize)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { studio.suspended() }
        }
        ImmersiveSpace(id: "motion-chamber") {
            MotionChamberView(studio: studio)
                .preferredColorScheme(.light)
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}
