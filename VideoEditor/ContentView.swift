import SwiftUI

struct ContentView: View {
    @StateObject private var flow = FlowState()

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            switch flow.route {
            case .camera:
                CameraScreen()
                    .transition(.opacity)

            case .exportSettings:
                ExportSettingsScreen()
                    .transition(.move(edge: .trailing))

            case .processing:
                ProcessingScreen()
                    .transition(.move(edge: .trailing))

            case .exportComplete:
                ExportCompleteScreen()
                    .transition(.move(edge: .trailing))
            }
        }
        .environmentObject(flow)
        .animation(.easeInOut(duration: 0.3), value: flow.route)
        .preferredColorScheme(.dark)
    }
}
