import SwiftUI

@main
struct VoiceChangerApp: App {
    @StateObject private var appController = AppController()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appController)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 400, height: 500)
    }
}
