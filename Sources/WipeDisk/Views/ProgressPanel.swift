import SwiftUI
import WipeKit

/// Calisan (veya bitmis) bir silme oturumunu gosteren panel.
struct ProgressPanel: View {

    let session: WipeSession
    @EnvironmentObject private var model: AppModel
    @State private var isConfirmingCancel = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if session.errorCode == "fullDiskAccess" {
                        fullDiskAccessHelp
                    }
                    // Bolumleme diskutil'e devredildigi icin bayt bazinda
                    // ilerleme uretmez; bos cubuk ve sifir sayac gostermek yerine
                    // dogrudan gunluge yer birakilir.
                    if session.kind.isByteTracked {
                        Divider()
                        bars
                        Divider()
                        stats
                    }
                    Divider()
                    logSection
                }
                .padding(24)
                .frame(maxWidth: 720, alignment: .leading)
            }
        }
        .safeAreaInset(edge: .bottom) { actionBar }
        .navigationTitle(session.disk.displayName)
        .navigationSubtitle(session.disk.deviceIdentifier)
        .confirmationDialog(
            "Silme durdurulsun mu?",
            isPresented: $isConfirmingCancel,
            titleVisibility: .visible
        ) {
            Button("Durdur", role: .destructive) { model.cancelWipe() }
            Button("Devam Et", role: .cancel) {}
        } message: {
            Text("Yarim kalan disk kismen silinmis olur; veriler geri gelmez.")
        }
    }

    // MARK: - Baslik

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            statusIcon
                .font(.system(size: 42))
                .foregroundStyle(accent)
                .frame(width: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.statusText)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(session.subtitle) · \(session.disk.formattedSize) · \(session.disk.deviceIdentifier)")
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    if session.isDryRun {
                        Badge(text: "Deneme modu", systemImage: "testtube.2")
                    }
                    if session.kind.isByteTracked {
                        Badge(text: "\(session.passCount) gecis", systemImage: "repeat")
                    }
                    Badge(text: session.startedAt.formatted(date: .omitted, time: .standard),
                          systemImage: "clock")
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch session.phase {
        case .starting, .writing:
            switch session.kind {
            case .wipe: Image(systemName: session.isDryRun ? "testtube.2" : "trash.fill")
            case .partition: Image(systemName: "square.split.2x1")
            case .formatVolume: Image(systemName: "eraser.fill")
            }
        case .verifying:
            Image(systemName: "checkmark.shield")
        case .finished:
            Image(systemName: "checkmark.circle.fill")
        case .failed:
            Image(systemName: "xmark.octagon.fill")
        case .cancelled:
            Image(systemName: "stop.circle.fill")
        }
    }

    private var accent: Color {
        switch session.phase {
        case .starting, .writing: return session.isDryRun ? .blue : .red
        case .verifying: return .blue
        case .finished: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }

    // MARK: - Tam Disk Erisimi yonlendirmesi

    /// macOS, fiziksel disk aygitlarini root icin bile TCC ile kapatir. Bu bir
    /// hata degil, eksik bir izindir; kullaniciyi dogrudan ilgili panele goturuyoruz.
    private var fullDiskAccessHelp: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Tam Disk Erisimi gerekiyor", systemImage: "lock.shield")
                .font(.headline)

            Text("""
                macOS, ham disk aygitlarina erisimi yonetici parolasindan bagimsiz olarak \
                ayri bir izne baglar. Asagidaki dugme ilgili paneli acar:
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                step(1, "Listeye **WipeDisk** uygulamasini ekleyin (+ dugmesi).")
                step(2, "Anahtari acik konuma getirin.")
                step(3, "WipeDisk'i tamamen kapatip yeniden acin — izin ancak yeniden baslatinca gecerli olur.")
            }

            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Tam Disk Erisimi Ayarlarini Ac", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.orange.opacity(0.45))
        )
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number).")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(.init(text))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Cubuklar

    private var bars: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Toplam ilerleme").font(.headline)
                    Spacer()
                    Text("%\(Int(session.overallFraction * 100))")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(accent)
                }
                ProgressView(value: session.overallFraction)
                    .progressViewStyle(.linear)
                    .tint(accent)
                HStack {
                    Text("\(ByteFormatter.string(session.overallDone)) / \(ByteFormatter.string(session.overallTotal))")
                    Spacer()
                    if let eta = session.eta {
                        Text("Kalan \(ByteFormatter.duration(eta))")
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(passTitle).font(.subheadline.weight(.medium))
                    Spacer()
                    Text("%\(Int(session.passFraction * 100))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: session.passFraction)
                    .progressViewStyle(.linear)
                    .tint(.secondary)
                Text("\(ByteFormatter.string(session.passDone)) / \(ByteFormatter.string(session.passTotal))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .opacity(session.passTotal > 0 ? 1 : 0.45)
        }
    }

    private var passTitle: String {
        switch session.phase {
        case .verifying:
            return "Dogrulama gecisi"
        default:
            let label = session.passLabel.isEmpty ? "" : " — \(session.passLabel)"
            return "Gecis \(max(session.passIndex, 1))/\(session.passCount)\(label)"
        }
    }

    // MARK: - Sayilar

    private var stats: some View {
        HStack(alignment: .top, spacing: 0) {
            stat("Hiz", ByteFormatter.rate(session.bytesPerSecond))
            stat("Gecen sure", ByteFormatter.duration(session.elapsed))
            stat("Kalan sure", session.eta.map(ByteFormatter.duration) ?? "—")
            stat("Yazilan", ByteFormatter.string(session.overallDone))
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit().weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Gunluk

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gunluk").font(.headline)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(session.log) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(line.timestamp.formatted(date: .omitted, time: .standard))
                                    .foregroundStyle(.tertiary)
                                Text(line.text)
                                    .foregroundStyle(line.isError ? Color.red : .primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .font(.caption.monospaced())
                            .id(line.id)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 190)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.08))
                )
                .onChange(of: session.log.count) {
                    // Son satir hep gorunsun.
                    guard let last = session.log.last else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Eylem cubugu

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                if session.phase.isActive {
                    ProgressView()
                        .controlSize(.small)
                    Text("Bilgisayari uyku moduna almayin ve diski cikarmayin.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Label(session.statusText, systemImage: finishedIconName)
                        .font(.callout)
                        .foregroundStyle(accent)
                }

                Spacer(minLength: 0)

                if session.phase.isActive {
                    // Bolumleme diskutil'e devredildigi icin yarida kesilemez.
                    if model.isCancellable {
                        Button(role: .destructive) {
                            isConfirmingCancel = true
                        } label: {
                            Label("Durdur", systemImage: "stop.fill")
                                .frame(minWidth: 100)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                } else {
                    Button {
                        model.dismissSession()
                    } label: {
                        Text("Kapat").frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.bar)
        }
    }

    private var finishedIconName: String {
        switch session.phase {
        case .finished: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .cancelled: return "stop.circle.fill"
        default: return "hourglass"
        }
    }
}
