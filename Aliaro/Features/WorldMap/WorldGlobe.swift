import SwiftUI
import UIKit

/// The country outlines of `world_map.json` as points on a unit sphere. The
/// file is in the Natural Earth projection (2000 wide), so each vertex is
/// projected back to longitude / latitude.
final class GlobeData {
    static let shared = GlobeData()

    struct Ring {
        /// Unit vectors, 3 floats per point.
        let xyz: [Float]
        /// Segment i→i+1 runs along the ±180° seam (not drawn).
        let cut: [Bool]
        var count: Int { xyz.count / 3 }
    }

    struct Country {
        let code: String
        let rings: [Ring]
        /// Direction of the mainland's center.
        let center: SIMD3<Float>
    }

    let countries: [Country]
    /// Meridians and parallels every 30°.
    let graticule: [Ring]
    let maxPoints: Int

    /// Natural Earth projection fitted to the file: x centered, equator at y = 514.
    private static let equatorY = 514.0

    private static func neY(_ p: Double) -> Double {
        let p2 = p * p, p4 = p2 * p2
        return p * (1.007226 + p2 * (0.015085 + p4 * (-0.044475 + 0.028874 * p2 - 0.005916 * p4)))
    }

    private static func neYPrime(_ p: Double) -> Double {
        let p2 = p * p, p4 = p2 * p2
        return 1.007226 + p2 * (3 * 0.015085 + p4 * (-7 * 0.044475 + 9 * 0.028874 * p2 - 11 * 0.005916 * p4))
    }

    private static func neL(_ p: Double) -> Double {
        let p2 = p * p, p4 = p2 * p2
        return 0.8707 - 0.131979 * p2 + p4 * (-0.013791 + p4 * (0.003971 * p2 - 0.001529 * p4))
    }

    private static func unit(lat: Double, lon: Double) -> [Float] {
        [Float(cos(lat) * sin(lon)), Float(sin(lat)), Float(cos(lat) * cos(lon))]
    }

    private init() {
        let map = WorldMapData.shared
        let half = Double(map.size.width) / 2
        let scale = half / (0.8707 * .pi)
        let seam = Double.pi * 179.3 / 180

        countries = map.rawCountries.map { entry in
            let rings: [Ring] = entry.rings.filter { $0.count >= 6 }.map { raw in
                let n = raw.count / 2
                var xyz = [Float](repeating: 0, count: n * 3)
                var lons = [Double](repeating: 0, count: n)
                for i in 0..<n {
                    let t = (Self.equatorY - raw[i * 2 + 1]) / scale
                    var p = min(max(t, -1.5), 1.5)
                    for _ in 0..<8 {
                        let d = (Self.neY(p) - t) / Self.neYPrime(p)
                        p -= d
                        if abs(d) < 1e-7 { break }
                    }
                    p = min(max(p, -.pi / 2), .pi / 2)
                    let lam = min(max((raw[i * 2] - half) / scale / Self.neL(p), -.pi), .pi)
                    lons[i] = lam
                    let v = Self.unit(lat: p, lon: lam)
                    xyz[i * 3] = v[0]; xyz[i * 3 + 1] = v[1]; xyz[i * 3 + 2] = v[2]
                }
                let cut = (0..<n).map { i in i < n - 1 && abs(lons[i]) > seam && abs(lons[i + 1]) > seam }
                return Ring(xyz: xyz, cut: cut)
            }
            var c = SIMD3<Float>(0, 0, 0)
            if let main = rings.max(by: { $0.count < $1.count }) {
                for i in 0..<main.count { c += SIMD3(main.xyz[i * 3], main.xyz[i * 3 + 1], main.xyz[i * 3 + 2]) }
            }
            let len = (c * c).sum().squareRoot()
            return Country(code: entry.code, rings: rings, center: len > 0 ? c / len : SIMD3(0, 0, 1))
        }

        func ring(_ points: [(Double, Double)]) -> Ring {
            let xyz = points.flatMap { Self.unit(lat: $0.0 * .pi / 180, lon: $0.1 * .pi / 180) }
            return Ring(xyz: xyz, cut: Array(repeating: false, count: points.count))
        }
        let meridians = stride(from: -180, to: 180, by: 30).map { lon in
            ring(stride(from: -80, through: 80, by: 4).map { (Double($0), Double(lon)) })
        }
        let parallels = [-60, -30, 0, 30, 60].map { lat in
            ring(stride(from: -180, through: 180, by: 4).map { (Double(lat), Double($0)) })
        }
        graticule = meridians + parallels
        maxPoints = max(countries.flatMap(\.rings).map(\.count).max() ?? 0, graticule.map(\.count).max() ?? 0)
    }
}

/// Rotates unit vectors by the globe's yaw / pitch and maps them to the screen.
private final class GlobeProjector {
    var cosYaw: Float = 1, sinYaw: Float = 0, cosPitch: Float = 1, sinPitch: Float = 0
    var radius: CGFloat = 1, center: CGPoint = .zero
    var bx: [Float], by: [Float], bz: [Float]

    init(maxPoints: Int) {
        bx = Array(repeating: 0, count: maxPoints)
        by = Array(repeating: 0, count: maxPoints)
        bz = Array(repeating: 0, count: maxPoints)
    }

    func setup(yaw: Double, pitch: Double, radius: CGFloat, center: CGPoint) {
        cosYaw = Float(cos(yaw)); sinYaw = Float(sin(yaw))
        cosPitch = Float(cos(pitch)); sinPitch = Float(sin(pitch))
        self.radius = radius; self.center = center
    }

    /// Rotated vector; z > 0 faces the viewer.
    func rotate(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let x1 = v.x * cosYaw + v.z * sinYaw
        let z1 = -v.x * sinYaw + v.z * cosYaw
        return SIMD3(x1, v.y * cosPitch - z1 * sinPitch, v.y * sinPitch + z1 * cosPitch)
    }

    /// Rotates a ring into the buffers. Returns whether any point faces the viewer.
    func load(_ ring: GlobeData.Ring) -> Bool {
        var visible = false
        ring.xyz.withUnsafeBufferPointer { p in
            for i in 0..<ring.count {
                let x = p[i * 3], y = p[i * 3 + 1], z = p[i * 3 + 2]
                let x1 = x * cosYaw + z * sinYaw
                let z1 = -x * sinYaw + z * cosYaw
                bx[i] = x1
                by[i] = y * cosPitch - z1 * sinPitch
                bz[i] = y * sinPitch + z1 * cosPitch
                if bz[i] > 0 { visible = true }
            }
        }
        return visible
    }

    func point(_ x: Float, _ y: Float) -> CGPoint {
        CGPoint(x: center.x + radius * CGFloat(x), y: center.y - radius * CGFloat(y))
    }

    private func horizon(_ i: Int, _ j: Int) -> CGPoint {
        let t = bz[i] / (bz[i] - bz[j])
        var x = bx[i] + (bx[j] - bx[i]) * t
        var y = by[i] + (by[j] - by[i]) * t
        let l = max((x * x + y * y).squareRoot(), 0.0001)
        x /= l; y /= l
        return point(x, y)
    }

    /// Filled outline of the loaded ring; hidden points slide onto the horizon.
    func fill(_ path: inout Path, count n: Int) {
        for i in 0..<n {
            if i > 0 && (bz[i - 1] > 0) != (bz[i] > 0) { path.addLine(to: horizon(i - 1, i)) }
            var x = bx[i], y = by[i]
            if bz[i] <= 0 { let l = max((x * x + y * y).squareRoot(), 0.0001); x /= l; y /= l }
            if i == 0 { path.move(to: point(x, y)) } else { path.addLine(to: point(x, y)) }
        }
        path.closeSubpath()
    }

    /// Visible edges of the loaded ring.
    func stroke(_ path: inout Path, count n: Int, cut: [Bool]) {
        var pen = false
        guard n > 1 else { return }
        for i in 1..<n {
            if cut[i - 1] { pen = false; continue }
            let a = bz[i - 1] > 0, b = bz[i] > 0
            if a && b {
                if !pen { path.move(to: point(bx[i - 1], by[i - 1])) }
                path.addLine(to: point(bx[i], by[i])); pen = true
            } else if a {
                if !pen { path.move(to: point(bx[i - 1], by[i - 1])) }
                path.addLine(to: horizon(i - 1, i)); pen = false
            } else if b {
                path.move(to: horizon(i - 1, i))
                path.addLine(to: point(bx[i], by[i])); pen = true
            } else {
                pen = false
            }
        }
    }
}

/// Spin, tilt and every animation of the globe, stepped once per frame.
private final class GlobeMotion {
    static let startYaw = -0.15     // ≈ 9°E: Europe / Africa
    static let restPitch = 0.42
    static let autoSpin = 0.10      // rad/s
    static let introLength = 1.7

    struct FillAnim {
        var from: Double, to: Double, start: Date, duration: Double, bouncy: Bool

        func value(at now: Date) -> Double {
            let p = min(max(now.timeIntervalSince(start) / duration, 0), 1)
            let eased = bouncy ? 1 - exp(-5 * p) * cos(9 * p) : 1 - pow(1 - p, 3)
            return p >= 1 ? to : from + (to - from) * eased
        }
    }

    struct Tween {
        var fromYaw: Double, toYaw: Double, fromPitch: Double, toPitch: Double, start: Date, duration: Double
    }

    var yaw = startYaw - 1.8
    var pitch = 0.15
    var velYaw = 0.0, velPitch = 0.0
    var dragging = false
    var lastTouch = Date.distantPast
    var lastStep: Date?
    var appeared: Date?
    var introDone = false
    var tween: Tween?
    var fills: [String: FillAnim] = [:]
    var pulses: [String: Date] = [:]
    var lastTargets: [String: Color?]?
    /// Current color of each visited country (changes are instant; only showing / hiding animates).
    var colors: [String: Color] = [:]
    var radius: CGFloat = 150
    var time = 0.0

    var intro: Double {
        guard let appeared else { return 0 }
        let p = min(max(Date().timeIntervalSince(appeared) / 0.9, 0), 1)
        return 1 - pow(1 - p, 3)
    }

    func fill(_ code: String, at now: Date) -> Double { fills[code]?.value(at: now) ?? 0 }

    func step(_ now: Date) {
        let dt = min(lastStep.map { now.timeIntervalSince($0) } ?? 0, 0.05)
        lastStep = now
        time += dt
        if appeared == nil {
            appeared = now
            tween = Tween(fromYaw: yaw, toYaw: Self.startYaw, fromPitch: pitch, toPitch: Self.restPitch, start: now, duration: Self.introLength)
        }

        if let t = tween {
            let p = min(max(now.timeIntervalSince(t.start) / t.duration, 0), 1)
            let e = p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
            yaw = t.fromYaw + (t.toYaw - t.fromYaw) * e
            pitch = t.fromPitch + (t.toPitch - t.fromPitch) * e
            if p >= 1 {
                tween = nil
                if !introDone { introDone = true; lastTouch = now.addingTimeInterval(-1.5) }
            }
            return
        }
        guard !dragging else { return }

        // Fling inertia.
        if abs(velYaw) > 0.001 || abs(velPitch) > 0.001 {
            yaw += velYaw * dt
            pitch = clampPitch(pitch + velPitch * dt)
            let decay = exp(-2.8 * dt)
            velYaw *= decay; velPitch *= decay
            if abs(velYaw) < 0.05 && abs(velPitch) < 0.05 { velYaw = 0; velPitch = 0 }
            return
        }

        // Idle spin, easing in, and the tilt drifting back to rest.
        let idle = now.timeIntervalSince(lastTouch) - 2.5
        guard idle > 0 else { return }
        let ease = min(1, idle / 1.5)
        yaw += Self.autoSpin * ease * dt
        pitch += (Self.restPitch - pitch) * min(1, dt * 0.6 * ease)
    }

    func clampPitch(_ p: Double) -> Double { min(max(p, -1.25), 1.25) }

    /// New fill targets: a wave on load / filter change; a pop, spin and
    /// pulse for a single newly marked country.
    func update(targets colorTargets: [String: Color?], countries: [GlobeData.Country], now: Date) {
        for (code, color) in colorTargets { if let color { colors[code] = color } }
        let targets = colorTargets.mapValues { $0 == nil ? 0.0 : 1.0 }
        let previous = lastTargets
        lastTargets = colorTargets
        var added: Set<String> = []
        if let previous, introDone {
            added = Set(colorTargets.filter { $0.value != nil && (previous[$0.key] ?? nil) == nil }.keys)
        }
        let single = added.count == 1
        if single, let code = added.first, let country = countries.first(where: { $0.code == code }) {
            focus(on: country, now: now)
        }
        for country in countries {
            let target = targets[country.code] ?? 0
            let current = fill(country.code, at: now)
            if current == target && (fills[country.code]?.to ?? 0) == target { continue }
            if single && added.contains(country.code) {
                fills[country.code] = FillAnim(from: current, to: target, start: now.addingTimeInterval(0.65), duration: 0.9, bouncy: true)
            } else {
                // Wave from west to east of what's facing us.
                let lon = Double(atan2(country.center.x, country.center.z)) + yaw
                let wrapped = ((lon / (2 * .pi)).truncatingRemainder(dividingBy: 1) + 1.5).truncatingRemainder(dividingBy: 1)
                let delay = introDone ? wrapped * 0.35 : 0.7 + wrapped * 0.9
                fills[country.code] = FillAnim(from: current, to: target, start: now.addingTimeInterval(delay), duration: target > current ? 0.55 : 0.35, bouncy: false)
            }
        }
    }

    private func focus(on country: GlobeData.Country, now: Date) {
        let lon = Double(atan2(country.center.x, country.center.z))
        let lat = Double(asin(min(max(country.center.y, -1), 1)))
        var delta = (-lon - yaw).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        velYaw = 0; velPitch = 0
        tween = Tween(fromYaw: yaw, toYaw: yaw + delta, fromPitch: pitch, toPitch: min(max(lat, -1), 1), start: now, duration: 1.1)
        lastTouch = now.addingTimeInterval(1.5)
        pulses[country.code] = now.addingTimeInterval(0.7)
    }
}

/// Mixes two colors (resolved for the current light / dark mode).
private func mix(_ a: Color, _ b: Color, _ t: Double, _ scheme: ColorScheme) -> Color {
    let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
    var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
    var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
    UIColor(a).resolvedColor(with: traits).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
    UIColor(b).resolvedColor(with: traits).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
    let t = CGFloat(min(max(t, 0), 1))
    return Color(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, opacity: a1 + (a2 - a1) * t)
}

/// Globe colors (same in light and dark mode).
private enum GlobeColors {
    static let oceanLight = Color(red: 0xB8 / 255, green: 0xE6 / 255, blue: 0xFB / 255)
    static let oceanDark = Color(red: 0x5F / 255, green: 0xA3 / 255, blue: 0xE0 / 255)
    static let land = Color(red: 0xFF / 255, green: 0xF9 / 255, blue: 0xF2 / 255)
    static let border = Color(red: 0x9C / 255, green: 0xCB / 255, blue: 0xEE / 255)
    static let ink = Color(red: 0x3B / 255, green: 0x33 / 255, blue: 0x50 / 255)
    static let floor = Color(red: 0x46 / 255, green: 0x59 / 255, blue: 0x8C / 255).opacity(0.31)
}

/// A 3D globe with each country's fill, in the app's pastels (blue sea,
/// cream land split into countries, apricot → coral visited ones) with
/// depth from the sphere itself: a hard shadow crescent, a soft shine and a
/// floor shadow; the countries stay flat. Drag (and fling) to spin it; it keeps turning slowly on its own. Fills animate in, and a country that gets marked
/// spins into view with a pop and a coral pulse. `colorFor` gives each visited country its color (nil = not visited).
struct WorldGlobe: View {
    let colorFor: (String) -> Color?

    @Environment(\.colorScheme) private var colorScheme
    @State private var motion = GlobeMotion()
    @State private var projector = GlobeProjector(maxPoints: GlobeData.shared.maxPoints)
    @State private var lastDrag: CGSize = .zero

    private static let radiusFraction: CGFloat = 0.43

    var body: some View {
        let data = GlobeData.shared
        let targets = Dictionary(data.countries.map { ($0.code, colorFor($0.code)) }, uniquingKeysWith: { first, _ in first })
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date
                let motion = self.motion
                motion.step(now)
                let grow = motion.intro
                context.opacity = grow
                let r = min(size.width, size.height) * Self.radiusFraction * (0.82 + 0.18 * grow)
                motion.radius = r
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                projector.setup(yaw: motion.yaw, pitch: motion.pitch, radius: r, center: c)

                let ink = GlobeColors.ink

                // Soft shadow on the "floor".
                context.drawLayer { ctx in
                    ctx.addFilter(.blur(radius: r * 0.05))
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.8, y: c.y + r * 1.05, width: r * 1.6, height: r * 0.18)),
                             with: .color(GlobeColors.floor))
                }

                // Ocean: soft clay light from the top left.
                let sphere = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                context.fill(sphere, with: .radialGradient(
                    Gradient(colors: [GlobeColors.oceanLight, GlobeColors.oceanDark]),
                    center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4), startRadius: 0, endRadius: r * 1.6
                ))
                context.fill(sphere, with: .radialGradient(
                    Gradient(stops: [.init(color: .white.opacity(0.20), location: 0.1), .init(color: ink.opacity(0.20), location: 1)]),
                    center: CGPoint(x: c.x - r * 0.4, y: c.y - r * 0.45), startRadius: 0, endRadius: r * 2
                ))

                context.drawLayer { ctx in
                    ctx.clip(to: sphere)

                    // Grid.
                    var grid = Path()
                    for ring in data.graticule where projector.load(ring) {
                        projector.stroke(&grid, count: ring.count, cut: ring.cut)
                    }
                    ctx.stroke(grid, with: .color(.white.opacity(0.31)), lineWidth: 1)

                    // Flat land, countries split by sea-colored borders.
                    var landPath = Path()
                    var strokePath = Path()
                    for country in data.countries {
                        for ring in country.rings where projector.load(ring) {
                            projector.fill(&landPath, count: ring.count)
                            projector.stroke(&strokePath, count: ring.count, cut: ring.cut)
                        }
                    }
                    let eo = FillStyle(eoFill: true)
                    ctx.fill(landPath, with: .color(GlobeColors.land), style: eo)

                    // Visited countries.
                    for country in data.countries {
                        let amount = motion.fill(country.code, at: now)
                        guard amount > 0.001 else { continue }
                        var path = Path()
                        for ring in country.rings where projector.load(ring) {
                            projector.fill(&path, count: ring.count)
                        }
                        guard !path.isEmpty else { continue }
                        let alpha = min(1, amount * 6)
                        ctx.fill(path, with: .color((motion.colors[country.code] ?? ALIPalette.coral).opacity(alpha)), style: eo)
                        // Overshoot of the pop shows as a brief highlight.
                        if amount > 1 {
                            ctx.fill(path, with: .color(.white.opacity(min(0.5, (amount - 1) * 2))), style: eo)
                        }
                    }
                    ctx.stroke(strokePath, with: .color(GlobeColors.border), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))

                    // Depth: a hard-edged shadow crescent and a soft shine.
                    var crescent = sphere
                    crescent.addEllipse(in: CGRect(x: c.x - r * 0.2 - r * 1.04, y: c.y - r * 0.2 - r * 1.04, width: r * 2.08, height: r * 2.08))
                    ctx.fill(crescent, with: .color(ink.opacity(0.13)), style: eo)
                    ctx.drawLayer { shine in
                        shine.addFilter(.blur(radius: r * 0.02))
                        shine.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.62, y: c.y - r * 0.66, width: r * 0.34, height: r * 0.18)),
                                   with: .color(.white.opacity(0.47)))
                        shine.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.2, y: c.y - r * 0.76, width: r * 0.08, height: r * 0.08)),
                                   with: .color(.white.opacity(0.63)))
                    }
                }

                // Pulses on newly marked countries.
                for (code, start) in motion.pulses {
                    let p = now.timeIntervalSince(start) / 1.5 * 1.25
                    if p > 1.25 { motion.pulses[code] = nil; continue }
                    guard p > 0, let country = data.countries.first(where: { $0.code == code }) else { continue }
                    let v = projector.rotate(country.center)
                    guard v.z > 0 else { continue }
                    let at = projector.point(v.x, v.y)
                    for (offset, color) in [(0.0, ALIPalette.coral), (0.25, ALIPalette.blush)] {
                        let q = p - offset
                        guard q > 0 && q < 1 else { continue }
                        let rad = 6 + 40 * q
                        context.stroke(
                            Path(ellipseIn: CGRect(x: at.x - rad, y: at.y - rad, width: rad * 2, height: rad * 2)),
                            with: .color(color.opacity((1 - q) * 0.9)), lineWidth: 2.5 * (1 - q * 0.6)
                        )
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    let r = max(Double(motion.radius), 1)
                    let dx = value.translation.width - lastDrag.width
                    let dy = value.translation.height - lastDrag.height
                    lastDrag = value.translation
                    motion.dragging = true
                    motion.tween = nil
                    motion.velYaw = 0; motion.velPitch = 0
                    motion.lastTouch = Date()
                    motion.yaw += dx / r
                    motion.pitch = motion.clampPitch(motion.pitch + dy / r)
                }
                .onEnded { value in
                    let r = max(Double(motion.radius), 1)
                    lastDrag = .zero
                    motion.dragging = false
                    motion.lastTouch = Date()
                    motion.velYaw = value.velocity.width / r
                    motion.velPitch = value.velocity.height / r
                }
        )
        .onAppear { motion.update(targets: targets, countries: data.countries, now: Date()) }
        .onChange(of: targets) { _, new in motion.update(targets: new, countries: data.countries, now: Date()) }
    }
}
