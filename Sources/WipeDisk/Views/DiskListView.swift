import SwiftUI
import WipeKit

struct DiskListView: View {

    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(selection: $model.selectedDiskID) {
            if let error = model.listError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Section("Silinebilir") {
                let wipable = model.disks.filter(\.canWipe)
                if wipable.isEmpty {
                    Text("Silinebilir disk yok")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                ForEach(wipable) { disk in
                    DiskRow(disk: disk).tag(disk.id)
                }
            }

            Section("Korumali") {
                ForEach(model.disks.filter { !$0.canWipe }) { disk in
                    DiskRow(disk: disk)
                        .tag(disk.id)
                        .selectionDisabled()
                }
            }
        }
        .listStyle(.sidebar)
        .disabled(model.isBusy)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    model.refresh()
                } label: {
                    Label("Yenile", systemImage: "arrow.clockwise")
                }
                .disabled(model.isRefreshing || model.isBusy)

                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                }
                Spacer()
            }
            .padding(10)
            .background(.bar)
        }
        .navigationTitle("Diskler")
    }
}

struct DiskRow: View {

    let disk: DiskInfo

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(disk.canWipe ? Color.accentColor : Color.secondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(disk.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                Text("\(disk.deviceIdentifier) · \(disk.formattedSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let reason = disk.blockReason {
                    Label(shortReason(reason), systemImage: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .help(disk.blockReason?.localizedDescription ?? disk.connectionSummary)
    }

    private var icon: String {
        if !disk.canWipe { return "lock.laptopcomputer" }
        if disk.isInternal { return "internaldrive" }
        if disk.busProtocol.localizedCaseInsensitiveContains("usb") { return "externaldrive.badge.plus" }
        return "externaldrive"
    }

    private func shortReason(_ reason: WipeBlockReason) -> String {
        switch reason {
        case .systemDisk: return "Sistem diski"
        case .synthesized: return "Sanal APFS kabi"
        case .virtualMedia: return "Sanal aygit"
        case .readOnly: return "Salt okunur"
        }
    }
}
