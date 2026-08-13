import SwiftUI
import WipeKit

struct DiskDetailView: View {

    let disk: DiskInfo
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                Divider()
                volumes
                Divider()
                methodSection
                Divider()
                optionsSection
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) { actionBar }
        .navigationTitle(disk.displayName)
        .navigationSubtitle(disk.deviceIdentifier)
    }

    // MARK: - Basliklar

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: disk.isInternal ? "internaldrive.fill" : "externaldrive.fill")
                .font(.system(size: 42))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(disk.mediaName.isEmpty ? disk.displayName : disk.mediaName)
                    .font(.title2.weight(.semibold))
                Text(disk.connectionSummary)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Badge(text: disk.formattedSize, systemImage: "chart.pie")
                    Badge(text: disk.rawDeviceNode, systemImage: "terminal")
                    Badge(text: "\(disk.blockSize) B blok", systemImage: "square.grid.3x3")
                }
                .padding(.top, 4)
            }
            Spacer()
        }
    }

    private var volumes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Silinecek birimler")
                .font(.headline)

            if disk.partitions.isEmpty {
                Text("Bolum tablosu yok — disk ham durumda.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(disk.partitions) { partition in
                    HStack {
                        Image(systemName: partition.mountPoint == nil ? "circle" : "checkmark.circle.fill")
                            .foregroundStyle(partition.mountPoint == nil ? .secondary : Color.green)
                            .font(.caption)
                        Text(partition.displayName)
                        Text(partition.deviceIdentifier)
                            .foregroundStyle(.secondary)
                            .font(.caption.monospaced())
                        Spacer()
                        Text(ByteFormatter.string(partition.size))
                            .foregroundStyle(.secondary)
                            .font(.caption.monospacedDigit())
                    }
                    .font(.callout)
                }
            }
        }
    }

    // MARK: - Yontem

    private var methodSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Silme yontemi")
                .font(.headline)

            ForEach(WipeMethod.allCases) { candidate in
                MethodCard(
                    method: candidate,
                    isSelected: model.method == candidate,
                    diskSize: disk.size
                )
                .onTapGesture { model.method = candidate }
            }
        }
    }

    // MARK: - Secenekler

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Secenekler")
                .font(.headline)

            Toggle(isOn: $model.verify) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Son gecisi dogrula")
                    Text("Disk geri okunup yazilanla karsilastirilir. Sureyi bir gecis kadar uzatir.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: $model.dryRun) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Deneme modu (hicbir sey yazilmaz)")
                    Text("Butun akis calisir ama diske tek bayt gitmez. Once bununla denemeniz onerilir.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Silme sonrasi", selection: $model.reformat) {
                ForEach(ReformatOption.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)

            if model.reformat != .none {
                TextField("Birim adi", text: $model.volumeLabel)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
            }
        }
    }

    // MARK: - Eylem cubugu

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Toplam yazilacak veri")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(ByteFormatter.string(model.plannedBytes(for: disk)))
                        .font(.title3.monospacedDigit().weight(.semibold))
                }

                Spacer()

                if model.dryRun {
                    Label("Deneme modu acik", systemImage: "testtube.2")
                        .foregroundStyle(.blue)
                        .font(.callout)
                }

                Button(role: .destructive) {
                    model.beginConfirmation()
                } label: {
                    Label(model.dryRun ? "Denemeyi Baslat" : "Diski Sil", systemImage: "trash.fill")
                        .frame(minWidth: 130)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.dryRun ? .blue : .red)
                .controlSize(.large)
                .disabled(!disk.canWipe || model.isBusy)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.bar)
        }
    }
}

// MARK: - Parcalar

private struct MethodCard: View {

    let method: WipeMethod
    let isSelected: Bool
    let diskSize: UInt64

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(method.title).font(.body.weight(.medium))
                    Spacer()
                    Text("\(method.passCount) gecis · \(ByteFormatter.string(diskSize * UInt64(method.passCount)))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(method.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.5) : .clear)
        )
        .contentShape(Rectangle())
    }
}

struct Badge: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.monospacedDigit())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))
    }
}
