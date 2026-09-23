import AppKit
import SwiftUI

extension SkinColor {
    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    init(_ color: Color) {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(
            red: Double(resolved.redComponent),
            green: Double(resolved.greenComponent),
            blue: Double(resolved.blueComponent),
            alpha: Double(resolved.alphaComponent)
        )
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var format: (Double) -> String = { String(format: "%.2f", $0) }

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                if let step {
                    Slider(value: $value, in: range, step: step)
                } else {
                    Slider(value: $value, in: range)
                }
                Text(format(value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }
        } label: {
            Text(AirCardL10n.text(title))
        }
    }
}

struct ColorRow: View {
    let title: String
    @Binding var color: SkinColor

    var body: some View {
        ColorPicker(AirCardL10n.text(title), selection: Binding(
            get: { color.swiftUIColor },
            set: { color = SkinColor($0) }
        ), supportsOpacity: true)
    }
}

struct PercentFormat {
    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
    static func degrees(_ value: Double) -> String { "\(Int(value.rounded()))°" }
    static func points(_ value: Double) -> String { "\(Int(value.rounded()))" }
}

struct GradientBar: View {
    let stops: [GradientStop]

    var body: some View {
        LinearGradient(
            stops: stops.sorted { $0.location < $1.location }.map {
                Gradient.Stop(color: $0.color.swiftUIColor, location: $0.location)
            },
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 18)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(.quaternary))
    }
}

struct GradientStopsEditor: View {
    @Binding var stops: [GradientStop]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GradientBar(stops: stops)
            ForEach($stops) { $stop in
                HStack(spacing: 8) {
                    ColorPicker("", selection: Binding(
                        get: { stop.color.swiftUIColor },
                        set: { stop.color = SkinColor($0) }
                    ), supportsOpacity: true)
                    .labelsHidden()
                    Slider(value: $stop.location, in: 0...1)
                    Text(PercentFormat.percent(stop.location))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                    Button {
                        stops.removeAll { $0.id == stop.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .disabled(stops.count <= 2)
                }
            }
            Button {
                let last = stops.max { $0.location < $1.location }
                let color = last?.color ?? .white
                stops.append(GradientStop(color: color, location: min(1, (last?.location ?? 0.5) * 0.5 + 0.5)))
            } label: {
                Label("Añadir color", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(stops.count >= 12)
        }
    }
}

struct CardShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: rect.width * 0.047, style: .continuous)
    }
}

struct CardThumbnail: View {
    let image: NSImage?
    var width: CGFloat = 38

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay {
                        Image(systemName: "creditcard.fill")
                            .font(.system(size: width * 0.32))
                            .foregroundStyle(.white.opacity(0.9))
                    }
            }
        }
        .frame(width: width, height: width * 969 / 1536)
        .clipShape(CardShape())
        .overlay(CardShape().stroke(.white.opacity(0.15), lineWidth: 0.5))
    }
}
