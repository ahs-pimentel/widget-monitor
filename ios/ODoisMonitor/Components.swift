import SwiftUI

/// Cartão padrão (um tom acima do fundo, cantos 18).
struct Card<Content: View>: View {
    var gradient: LinearGradient?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(gradient.map { AnyShapeStyle($0) } ?? AnyShapeStyle(Palette.surface))
            }
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.06)))
    }
}

struct SectionTitle: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack {
            Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(0.6).foregroundStyle(Palette.secondary).lineLimit(1)
            Spacer()
            if let detail { Text(detail).font(.caption).foregroundStyle(Palette.secondary) }
        }
    }
}

struct Meter: View {
    let value: Double
    let color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                Capsule().fill(color.gradient).frame(width: value > 0 ? max(height, geo.size.width * min(max(value, 0), 1)) : 0)
            }
        }
        .frame(height: height)
    }
}

struct Ring<Content: View>: View {
    let value: Double
    let color: Color
    var lineWidth: CGFloat = 6
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.12), lineWidth: lineWidth)
            Circle().trim(from: 0, to: min(max(value, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            content
        }
    }
}

struct Bars: View {
    let values: [Double]
    let color: Color
    var highlightLast = false

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(values.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(!highlightLast || i == values.count - 1 ? 1 : 0.4))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(2, geo.size.height * min(max(values[i], 0), 1)))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

struct Chip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text).font(.caption2.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.16)))
    }
}

/// Imagem vinda do Mac (ícone de CLI ou avatar), carregada uma vez.
struct RemoteImage<Fallback: View>: View {
    let path: String
    @ViewBuilder var fallback: Fallback
    @State private var image: UIImage?
    @State private var loaded = false

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else if loaded { fallback }
            else { Palette.surfaceHigh }
        }
        .task(id: path) {
            image = await Repository.shared.image(path)
            loaded = true
        }
    }
}

/// Ícone da CLI: o do app no Mac ou a sigla sobre a cor dela, com anel opcional e ponto de atividade.
struct ProviderIcon: View {
    let provider: Provider
    var size: CGFloat = 32
    var ring: Double?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        let icon = Group {
            if provider.hasIcon == true {
                RemoteImage(path: "/v1/icons/\(provider.id).png") { fallback }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)

        ZStack(alignment: .bottomTrailing) {
            if let ring {
                Ring(value: ring, color: Palette.severity(ring), lineWidth: 2.5) { icon }
                    .frame(width: size + 10, height: size + 10)
            } else {
                icon
            }
            if provider.isActive {
                Circle().fill(.green).frame(width: size * 0.28, height: size * 0.28)
                    .overlay(Circle().stroke(Palette.background, lineWidth: 2))
            }
        }
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(colors: [Palette.hex(provider.tint), Palette.hex(provider.tint).opacity(0.7)], startPoint: .top, endPoint: .bottom)
            Text(provider.monogram ?? String(provider.name.prefix(1)))
                .font(.system(size: size * 0.36, weight: .black, design: .rounded)).foregroundStyle(.white)
        }
    }
}
