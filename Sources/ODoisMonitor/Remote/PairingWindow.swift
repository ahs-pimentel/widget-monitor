import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Janela "Parear celular": QR code com o endereço público e o token de um aparelho novo.
/// O token aparece só aqui, uma vez; no disco fica apenas o hash.
@MainActor
final class PairingWindow {
    static let shared = PairingWindow()
    private var window: NSWindow?

    func show() {
        let access = RemoteAccess.shared
        if !access.enabled { access.start() }
        // Códigos de abertas anteriores que nunca conectaram deixam de valer.
        for pending in access.devices where pending.lastSeenAt == nil { access.revoke(pending.id) }
        let name = "Celular · " + DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
        let (device, token) = access.pair(name: name)

        let payload: [String: Any] = [
            "v": 1,
            "url": access.publicURL?.absoluteString ?? "",
            "token": token,
            "host": Host.current().localizedName ?? "Mac",
            "device": device.name,
        ]
        let json = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
        let view = PairingView(access: access, qr: Self.qr(json), url: access.publicURL?.absoluteString ?? "—", deviceName: device.name)

        window?.close()
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 560),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        w.title = "Parear celular"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: view)
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private static func qr(_ data: Data) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

private struct PairingView: View {
    @ObservedObject var access: RemoteAccess
    let qr: NSImage?
    let url: String
    let deviceName: String

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(access.status.label).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(url).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            if let qr {
                Image(nsImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 240, height: 240)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
            }
            VStack(spacing: 4) {
                Text("Abra o oDois Monitor no Android e toque em **Parear**.")
                    .font(.system(size: 12))
                Text("Este código vale para um aparelho (\(deviceName)). Não compartilhe a imagem.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("APARELHOS PAREADOS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(access.devices) { d in
                    HStack {
                        Image(systemName: "iphone.gen3").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(d.name).font(.system(size: 11, weight: .medium))
                            Text(d.lastSeenAt.map { "Último acesso \(Format.relative($0))" } ?? "Ainda não conectou")
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Revogar") { access.revoke(d.id) }
                            .controlSize(.small)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 380)
    }

    private var statusColor: Color {
        switch access.status {
        case .online: return .green
        case .starting: return .orange
        case .off: return .gray
        case .error: return .red
        }
    }
}
