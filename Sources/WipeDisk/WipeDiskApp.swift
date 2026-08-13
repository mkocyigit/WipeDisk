import SwiftUI

@main
struct WipeDiskApp: App {

    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("WipeDisk") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 580)
                .onAppear { model.startAutoRefresh() }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Button("Diskleri Yenile") { model.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.isBusy)
            }
        }
    }
}
