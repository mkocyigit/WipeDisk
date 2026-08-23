import SwiftUI
import WipeKit

/// Diski yeniden bolumleme ve bicimlendirme ekrani.
///
/// Silme ekranindan farkli olarak burada ham aygita dokunulmaz; is `diskutil`e
/// devredilir. Yine de bolum tablosunu bastan yazdigi icin veri kaybi kesindir,
/// bu yuzden ayni onay surtunmesi uygulanir.
struct PartitionView: View {

    let disk: DiskInfo
    @EnvironmentObject private var model: AppModel

    private var plan: PartitionPlan { model.currentPlan(for: disk) }
    private var issues: [PartitionPlan.ValidationIssue] { plan.validate(against: disk) }
    private var blockingIssues: [PartitionPlan.ValidationIssue] { issues.filter(\.isBlocking) }
    private var warnings: [PartitionPlan.ValidationIssue] { issues.filter { !$0.isBlocking } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                currentLayout
                Divider()
                schemeSection
                Divider()
                plannedLayout
                if !issues.isEmpty {
                    issueSection
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) { actionBar }
        .onChange(of: disk.id) { model.resetPartitionPlan() }
    }

    // MARK: - Diskteki mevcut duzen

    private var currentLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diskteki mevcut duzen")
                .font(.headline)

            if disk.partitions.isEmpty {
                Text("Bolum tablosu yok — disk ham durumda.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(disk.partitions) { partition in
                    HStack(spacing: 10) {
                        VolumeRow(partition: partition)
                        // Bolum tablosuna dokunmadan yalnizca bu birimi bicimlendir.
                        Button("Bicimlendir") {
                            model.beginVolumeFormat(partition)
                        }
                        .buttonStyle(.link)
                        .disabled(model.isBusy)
                    }
                }
            }

            if let error = model.volumeActionError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Sema

    private var schemeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bolum tablosu semasi")
                .font(.headline)

            Picker("", selection: $model.scheme) {
                ForEach(PartitionScheme.allCases) { candidate in
                    Text(candidate.title).tag(candidate)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
        }
    }

    // MARK: - Planlanan duzen

    private var plannedLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Olusturulacak bolumler")
                    .font(.headline)
                Spacer()
                Text("\(model.partitions.count) bolum")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            proportionBar

            ForEach($model.partitions) { $partition in
                PartitionRow(
                    partition: $partition,
                    diskSize: disk.size,
                    isLast: model.partitions.last?.id == partition.id,
                    canRemove: model.partitions.count > 1,
                    onRemove: { remove(partition.id) }
                )
            }

            Button {
                addPartition()
            } label: {
                Label("Bolum ekle", systemImage: "plus")
            }
            .disabled(!canAddPartition)
        }
    }

    /// Planin disk uzerindeki dagilimini gosteren serit.
    private var proportionBar: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(model.partitions) { partition in
                    let width = geometry.size.width * fraction(of: partition)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color(for: partition.format))
                        .frame(width: max(width - 2, 2))
                        .overlay(alignment: .leading) {
                            if width > 62 {
                                Text(partition.format == .freeSpace ? "Bos" : partition.diskutilName)
                                    .font(.caption2)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .padding(.leading, 6)
                            }
                        }
                }
            }
        }
        .frame(height: 26)
    }

    private func fraction(of partition: PlannedPartition) -> Double {
        guard disk.size > 0 else { return 0 }
        if let bytes = partition.size.byteValue {
            return min(Double(bytes) / Double(disk.size), 1)
        }
        // Kalan alan: acikca verilmis boyutlardan arta kalan.
        let explicit = Double(plan.explicitBytes)
        return max(0, (Double(disk.size) - explicit) / Double(disk.size))
    }

    private func color(for format: VolumeFormat) -> Color {
        switch format {
        case .apfs: return .blue
        case .exfat: return .teal
        case .hfsPlus: return .indigo
        case .fat32: return .orange
        case .freeSpace: return .gray.opacity(0.55)
        }
    }

    // MARK: - Sorunlar

    private var issueSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                Label {
                    Text(issue.localizedDescription)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: issue.isBlocking ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                }
                .font(.callout)
                .foregroundStyle(issue.isBlocking ? Color.red : Color.orange)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill((blockingIssues.isEmpty ? Color.orange : Color.red).opacity(0.10))
        )
    }

    // MARK: - Eylem cubugu

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Disk boyutu")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(disk.formattedSize)
                        .font(.title3.monospacedDigit().weight(.semibold))
                }

                Spacer()

                if !warnings.isEmpty && blockingIssues.isEmpty {
                    Label("\(warnings.count) uyari", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }

                Button(role: .destructive) {
                    model.beginPartitionConfirmation()
                } label: {
                    Label("Bolumle ve Bicimlendir", systemImage: "square.split.2x1")
                        .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .disabled(!disk.canWipe || model.isBusy || !blockingIssues.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.bar)
        }
    }

    // MARK: - Duzenleme

    private var canAddPartition: Bool {
        guard !model.isBusy else { return false }
        if let limit = model.scheme.maximumPartitions {
            return model.partitions.count < limit
        }
        return model.partitions.count < 16
    }

    /// Yeni bolum eklenirken, kalan alani kullanan bolum sonda kalmalidir.
    private func addPartition() {
        let used = plan.explicitBytes
        let free = disk.size > used ? disk.size - used : 0
        let suggested = max(free / 2, 1_000_000_000)

        if let index = model.partitions.lastIndex(where: { $0.size == .remainder }) {
            model.partitions[index].size = .bytes(suggested)
        }
        model.partitions.append(
            PlannedPartition(
                name: "BOLUM\(model.partitions.count + 1)",
                format: .exfat,
                size: .remainder
            )
        )
    }

    private func remove(_ id: PlannedPartition.ID) {
        model.partitions.removeAll { $0.id == id }
        // Silinen son bolumse, yeni son bolum kalan alani devralir.
        if !model.partitions.isEmpty, !model.partitions.contains(where: { $0.size == .remainder }) {
            model.partitions[model.partitions.count - 1].size = .remainder
        }
    }
}

// MARK: - Tek bolum satiri

private struct PartitionRow: View {

    @Binding var partition: PlannedPartition
    let diskSize: UInt64
    let isLast: Bool
    let canRemove: Bool
    let onRemove: () -> Void

    /// Metin alaninda GB cinsinden duzenlenir; modelde bayt tutulur.
    @State private var sizeText = ""

    private var usesRemainder: Bool { partition.size == .remainder }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("Ad", text: $partition.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                    .disabled(partition.format == .freeSpace)

                Picker("", selection: $partition.format) {
                    ForEach(VolumeFormat.allCases) { format in
                        Text(format.shortTitle).tag(format)
                    }
                }
                .labelsHidden()
                .frame(width: 110)

                Spacer()

                if usesRemainder {
                    Text("Kalan alan")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    TextField("Boyut", text: $sizeText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 84)
                        .multilineTextAlignment(.trailing)
                        .onSubmit(commitSize)
                        .onChange(of: sizeText) { commitSize() }
                    Text("GB").foregroundStyle(.secondary)
                }

                // Son bolum diskin kalanini kaplayabilir; digerleri sabit boyutlu olmali.
                if isLast {
                    Toggle("Kalan", isOn: Binding(
                        get: { usesRemainder },
                        set: { newValue in
                            partition.size = newValue ? .remainder : .bytes(currentBytes)
                            syncText()
                        }
                    ))
                    .toggleStyle(.checkbox)
                }

                Button {
                    onRemove()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(!canRemove)
            }

            if partition.format == .freeSpace {
                Text("Bu aralik bicimlendirilmez, bos birakilir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.07))
        )
        .onAppear(perform: syncText)
    }

    private var currentBytes: UInt64 {
        partition.size.byteValue ?? max(diskSize / 2, 1_000_000_000)
    }

    private func syncText() {
        guard let bytes = partition.size.byteValue else { return }
        let gigabytes = Double(bytes) / 1_000_000_000
        sizeText = String(format: gigabytes < 10 ? "%.1f" : "%.0f", gigabytes)
    }

    private func commitSize() {
        guard !usesRemainder else { return }
        // Ondalik ayraci olarak virgul da kabul edilir.
        let normalized = sizeText.replacingOccurrences(of: ",", with: ".")
        guard let gigabytes = Double(normalized), gigabytes > 0 else { return }
        partition.size = .bytes(UInt64(gigabytes * 1_000_000_000))
    }
}
