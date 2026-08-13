import SwiftUI
import WipeKit

/// Son onay. Kullanicinin aygit tanimlayicisini elle yazmasi gerekir —
/// yanlis diski secip refleksle "Tamam"a basmaya karsi kasitli bir surtunme.
struct ConfirmWipeSheet: View {

    let disk: DiskInfo
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @FocusState private var fieldFocused: Bool

    private var matches: Bool {
        typed.trimmingCharacters(in: .whitespaces).lowercased() == disk.deviceIdentifier.lowercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: model.dryRun ? "testtube.2" : "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(model.dryRun ? .blue : .red)

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.dryRun ? "Deneme calistirilacak" : "Bu islem geri alinamaz")
                        .font(.title3.weight(.semibold))
                    Text(model.dryRun
                        ? "Diske hicbir sey yazilmayacak."
                        : "\(disk.deviceIdentifier) uzerindeki tum veriler kalici olarak yok edilecek.")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    row("Disk", "\(disk.deviceIdentifier) — \(disk.mediaName.isEmpty ? disk.displayName : disk.mediaName)")
                    row("Boyut", disk.formattedSize)
                    row("Baglanti", disk.connectionSummary)
                    row("Yontem", "\(model.method.title) (\(model.method.passCount) gecis)")
                    row("Yazilacak", ByteFormatter.string(model.plannedBytes(for: disk)))
                    if model.verify { row("Dogrulama", "Son gecis geri okunacak") }
                    if model.reformat != .none { row("Sonrasinda", model.reformat.title) }

                    if !disk.partitions.isEmpty {
                        Divider().padding(.vertical, 2)
                        row("Yok edilecek birimler", disk.partitions.map(\.displayName).joined(separator: ", "))
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
                    .onSubmit { if matches { model.startWipe() } }
            }

            HStack {
                Spacer()
                Button("Vazgec", role: .cancel) { model.isConfirming = false }
                    .keyboardShortcut(.cancelAction)

                Button(model.dryRun ? "Denemeyi Baslat" : "Kalici Olarak Sil") {
                    model.startWipe()
                }
                .buttonStyle(.borderedProminent)
                .tint(model.dryRun ? .blue : .red)
                .disabled(!matches)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 520)
        .onAppear { fieldFocused = true }
    }

    private func row(_ label: String, _ value: String) -> some View {
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
