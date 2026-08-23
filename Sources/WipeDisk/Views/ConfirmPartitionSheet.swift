import SwiftUI
import WipeKit

/// Bolumleme onayi. Silme onayiyla ayni surtunme: aygit tanimlayicisi elle yazilir.
struct ConfirmPartitionSheet: View {

    let disk: DiskInfo
    @EnvironmentObject private var model: AppModel
    @State private var typed = ""
    @FocusState private var fieldFocused: Bool

    private var plan: PartitionPlan { model.currentPlan(for: disk) }

    private var matches: Bool {
        typed.trimmingCharacters(in: .whitespaces).lowercased() == disk.deviceIdentifier.lowercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.red)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Bolum tablosu bastan yazilacak")
                        .font(.title3.weight(.semibold))
                    Text("\(disk.deviceIdentifier) uzerindeki butun veriler silinecek.")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    ConfirmRow(label: "Disk", value: "\(disk.deviceIdentifier) — \(disk.mediaName.isEmpty ? disk.displayName : disk.mediaName)")
                    ConfirmRow(label: "Boyut", value: disk.formattedSize)
                    ConfirmRow(label: "Sema", value: plan.scheme.rawValue)

                    Divider().padding(.vertical, 2)

                    ForEach(Array(plan.partitions.enumerated()), id: \.element.id) { index, partition in
                        ConfirmRow(
                            label: "Bolum \(index + 1)",
                            value: partition.format == .freeSpace
                                ? "Bos alan · \(sizeText(partition))"
                                : "\(partition.diskutilName) · \(partition.format.shortTitle) · \(sizeText(partition))"
                        )
                    }

                    if !disk.partitions.isEmpty {
                        Divider().padding(.vertical, 2)
                        ConfirmRow(
                            label: "Yok edilecek birimler",
                            value: disk.partitions.map(\.displayName).joined(separator: ", ")
                        )
                    }
                }
                .padding(4)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Onaylamak icin **\(disk.deviceIdentifier)** yazin:")
                    .font(.callout)
                TextField(disk.deviceIdentifier, text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .focused($fieldFocused)
                    .onSubmit { if matches { model.startPartitioning() } }
            }

            HStack {
                Spacer()
                Button("Vazgec", role: .cancel) { model.isConfirmingPartition = false }
                    .keyboardShortcut(.cancelAction)

                Button("Bolumle ve Bicimlendir") {
                    model.startPartitioning()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!matches)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 540)
        .onAppear { fieldFocused = true }
    }

    private func sizeText(_ partition: PlannedPartition) -> String {
        if let bytes = partition.size.byteValue {
            return ByteFormatter.string(bytes)
        }
        let remaining = disk.size > plan.explicitBytes ? disk.size - plan.explicitBytes : 0
        return "kalan alan (~\(ByteFormatter.string(remaining)))"
    }
}

/// Diskin tamamini bicimlendirme onayi.
struct ConfirmFormatSheet: View {

    let disk: DiskInfo
    @EnvironmentObject private var model: AppModel
    @State private var typed = ""
    @FocusState private var fieldFocused: Bool

    private var matches: Bool {
        typed.trimmingCharacters(in: .whitespaces).lowercased() == disk.deviceIdentifier.lowercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Disk bicimlendirilecek")
                        .font(.title3.weight(.semibold))
                    Text("\(disk.deviceIdentifier) uzerindeki butun birimler silinecek.")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    ConfirmRow(label: "Disk", value: "\(disk.deviceIdentifier) — \(disk.mediaName.isEmpty ? disk.displayName : disk.mediaName)")
                    ConfirmRow(label: "Boyut", value: disk.formattedSize)
                    ConfirmRow(label: "Bicim", value: model.diskFormat.title)
                    ConfirmRow(label: "Sema", value: model.diskFormatScheme.rawValue)
                    ConfirmRow(label: "Birim adi", value: model.diskFormatName)

                    if !disk.partitions.isEmpty {
                        Divider().padding(.vertical, 2)
                        ConfirmRow(
                            label: "Yok edilecek birimler",
                            value: disk.partitions.map(\.displayName).joined(separator: ", ")
                        )
                    }
                }
                .padding(4)
            }

            Label(
                "Bicimlendirme veriyi uzerine yazmaz; eski veri kurtarma araclariyla geri getirilebilir.",
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Onaylamak icin **\(disk.deviceIdentifier)** yazin:")
                    .font(.callout)
                TextField(disk.deviceIdentifier, text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .focused($fieldFocused)
                    .onSubmit { if matches { model.startDiskFormat() } }
            }

            HStack {
                Spacer()
                Button("Vazgec", role: .cancel) { model.isConfirmingFormat = false }
                    .keyboardShortcut(.cancelAction)

                Button("Diski Bicimlendir") { model.startDiskFormat() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(!matches)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 520)
        .onAppear { fieldFocused = true }
    }
}

/// Tek bir birimi, bolum tablosuna dokunmadan bicimlendirme onayi.
struct ConfirmVolumeFormatSheet: View {

    let partition: PartitionInfo
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "eraser.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Birim bicimlendirilecek")
                        .font(.title3.weight(.semibold))
                    Text("\(partition.deviceIdentifier) uzerindeki veriler silinecek. Diskin diger bolumlerine dokunulmaz.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    ConfirmRow(label: "Birim", value: partition.displayName)
                    ConfirmRow(label: "Aygit", value: partition.deviceIdentifier)
                    ConfirmRow(label: "Boyut", value: ByteFormatter.string(partition.size))
                    if let mount = partition.mountPoint {
                        ConfirmRow(label: "Baglama noktasi", value: mount)
                    }
                }
                .padding(4)
            }

            Picker("Dosya sistemi", selection: $model.volumeFormat) {
                ForEach(VolumeFormat.allCases.filter { $0 != .freeSpace }) { format in
                    Text(format.title).tag(format)
                }
            }

            TextField("Birim adi", text: $model.volumeFormatName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Vazgec", role: .cancel) { model.volumeToFormat = nil }
                    .keyboardShortcut(.cancelAction)

                Button("Bicimlendir") { model.startVolumeFormat() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 480)
    }
}

/// Onay sayfalarindaki etiket-deger satiri.
struct ConfirmRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            Text(value)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.callout)
    }
}
