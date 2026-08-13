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
                    VStack(spacing: 0) {
                        Picker("", selection: $model.detailMode) {
                            ForEach(AppModel.DetailMode.allCases) { mode in
                                Label(mode.title, systemImage: mode.systemImage).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 320)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)

                        Divider()

                        switch model.detailMode {
                        case .wipe: DiskDetailView(disk: disk)
                        case .partition: PartitionView(disk: disk)
                        }
                    }
                    .navigationTitle(disk.displayName)
                    .navigationSubtitle(disk.deviceIdentifier)
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
        .sheet(isPresented: $model.isConfirmingPartition) {
            if let disk = model.selectedDisk {
                ConfirmPartitionSheet(disk: disk)
            }
        }
        .sheet(item: $model.volumeToFormat) { partition in
            ConfirmVolumeFormatSheet(partition: partition)
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
