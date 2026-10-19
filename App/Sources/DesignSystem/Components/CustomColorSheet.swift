import MiraNoteKit
import SwiftUI
import UIKit

/// The handoff's custom color sheet (screens 14 and 20; the Background
/// tool's page color uses it too): a 282 pt glass card with the curated
/// spectrum, the hue rail, the current swatch, an editable HEX and "Pick
/// color", which samples the page through a loupe.
///
/// Every change previews live through `onLiveChange`; Apply commits with
/// `onApply`. A swipe down on the top of the card cancels (`onCancel`):
/// the caller reverts its preview. The caller places the card (16 pt
/// gutters) and treats a tap outside it as cancel.
struct CustomColorSheet: View {
    let title: String
    let subtitle: String
    /// Prefixes the controls' accessibility identifiers.
    var idPrefix = "colorSheet"
    var onLiveChange: (RGBColor) -> Void
    var onApply: (RGBColor) -> Void
    var onCancel: () -> Void
    /// Renders the page for the eyedropper; nil hides "Pick color".
    var snapshot: (() -> UIImage?)?
    /// Opens straight into the eyedropper (the Background tool's "Pick").
    var picksOnAppear = false

    @State private var current: RGBColor
    @State private var spot: (x: Double, y: Double, rail: Double)
    @State private var hexText: String
    @State private var dragDown: CGFloat = 0
    @State private var picking: EyedropperSource?
    @FocusState private var hexFocused: Bool

    static let height: CGFloat = 282

    init(
        title: String,
        subtitle: String,
        initial: RGBColor,
        idPrefix: String = "colorSheet",
        onLiveChange: @escaping (RGBColor) -> Void,
        onApply: @escaping (RGBColor) -> Void,
        onCancel: @escaping () -> Void,
        snapshot: (() -> UIImage?)? = nil,
        picksOnAppear: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.idPrefix = idPrefix
        self.onLiveChange = onLiveChange
        self.onApply = onApply
        self.onCancel = onCancel
        self.snapshot = snapshot
        self.picksOnAppear = picksOnAppear
        _current = State(initialValue: initial)
        _spot = State(initialValue: ColorField.nearest(to: initial))
        _hexText = State(initialValue: initial.hex)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let inner = width - 40
            ZStack(alignment: .topLeading) {
                header(width: width)
                Text(subtitle)
                    .font(Sans.font(size: 13, weight: 500))
                    .foregroundStyle(Color(hex: 0x777267))
                    .lineLimit(1)
                    .offset(x: 19, y: 60)
                spectrum(width: inner)
                    .offset(x: 19, y: 82)
                label("HUE").offset(x: 19, y: 170)
                hueRail(width: inner - 48)
                    .offset(x: 19, y: 186)
                RoundedRectangle(cornerRadius: 10)
                    .fill(current.color)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(hex: 0xB28B7A), lineWidth: 1))
                    .frame(width: 34, height: 34)
                    .offset(x: width - 21 - 34, y: 180)
                    .accessibilityIdentifier("\(idPrefix).swatch")
                label("HEX").offset(x: 19, y: 208)
                hexField
                    .frame(width: inner - 126, height: 38)
                    .offset(x: 19, y: 227)
                if snapshot != nil {
                    pickButton.offset(x: width - 21 - 116, y: 227)
                }
            }
            .frame(width: width, height: Self.height, alignment: .topLeading)
        }
        .frame(height: Self.height)
        .background(background)
        .offset(y: dragDown)
        .onAppear {
            if picksOnAppear, let image = snapshot?() { picking = EyedropperSource(image: image) }
        }
        .fullScreenCover(item: $picking) { source in
            EyedropperView(image: source.image, idPrefix: idPrefix) { picked in
                picking = nil
                if let picked { set(picked, moveTarget: true) }
            }
            .presentationBackground(.clear)
        }
    }

    // MARK: Parts

    /// Grabber, title and Apply; a swipe down here cancels.
    private func header(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Capsule()
                .fill(Color(hex: 0xD7D1C5))
                .frame(width: 40, height: 4)
                .offset(x: (width - 40) / 2, y: 10)
            Text(title)
                .font(Sans.font(size: 17, weight: 700))
                .foregroundStyle(Palette.ink)
                .offset(x: 19, y: 28)
            Button { onApply(current) } label: {
                Text("Apply")
                    .font(Sans.font(size: 15, weight: 600))
                    .foregroundStyle(Palette.onInk)
                    .frame(width: 66, height: 34)
                    .background(Capsule().fill(Palette.selectedTool))
                    .minimumHitTarget()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(idPrefix).apply")
            .offset(x: width - 21 - 66, y: 22)
        }
        .frame(width: width, height: 58, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { dragDown = max(0, $0.translation.height) }
                .onEnded { value in
                    if value.translation.height > 60 || value.predictedEndTranslation.height > 140 {
                        onCancel()
                    } else {
                        withAnimation(.spring(duration: 0.25)) { dragDown = 0 }
                    }
                }
        )
        .accessibilityAction(named: "Cancel", onCancel)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(Sans.font(size: 12, weight: 600))
            .foregroundStyle(Color(hex: 0x777267))
    }

    private func spectrum(width: CGFloat) -> some View {
        let height: CGFloat = 82
        return Image(uiImage: SpectrumImage.render(rail: spot.rail))
            .resizable()
            .interpolation(.high)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(current.color)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                    .frame(width: 23, height: 23)
                    .shadow(color: Palette.ink.opacity(0.2), radius: 2, y: 1)
                    .offset(x: spot.x * width - 11.5, y: spot.y * height - 11.5)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        spot.x = min(max(value.location.x / width, 0), 1)
                        spot.y = min(max(value.location.y / height, 0), 1)
                        set(ColorField.color(x: spot.x, y: spot.y, rail: spot.rail), moveTarget: false)
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Shade")
            .accessibilityValue(current.hex)
            .accessibilityIdentifier("\(idPrefix).spectrum")
    }

    private func hueRail(width: CGFloat) -> some View {
        let travel = width - 22
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(LinearGradient(
                    stops: ColorField.railStops.map { .init(color: $0.color.color, location: $0.position) },
                    startPoint: .leading, endPoint: .trailing
                ))
                .frame(height: 12)
            Circle()
                .fill(.white)
                .overlay(Circle().strokeBorder(Palette.selectedTool, lineWidth: 2))
                .frame(width: 22, height: 22)
                .offset(x: spot.rail * travel)
        }
        .frame(width: width, height: 22)
        .contentShape(Rectangle().inset(by: -11))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    spot.rail = min(max((value.location.x - 11) / travel, 0), 1)
                    set(ColorField.color(x: spot.x, y: spot.y, rail: spot.rail), moveTarget: false)
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Hue")
        .accessibilityValue("\(Int(spot.rail * 100)) percent")
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 0.05 : -0.05
            spot.rail = min(max(spot.rail + step, 0), 1)
            set(ColorField.color(x: spot.x, y: spot.y, rail: spot.rail), moveTarget: false)
        }
        .accessibilityIdentifier("\(idPrefix).hue")
    }

    private var hexField: some View {
        HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 6)
                .fill(current.color)
                .frame(width: 24, height: 24)
            TextField("#RRGGBB", text: $hexText)
                .font(Sans.font(size: 16, weight: 600))
                .foregroundStyle(Palette.selectedTool)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($hexFocused)
                .submitLabel(.done)
                .accessibilityIdentifier("\(idPrefix).hex")
                .onChange(of: hexText) { _, typed in
                    let cleaned = Self.cleanHex(typed)
                    if cleaned != typed {
                        hexText = cleaned
                        return
                    }
                    // Typed, not echoed: a drag writes the current color's
                    // hex here too, and must not snap its own target.
                    if cleaned != current.hex, let color = RGBColor(hex: cleaned) {
                        set(color, moveTarget: true)
                    }
                }
                .onChange(of: hexFocused) { _, focused in
                    // An unfinished value goes back to the last valid one.
                    if !focused { hexText = current.hex }
                }
        }
        .padding(.leading, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(.white)
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color(hex: 0xDCD6C8), lineWidth: 1))
        )
    }

    private var pickButton: some View {
        Button {
            hexFocused = false
            if let image = snapshot?() { picking = EyedropperSource(image: image) }
        } label: {
            HStack(spacing: 7) {
                Image("color.eyedropper")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 20, height: 20)
                Text("Pick color")
                    .font(Sans.font(size: 13, weight: 600))
            }
            .foregroundStyle(Palette.onInk)
            .padding(.leading, 8)
            .frame(width: 116, height: 38, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 11).fill(Palette.selectedTool))
            .minimumHitTarget()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(idPrefix).pick")
    }

    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 30)
        return shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(Palette.paper.opacity(0.5)))
            .overlay(InnerTopHighlight(shape: shape))
            .overlay(shape.strokeBorder(Color.white.opacity(0.46), lineWidth: 1))
            .shadow(color: Palette.ink.opacity(0.16), radius: 18, y: 18)
    }

    // MARK: State

    /// A new current color: previewed live; a typed or sampled one also
    /// moves the target and handle to where the field shows it.
    private func set(_ color: RGBColor, moveTarget: Bool) {
        current = color
        if moveTarget { spot = ColorField.nearest(to: color) }
        if !hexFocused || moveTarget { hexText = color.hex }
        onLiveChange(color)
    }

    /// "#" plus up to six uppercase hex digits.
    static func cleanHex(_ text: String) -> String {
        let digits = text.uppercased().filter { $0.isHexDigit }
        return "#" + String(digits.prefix(6))
    }
}

extension RGBColor {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }

    init(_ color: Color) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.init(red: Double(red), green: Double(green), blue: Double(blue))
    }
}

/// The spectrum bitmap, drawn from the same function the picker samples.
enum SpectrumImage {
    private static var cache: (rail: Double, image: UIImage)?

    static func render(rail: Double) -> UIImage {
        if let cache, abs(cache.rail - rail) < 0.001 { return cache.image }
        let columns = 151, rows = 41
        var pixels = [UInt8](repeating: 255, count: columns * rows * 4)
        for row in 0..<rows {
            for column in 0..<columns {
                let color = ColorField.color(
                    x: Double(column) / Double(columns - 1), y: Double(row) / Double(rows - 1), rail: rail
                )
                let index = (row * columns + column) * 4
                pixels[index] = UInt8(min(max(color.red, 0), 1) * 255)
                pixels[index + 1] = UInt8(min(max(color.green, 0), 1) * 255)
                pixels[index + 2] = UInt8(min(max(color.blue, 0), 1) * 255)
            }
        }
        let image = pixels.withUnsafeMutableBytes { buffer -> UIImage in
            guard let context = CGContext(
                data: buffer.baseAddress, width: columns, height: rows, bitsPerComponent: 8,
                bytesPerRow: columns * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ), let cgImage = context.makeImage() else { return UIImage() }
            return UIImage(cgImage: cgImage)
        }
        cache = (rail, image)
        return image
    }
}

private struct EyedropperSource: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// "Pick color": the page as a picture under a dim veil. Drag to move the
/// loupe, lift to take the color under its center; Cancel keeps the sheet's
/// color. Samples the page only -- "from your memory", not the screen.
struct EyedropperView: View {
    let image: UIImage
    var idPrefix = "colorSheet"
    let onDone: (RGBColor?) -> Void

    @State private var touch: CGPoint?
    @State private var sample: RGBColor?

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Drag to pick a color")
                    .font(Sans.font(size: 16, weight: 600))
                    .foregroundStyle(Palette.onInk)
                Spacer()
                Button("Cancel") { onDone(nil) }
                    .buttonStyle(NavPill(prominent: false, width: NavPill.leadingWidth))
                    .accessibilityIdentifier("\(idPrefix).pick.cancel")
            }
            .padding(.horizontal, Metrics.chromeInset)
            GeometryReader { geo in
                let frame = fitted(in: geo.size)
                Image(uiImage: image)
                    .resizable()
                    .frame(width: frame.width, height: frame.height)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .position(x: frame.midX, y: frame.midY)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let point = clamp(value.location, to: frame)
                                touch = point
                                sample = pixel(at: point, in: frame)
                            }
                            .onEnded { _ in onDone(sample) }
                    )
                    .overlay {
                        if let touch {
                            Loupe(image: image, point: touch, frame: frame, color: sample?.color ?? .clear)
                        }
                    }
                    .accessibilityIdentifier("\(idPrefix).pick.page")
            }
            .padding(.horizontal, Metrics.chromeInset)
        }
        .padding(.vertical, 12)
        .background(Color(hex: 0x293322).opacity(0.92).ignoresSafeArea())
    }

    private func fitted(in size: CGSize) -> CGRect {
        let scale = min(size.width / image.size.width, size.height / image.size.height)
        let width = image.size.width * scale, height = image.size.height * scale
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    private func clamp(_ point: CGPoint, to frame: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, frame.minX), frame.maxX - 1), y: min(max(point.y, frame.minY), frame.maxY - 1))
    }

    private func pixel(at point: CGPoint, in frame: CGRect) -> RGBColor? {
        guard let cgImage = image.cgImage else { return nil }
        let x = Int((point.x - frame.minX) / frame.width * CGFloat(cgImage.width))
        let y = Int((point.y - frame.minY) / frame.height * CGFloat(cgImage.height))
        var rgba = [UInt8](repeating: 0, count: 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.translateBy(x: CGFloat(-x), y: CGFloat(y - cgImage.height + 1))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
            return true
        }
        guard drawn else { return nil }
        return RGBColor(red: Double(rgba[0]) / 255, green: Double(rgba[1]) / 255, blue: Double(rgba[2]) / 255)
    }
}

/// A 64 pt magnifier held above the finger, ringed in the color under it.
private struct Loupe: View {
    let image: UIImage
    let point: CGPoint
    let frame: CGRect
    let color: Color

    private let size: CGFloat = 64
    private let zoom: CGFloat = 4

    var body: some View {
        let lift: CGFloat = point.y - frame.minY > 90 ? -72 : 72
        Image(uiImage: image)
            .resizable()
            .frame(width: frame.width * zoom, height: frame.height * zoom)
            .offset(
                x: size / 2 - (point.x - frame.minX) * zoom,
                y: size / 2 - (point.y - frame.minY) * zoom
            )
            .frame(width: size, height: size, alignment: .topLeading)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(color, lineWidth: 6))
            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
            .overlay(Circle().stroke(Palette.ink.opacity(0.6), lineWidth: 1).frame(width: 6, height: 6))
            .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
            .position(x: point.x, y: point.y + lift)
            .allowsHitTesting(false)
    }
}
