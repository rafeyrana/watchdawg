import SwiftUI

@main
struct WatchdawgApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    TTLCleaner.shared.cleanExpiredRecordings()
                }
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit Watchdawg") {
                    cleanupAndQuit()
                }
                .keyboardShortcut("q")
            }
        }
    }

    private func cleanupAndQuit() {
        CameraManager.shared.stop()
        TTLCleaner.shared.stopPeriodicCleanup()
        NSApp.terminate(nil)
    }
}
