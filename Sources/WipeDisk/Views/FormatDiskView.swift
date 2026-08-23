import SwiftUI
import WipeKit

/// Diskin tamamini tek adimda bicimlendirme ekrani.
///
/// Bolumleme ekraninin sadelestirilmis hali: tek birim, tek dosya sistemi.
/// Gunluk kullanimda istenen sey genelde budur.
struct FormatDiskView: View {

    let disk: DiskInfo
    @EnvironmentObject private var model: AppModel

    private var schemeMismatch: Bool {
        model.diskFormatScheme == .mbr && !model.diskFormat.supportsMBR
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                summary
                Divider()
                formatSection
                Divider()
                volumes
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) { actionBar }
    }

    // MARK: - Ozet

    private var summary: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "eraser.fill")
                .font(.system(size: 38))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text("Diski bicimlendir")
                    .font(.title2.weight(.semibold))
                Text("""
                    Bolum tablosu yeniden yazilir ve disk tek bir birim olur. \
                    Hizlidir ama veriyi uzerine yazmaz — veriyi kurtarilamaz \
                    kilmak icin Sil sekmesini kullanin.
                    """)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Bicim secimi

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Bicim")
                .font(.headline)

            Picker("Dosya sistemi", selection: $model.diskFormat) {
                ForEach(VolumeFormat.allCases.filter { $0 != .freeSpace }) { format in
                    Text(format.title).tag(format)
                }
            }

            Picker("Sema", selection: $model.diskFormatScheme) {
                ForEach(PartitionScheme.allCases) { scheme in
                    Text(scheme.title).tag(scheme)
                }
            }

            HStack {
                Text("Birim adi")
                    .frame(width: 106, alignment: .leading)
                TextField("Birim adi", text: $model.diskFormatName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
            }

            // NTFS macOS'ta olusturulabiliyor ama yazilamiyor; bunu bicimlendirmeden
            // once soylemek, sonradan "neden yazamiyorum" sorusunu onluyor.
            if !model.diskFormat.isWritableByMacOS {
                Label {
                    Text("""
                        macOS bu diski **salt okunur** baglayacak. Windows'ta tam \
                        okuma-yazma calisir; Mac'te yazmak icin ucuncu taraf surucu gerekir.
                        """)
                    .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle.fill")
                }
                .font(.callout)
                .foregroundStyle(.blue)
            }

            if model.diskFormat.needsExternalFormatter && !NTFSFormatter.isAvailable {
                Label(
                    "NTFS araci (mkntfs) pakette bulunamadi. Scripts/build-ntfsprogs.sh calistirilmali.",
                    systemImage: "xmark.octagon.fill"
                )
                .foregroundStyle(.red)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            }

            if schemeMismatch {
                Label(
                    "\(model.diskFormat.shortTitle), MBR semasinda kullanilamaz.",
                    systemImage: "xmark.octagon.fill"
                )
                .foregroundStyle(.red)
                .font(.callout)
            }

            if let limit = model.diskFormat.recommendedMaximum, disk.size > limit {
                Label(
                    "Bu disk \(model.diskFormat.shortTitle) icin buyuk (onerilen ust sinir \(ByteFormatter.string(limit))).",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Yok edilecek birimler

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
                    VolumeRow(partition: partition)
                }
            }
        }
    }

    // MARK: - Eylem cubugu

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sonuc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(model.diskFormat.shortTitle) · \(disk.formattedSize) · tek birim")
                        .font(.title3.monospacedDigit().weight(.semibold))
                }

                Spacer()

                Button(role: .destructive) {
                    model.beginFormatConfirmation()
                } label: {
                    Label("Diski Bicimlendir", systemImage: "eraser.fill")
                        .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
                .disabled(
                    !disk.canWipe || model.isBusy || schemeMismatch
                        || (model.diskFormat.needsExternalFormatter && !NTFSFormatter.isAvailable)
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.bar)
        }
    }
}

/// Bir birimi dosya sistemi, baglama durumu ve baglama eylemiyle gosterir.
struct VolumeRow: View {

    let partition: PartitionInfo
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: partition.isMounted ? "externaldrive.fill" : "externaldrive")
                .foregroundStyle(partition.isMounted ? Color.accentColor : .secondary)

            Text(partition.displayName)

            Text(partition.deviceIdentifier)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            Badge(text: partition.filesystemLabel, systemImage: "doc.text")

            // NTFS gibi macOS'un yazamadigi dosya sistemlerini acikca isaretle.
            if partition.isReadOnlyFilesystem {
                Badge(text: "Salt okunur", systemImage: "lock")
            }

            Spacer()

            Text(ByteFormatter.string(partition.size))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            if model.busyVolumeID == partition.deviceIdentifier {
                ProgressView().controlSize(.small)
            } else {
                Button(partition.isMounted ? "Ayir" : "Bagla") {
                    model.setMounted(partition, mounted: !partition.isMounted)
                }
                .buttonStyle(.link)
                .disabled(model.isBusy || model.busyVolumeID != nil)
            }
        }
        .font(.callout)
    }
}
