import SwiftUI
import VisionKit

/// Primeiro acesso: lê o QR code de *Acesso remoto → Parear celular…* no Mac.
struct PairView: View {
    @ObservedObject var repo: Repository
    @State private var scanning = false
    @State private var busy = false
    @State private var error: String?
    @State private var manual = false
    @State private var code = ""

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image("AppIconImage").resizable().frame(width: 112, height: 112).clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            Text("oDois Monitor").font(.largeTitle.bold())
            Text("Acompanhe o monitor do seu Mac de qualquer lugar.\nNo Mac, abra o menu do monitor → Acesso remoto → Parear celular… e leia o QR code.")
                .multilineTextAlignment(.center).foregroundStyle(Palette.secondary)
            Button {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    scanning = true
                } else {
                    error = "Leitor de QR indisponível neste aparelho. Use “Colar código”."
                }
            } label: {
                Label(busy ? "Conferindo…" : "Ler QR code", systemImage: "qrcode.viewfinder")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent).tint(Palette.teal).disabled(busy)
            if manual {
                TextField("Código de pareamento", text: $code, axis: .vertical).lineLimit(3...6)
                    .textFieldStyle(.roundedBorder).autocorrectionDisabled().textInputAutocapitalization(.never)
                Button("Parear") { submit(code) }.disabled(busy || code.isEmpty)
            } else {
                Button("Colar código") { manual = true }.tint(Palette.teal)
            }
            if let error { Text(error).foregroundStyle(.red).multilineTextAlignment(.center) }
            Spacer()
        }
        .padding(28)
        .sheet(isPresented: $scanning) {
            QRScanner { value in
                scanning = false
                submit(value)
            }
            .ignoresSafeArea()
        }
    }

    private func submit(_ raw: String) {
        busy = true
        Task {
            error = await repo.pair(raw)
            busy = false
        }
    }
}

/// Câmera com leitura de QR (VisionKit). Devolve o primeiro código lido.
struct QRScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced, isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var done = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for case let .barcode(code) in items {
                if let value = code.payloadStringValue {
                    done = true
                    scanner.stopScanning()
                    onCode(value)
                    return
                }
            }
        }
    }
}
