import MiraNoteKit
import SwiftUI

/// The star jar (team decision 2026-10-24, no design screen): every saved
/// page is a star colored by its mood, a week or a month to a jar. Drawn
/// in the app's own language -- paper, hairlines, quiet type. Its one
/// motion: pages saved since the jar was last opened drop in.
struct StarJarView: View {
    var viewModel: HomeViewModel
    var onBack: () -> Void = {}
    var onOpenNote: (JarStar) -> Void = { _ in }
    /// The shown pages not judged yet, to ask the mood of one at a time;
    /// `[]` when the jar closes.
    var onShow: ([Memory.ID]) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var period: JarPeriod = .month
    @State private var interval = JarPeriod.month.interval(containing: .now)
    /// Stars dropping in on this visit, in drop order; set once.
    @State private var arriving: [Memory.ID] = []
    @State private var visited = false
    @State private var viewport: CGFloat = 0

    /// When the jar was last opened: what was saved since drops in.
    static let lastOpenedKey = "starJar.lastOpened"

    private var stars: [JarStar] {
        StarJar.stars(in: viewModel.library, during: interval)
    }

    private var isCurrent: Bool { interval.contains(.now) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                periodPicker
                    .padding(.bottom, 10)
                periodStepper
                    .padding(.bottom, 14)
                jar
                    .padding(.bottom, 18)
                // An empty jar says so inside it.
                if !stars.isEmpty {
                    Text(summary)
                        .font(Sans.font(size: 16, weight: 600))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("jar.summary")
                        .padding(.bottom, 14)
                }
                legend
            }
            .padding(.horizontal, Metrics.chromeInset)
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewport = $0 }
        .screenBackground()
        .safeAreaInset(edge: .top) { header }
        .onAppear(perform: firstVisit)
        .task(id: interval) {
            onShow(stars.filter { $0.memory.mood == nil }.map(\.id))
        }
        .onDisappear { onShow([]) }
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Home")
                }
            }
            .buttonStyle(SoftPill())
            Spacer()
            Text("Star jar")
                .font(.miraScreenTitle)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Color.clear.frame(width: 64, height: 1)
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.vertical, 8)
        .background(Palette.paper.opacity(0.94))
    }

    private var periodPicker: some View {
        HStack(spacing: 6) {
            ForEach(JarPeriod.allCases, id: \.self) { option in
                Button(option == .week ? "Week" as LocalizedStringKey : "Month") {
                    period = option
                    interval = option.interval(containing: isCurrent ? .now : interval.start)
                }
                .buttonStyle(SoftPill(selected: option == period))
                .accessibilityAddTraits(option == period ? .isSelected : [])
                .accessibilityIdentifier("jar.period.\(option.rawValue)")
            }
        }
    }

    private var periodStepper: some View {
        HStack {
            stepButton("chevron.left", label: period == .week ? String(appCopy: "Previous week") : String(appCopy: "Previous month"),
                       id: "jar.previous") {
                interval = period.interval(shifting: interval, by: -1)
            }
            Spacer()
            Text(period.label(for: interval, locale: AppSettings.shared.language.locale))
                .font(.miraCardTitle)
                .foregroundStyle(Palette.ink)
                .accessibilityIdentifier("jar.period")
            Spacer()
            stepButton("chevron.right", label: period == .week ? String(appCopy: "Next week") : String(appCopy: "Next month"),
                       id: "jar.next") {
                interval = period.interval(shifting: interval, by: 1)
            }
            .disabled(isCurrent)
            .opacity(isCurrent ? 0.35 : 1)
        }
    }

    /// The 34 pt paper circle of reading mode's buttons, hit-tested at 44.
    private func stepButton(
        _ symbol: String, label: String, id: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(Palette.onInk)
                        .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
                )
                .padding(5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    // MARK: The jar

    private var jar: some View {
        GeometryReader { proxy in
            let geometry = JarGeometry(size: proxy.size)
            let pile = StarPile.layout(stars.map(\.id), in: geometry.interior)
            ZStack(alignment: .topLeading) {
                JarGlass(geometry: geometry)
                // After the visit has decided what drops in.
                ForEach(Array((visited ? stars : []).enumerated()), id: \.element.id) { index, star in
                    let spot = pile.spots[index]
                    StarButton(
                        star: star,
                        size: pile.starSize,
                        rotation: spot.rotation,
                        drop: dropOffset(for: star.id, at: spot.center, geometry: geometry),
                        delay: dropDelay(for: star.id),
                        reduceMotion: reduceMotion
                    ) {
                        onOpenNote(star)
                    }
                    .position(spot.center)
                }
                JarShine(geometry: geometry)
                JarLid(geometry: geometry)
                if stars.isEmpty {
                    Text(emptyLine)
                        .font(.miraBody)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(width: geometry.interior.width - 80)
                        .accessibilityIdentifier("jar.empty")
                        .position(x: geometry.interior.midX, y: geometry.interior.midY + 20)
                }
            }
            // Small stars hit-test at 1.3x: a tap between them opens the
            // nearest within 17 pt, so even a crowd keeps a 34 pt target
            // without one star covering another.
            .contentShape(Rectangle())
            .onTapGesture { point in
                guard visited else { return }
                let nearest = zip(stars, pile.spots)
                    .map { (star: $0, distance: hypot($1.center.x - point.x, $1.center.y - point.y)) }
                    .min { $0.distance < $1.distance }
                if let nearest, nearest.distance <= 17 { onOpenNote(nearest.star) }
            }
        }
        .aspectRatio(JarGeometry.aspect, contentMode: .fit)
        // As wide as fits, short enough that the count and legend stay on
        // screen on a small phone (the rest of the column is ~290 pt).
        .frame(maxWidth: min(320, max(220, (viewport - 290) * JarGeometry.aspect)))
    }

    private var emptyLine: String {
        switch (period, isCurrent) {
        case (.week, true): return String(appCopy: "No memories yet this week.")
        case (.month, true): return String(appCopy: "No memories yet this month.")
        case (.week, false): return String(appCopy: "No memories that week.")
        case (.month, false): return String(appCopy: "No memories that month.")
        }
    }

    private var summary: String {
        let count = stars.count
        switch (period, isCurrent) {
        case (.week, true): return String(appCopy: "\(count) memories this week")
        case (.month, true): return String(appCopy: "\(count) memories this month")
        case (.week, false): return String(appCopy: "\(count) memories that week")
        case (.month, false): return String(appCopy: "\(count) memories that month")
        }
    }

    private var legend: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 10) {
            ForEach(Mood.allCases, id: \.self) { mood in
                HStack(spacing: 6) {
                    Circle()
                        .fill(Palette.mood(mood))
                        .frame(width: 10, height: 10)
                    Text(mood.displayName)
                        .font(.miraCaption)
                        .foregroundStyle(Palette.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: 300)
    }

    // MARK: Arrivals

    /// Once per visit: what was saved since the jar was last opened drops
    /// in. A first visit drops the whole period once.
    private func firstVisit() {
        guard !visited else { return }
        visited = true
        let defaults = UserDefaults.standard
        let lastOpened = defaults.object(forKey: Self.lastOpenedKey) as? Date
        defaults.set(Date.now, forKey: Self.lastOpenedKey)
        arriving = stars
            .filter { star in
                guard let lastOpened else { return true }
                return (star.memory.savedAt ?? star.memory.createdAt) > lastOpened
            }
            .map(\.id)
        // Landed: a later switch of period shows these at rest.
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            arriving = []
        }
    }

    private func dropOffset(for id: Memory.ID, at center: CGPoint, geometry: JarGeometry) -> CGSize? {
        guard arriving.contains(id) else { return nil }
        // From the middle of the mouth, a little apart from each other.
        let spread = CGFloat(StarPile.unit(id, 7) - 0.5) * geometry.mouthWidth * 0.5
        return CGSize(width: geometry.size.width / 2 + spread - center.x, height: geometry.mouthY - center.y)
    }

    /// Staggered 0.08 s, squeezed so the last starts within 0.9 s.
    private func dropDelay(for id: Memory.ID) -> Double {
        guard let index = arriving.firstIndex(of: id) else { return 0 }
        let stagger = min(0.08, 0.9 / Double(max(1, arriving.count - 1)))
        return Double(index) * stagger
    }
}

// MARK: - Star

/// One star: a tap opens its page. It drops in from `drop` when given one
/// (or, under Reduce Motion, fades in), and its mood tints it with a short
/// cross-fade when the mood arrives.
private struct StarButton: View {
    let star: JarStar
    let size: CGFloat
    let rotation: Double
    let drop: CGSize?
    let delay: Double
    let reduceMotion: Bool
    let action: () -> Void

    @State private var landed = false

    var body: some View {
        let waiting = drop != nil && !landed
        Button(action: action) {
            StarMark(color: Palette.mood(star.memory.mood))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(waiting && !reduceMotion ? 0 : rotation))
                .frame(width: size * 1.3, height: size * 1.3)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .offset(waiting && !reduceMotion ? drop ?? .zero : .zero)
        .opacity(waiting ? 0 : 1)
        .animation(.easeInOut(duration: 0.6), value: star.memory.mood)
        .onAppear {
            guard drop != nil, !landed else { return }
            let motion: Animation = reduceMotion
                ? .easeOut(duration: 0.4)
                : .spring(response: 0.55, dampingFraction: 0.68)
            withAnimation(motion.delay(delay)) { landed = true }
        }
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("jar.star.\(star.memory.title)")
    }

    private var accessibilityText: String {
        let title = star.memory.title.isEmpty ? CaptionDate.string(for: star.memory.memoryDate) : star.memory.title
        return String(appCopy: "\(title), \(star.memory.mood?.displayName ?? String(appCopy: "mood not read yet"))")
    }
}

/// The star's face: the mood's fill, a soft light from above, and a
/// hairline edge so neighbors in a pile stay apart.
private struct StarMark: View {
    let color: Color

    var body: some View {
        RoundedStar()
            .fill(color)
            .overlay(
                RoundedStar().fill(
                    LinearGradient(colors: [Color.white.opacity(0.3), .clear], startPoint: .top, endPoint: .center)
                )
            )
            .overlay(RoundedStar().stroke(Palette.ink.opacity(0.1), lineWidth: 0.6))
    }
}

/// A five-point star with softened tips.
struct RoundedStar: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.04)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.5
        let points: [CGPoint] = (0..<10).map { index in
            let radius = index.isMultiple(of: 2) ? outer : inner
            let angle = -Double.pi / 2 + Double(index) * Double.pi / 5
            return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
        func toward(_ from: CGPoint, _ to: CGPoint, _ share: CGFloat) -> CGPoint {
            CGPoint(x: from.x + (to.x - from.x) * share, y: from.y + (to.y - from.y) * share)
        }
        var path = Path()
        for index in 0..<10 {
            let point = points[index]
            let previous = points[(index + 9) % 10]
            let next = points[(index + 1) % 10]
            let share: CGFloat = index.isMultiple(of: 2) ? 0.24 : 0.12
            let start = toward(point, previous, share)
            if index == 0 { path.move(to: start) } else { path.addLine(to: start) }
            path.addQuadCurve(to: toward(point, next, share), control: point)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Jar drawing

/// Where the jar's parts sit in its frame: a lid, a short neck, rounded
/// shoulders and a body with soft bottom corners.
struct JarGeometry {
    /// Width over height of the whole jar, lid included.
    static let aspect: CGFloat = 0.8

    let size: CGSize

    var lid: CGRect {
        let width = size.width * 0.5
        return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: size.height * 0.06)
    }

    var mouthWidth: CGFloat { size.width * 0.44 }
    /// The bottom of the neck: where dropping stars come in.
    var mouthY: CGFloat { lid.maxY + size.height * 0.035 }
    var shoulderY: CGFloat { mouthY + size.height * 0.12 }
    var corner: CGFloat { size.width * 0.16 }
    static let stroke: CGFloat = 1.5

    /// The inside of the body, where stars may lie.
    var interior: JarInterior {
        let inset = Self.stroke + 2
        return JarInterior(
            rect: CGRect(x: inset, y: shoulderY, width: size.width - 2 * inset, height: size.height - shoulderY - inset),
            corner: corner - inset
        )
    }

    func body(closed: Bool) -> Path {
        let left = (size.width - mouthWidth) / 2
        let right = left + mouthWidth
        let bottom = size.height - Self.stroke / 2
        let side = Self.stroke / 2
        let far = size.width - side
        var path = Path()
        path.move(to: CGPoint(x: left, y: lid.maxY))
        path.addLine(to: CGPoint(x: left, y: mouthY))
        path.addQuadCurve(to: CGPoint(x: side, y: shoulderY), control: CGPoint(x: side, y: mouthY))
        path.addLine(to: CGPoint(x: side, y: bottom - corner))
        path.addQuadCurve(to: CGPoint(x: side + corner, y: bottom), control: CGPoint(x: side, y: bottom))
        path.addLine(to: CGPoint(x: far - corner, y: bottom))
        path.addQuadCurve(to: CGPoint(x: far, y: bottom - corner), control: CGPoint(x: far, y: bottom))
        path.addLine(to: CGPoint(x: far, y: shoulderY))
        path.addQuadCurve(to: CGPoint(x: right, y: mouthY), control: CGPoint(x: far, y: mouthY))
        path.addLine(to: CGPoint(x: right, y: lid.maxY))
        if closed { path.closeSubpath() }
        return path
    }
}

/// Clear glass: a faint white body behind the stars, an ink hairline.
private struct JarGlass: View {
    let geometry: JarGeometry

    var body: some View {
        ZStack(alignment: .topLeading) {
            geometry.body(closed: true)
                .fill(Color.white.opacity(0.3))
            geometry.body(closed: false)
                .stroke(Palette.ink.opacity(0.18), style: StrokeStyle(lineWidth: JarGeometry.stroke, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// Two strokes of light down the front glass's left side, over the stars.
private struct JarShine: View {
    let geometry: JarGeometry

    var body: some View {
        let size = geometry.size
        Path { path in
            let x = size.width * 0.085
            path.move(to: CGPoint(x: x, y: geometry.shoulderY + size.height * 0.06))
            path.addLine(to: CGPoint(x: x, y: size.height * 0.62))
            path.move(to: CGPoint(x: x, y: size.height * 0.67))
            path.addLine(to: CGPoint(x: x, y: size.height * 0.71))
        }
        .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct JarLid: View {
    let geometry: JarGeometry

    var body: some View {
        let lid = geometry.lid
        RoundedRectangle(cornerRadius: lid.height * 0.35)
            .fill(Color(hex: 0xC6B298))
            .overlay(
                RoundedRectangle(cornerRadius: lid.height * 0.35)
                    .strokeBorder(Palette.ink.opacity(0.14), lineWidth: 1)
            )
            .frame(width: lid.width, height: lid.height)
            .offset(x: lid.minX, y: lid.minY)
            .accessibilityHidden(true)
    }
}

// MARK: - Pile

/// The body's inside: a rectangle with rounded bottom corners.
struct JarInterior {
    let rect: CGRect
    let corner: CGFloat

    var width: CGFloat { rect.width }
    var midX: CGFloat { rect.midX }
    var midY: CGFloat { rect.midY }
}

/// A settled pile: rows from the bottom up, every other row offset half a
/// star, each star nudged and turned by its page's id -- the same jar
/// looks the same every time. Stars are as large as fits with the pile
/// filling at most two thirds of the jar; a crowd shrinks them further
/// only as far as it must to fit at all.
enum StarPile {
    struct Spot {
        let center: CGPoint
        let rotation: Double
    }

    static let largest: CGFloat = 64
    /// The size a crowd shrinks from to fit the whole jar.
    static let crowdLargest: CGFloat = 26
    static let smallest: CGFloat = 10
    /// The share of the jar's height a pile may fill.
    static let fillShare: CGFloat = 2.0 / 3.0

    static func layout(_ ids: [UUID], in interior: JarInterior) -> (starSize: CGFloat, spots: [Spot]) {
        let size = starSize(ids.count, in: interior)
        let perRow = slots(size: size, width: interior.width)
        var spots: [Spot] = []
        var row = 0
        var placed = 0
        while placed < ids.count {
            let count = min(perRow - row % 2, ids.count - placed)
            let rowWidth = CGFloat(count) * size
            let startX = interior.midX - rowWidth / 2 + size / 2
            let y = interior.rect.maxY - size / 2 - CGFloat(row) * size * 0.84 - 1
            for slot in 0..<count {
                let id = ids[placed + slot]
                let jittered = CGPoint(
                    x: startX + CGFloat(slot) * size + CGFloat(unit(id, 0) - 0.5) * size * 0.3,
                    y: y + CGFloat(unit(id, 1) - 0.5) * size * 0.16
                )
                spots.append(Spot(
                    center: inside(jittered, radius: size / 2, interior: interior),
                    rotation: (unit(id, 2) - 0.5) * 44
                ))
            }
            placed += count
            row += 1
        }
        return (size, spots)
    }

    /// The largest size whose pile fills no more than `fillShare` of the
    /// jar, up to `largest`; never below what a crowd needs to fit at all.
    static func starSize(_ count: Int, in interior: JarInterior) -> CGFloat {
        var size = largest
        while size > smallest, pileHeight(count, size: size, width: interior.width)
                > interior.rect.height * fillShare {
            size -= 1
        }
        var crowd = crowdLargest
        while crowd > smallest, pileHeight(count, size: crowd, width: interior.width)
                > interior.rect.height * 0.9 {
            crowd -= 1
        }
        return max(size, crowd)
    }

    /// How tall the rows of `count` stars of `size` stand.
    static func pileHeight(_ count: Int, size: CGFloat, width: CGFloat) -> CGFloat {
        rowsNeeded(count, size: size, width: width) * size * 0.84
    }

    /// Stars in a full (even) row: the width less a margin, a star apiece.
    private static func slots(size: CGFloat, width: CGFloat) -> Int {
        max(2, Int((width - size * 0.4) / size))
    }

    private static func rowsNeeded(_ count: Int, size: CGFloat, width: CGFloat) -> CGFloat {
        let perPair = 2 * slots(size: size, width: width) - 1
        let pairs = count / perPair
        let rest = count % perPair
        return CGFloat(pairs * 2 + (rest == 0 ? 0 : (rest > slots(size: size, width: width) ? 2 : 1)))
    }

    /// Keeps a star of `radius` clear of the walls and the rounded bottom
    /// corners.
    private static func inside(_ point: CGPoint, radius: CGFloat, interior: JarInterior) -> CGPoint {
        let rect = interior.rect.insetBy(dx: radius, dy: radius)
        var point = CGPoint(x: min(max(point.x, rect.minX), rect.maxX), y: min(max(point.y, rect.minY), rect.maxY))
        let corner = interior.corner
        let reach = corner - radius
        guard reach > 0 else { return point }
        for centerX in [interior.rect.minX + corner, interior.rect.maxX - corner] {
            let cornerCenter = CGPoint(x: centerX, y: interior.rect.maxY - corner)
            let inCornerX = centerX < interior.midX ? point.x < cornerCenter.x : point.x > cornerCenter.x
            guard inCornerX, point.y > cornerCenter.y else { continue }
            let dx = point.x - cornerCenter.x, dy = point.y - cornerCenter.y
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance > reach {
                point = CGPoint(x: cornerCenter.x + dx / distance * reach, y: cornerCenter.y + dy / distance * reach)
            }
        }
        return point
    }

    /// A number in 0..<1 drawn from the id's bytes: stable across launches,
    /// unlike `hashValue`.
    static func unit(_ id: UUID, _ salt: Int) -> Double {
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        let a = Int(bytes[(salt * 2) % 16]), b = Int(bytes[(salt * 2 + 1) % 16])
        return Double(a << 8 | b) / 65536
    }
}
