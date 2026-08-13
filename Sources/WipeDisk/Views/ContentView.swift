import SwiftUI
import WipeKit

struct ContentView: View {

    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            DiskListView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
        } detail: {
            Group {
                if let session = model.session {
                    ProgressPanel(session: session)
                } else if let disk = model.selectedDisk {
                    DiskDetailView(disk: disk)
                } else {
                    ContentUnavailableView(
                        "Disk secilmedi",
                        systemImage: "externaldrive",
                        description: Text("Soldaki listeden silmek istediginiz diski secin.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $model.isConfirming) {
            if let disk = model.selectedDisk {
                ConfirmWipeSheet(disk: disk)
            }
        }
        .alert(
            "Islem baslatilamadi",
            isPresented: Binding(
                get: { model.launchError != nil && model.session == nil },
                set: { if !$0 { model.launchError = nil } }
            )
        ) {
            Button("Tamam", role: .cancel) { model.launchError = nil }
        } message: {
            Text(model.launchError ?? "")
        }
    }
}
