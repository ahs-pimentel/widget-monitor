import AppKit
import Collaboration
import SwiftUI

/// Foto da conta do macOS (local, sem rede); sem foto, as iniciais sobre o gradiente.
struct UserAvatar: View {
    let name: String?
    var size: CGFloat = 36

    /// Lida uma vez: a foto da conta não muda durante a execução.
    private static let photo: NSImage? = CBUserIdentity(posixUID: getuid(), authority: .default())?.image

    var body: some View {
        ZStack {
            if let photo = Self.photo {
                Image(nsImage: photo).resizable().scaledToFill()
            } else {
                SeaStyle.hero
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .padding(2)
        .background(Circle().fill(SeaStyle.hero))
    }

    private var initials: String {
        let parts = (name ?? "").split(separator: " ").filter { !$0.isEmpty }
        let letters = [parts.first, parts.count > 1 ? parts.last : nil].compactMap { $0?.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}
