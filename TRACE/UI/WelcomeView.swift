import SwiftUI

struct WelcomeView: View {
    @Bindable var studio: StudioModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("TRACE").font(.system(size: 17, weight: .semibold)).tracking(4)
                Spacer()
                Text("Motion studio").font(.system(size: 14)).foregroundStyle(TraceStyle.blue)
            }
            Spacer(minLength: 8)
            ChamberEmblem().padding(.bottom, 16)
            Text("A little movement.\nA lasting impression.")
                .font(.system(size: 30, weight: .medium)).multilineTextAlignment(.center).lineSpacing(4)
            Text("Record a gesture and explore it in space,\none moment at a time.")
                .font(.system(size: 17)).foregroundStyle(TraceStyle.blue).multilineTextAlignment(.center).lineSpacing(4).padding(.top, 16)
            Spacer(minLength: 8)
            Button { Task { await enterChamber() } } label: {
                HStack(spacing: 12) { Text(studio.opening ? "Opening studio…" : "Enter studio"); Image(systemName: "arrow.up.right") }
                    .font(.system(size: 17, weight: .semibold)).frame(width: 260, height: 50)
            }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(TraceStyle.graphite).foregroundStyle(.white)
                .disabled(studio.opening || studio.immersiveOpen).accessibilityIdentifier("enterChamber")
            HStack(spacing: 18) {
                Label("Up to 10 seconds", systemImage: "timer")
                Label("Stored on device", systemImage: "lock")
            }.font(.system(size: 12)).foregroundStyle(TraceStyle.blue).padding(.top, 18)
            if studio.notice.hasPrefix("The chamber") || studio.notice.hasPrefix("Entry cancelled") {
                Text(studio.notice).font(.caption).foregroundStyle(TraceStyle.blue).multilineTextAlignment(.center).padding(.top, 12)
            }
            Text(studio.isSimulator ? "Simulator preview · synthetic motion only" : "Works seated or standing. No walking needed.")
                .font(.system(size: 11)).foregroundStyle(TraceStyle.blue.opacity(0.8)).padding(.top, 26)
        }
        .foregroundStyle(TraceStyle.chalk).padding(36).frame(width: 620, height: 620)
        .background(TraceStyle.paper)
        .task {
            #if targetEnvironment(simulator)
            if CommandLine.arguments.contains("--preview-chamber") { await enterChamber() }
            #endif
        }
    }
    private func enterChamber() async {
        guard !studio.opening, !studio.immersiveOpen else { return }
        studio.opening = true
        switch await openImmersiveSpace(id: "motion-chamber") {
        case .opened: studio.immersiveOpen = true; dismissWindow(id: "studio")
        case .userCancelled: studio.notice = "Entry cancelled. Enter whenever you’re ready."
        case .error: studio.notice = "The chamber couldn’t open. Close another immersive app and try again."
        @unknown default: studio.notice = "The chamber couldn’t open. Try again."
        }
        studio.opening = false
    }
}
