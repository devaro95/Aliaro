import SwiftUI

/// Country outlines for the World map, from the bundled `world_map.json`:
/// Natural Earth 1:50m (public domain), simplified and already projected
/// (Natural Earth projection) to integer coordinates in a `size` canvas.
/// `allCodes` lists every country that can be marked, including tiny ones
/// not drawn at this scale.
final class WorldMapData {
    static let shared = WorldMapData()

    struct Country {
        let code: String
        let path: Path
    }

    let size: CGSize
    let countries: [Country]
    let allCodes: [String]

    private struct File: Decodable {
        let w: Double
        let h: Double
        let countries: [Entry]
        let all: [String]

        struct Entry: Decodable {
            let c: String
            let r: [[Double]]
        }
    }

    private init() {
        guard let url = Bundle.main.url(forResource: "world_map", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else {
            size = CGSize(width: 2000, height: 900)
            countries = []
            allCodes = []
            return
        }
        size = CGSize(width: file.w, height: file.h)
        countries = file.countries.map { entry in
            var path = Path()
            for ring in entry.r where ring.count >= 6 {
                path.move(to: CGPoint(x: ring[0], y: ring[1]))
                var i = 2
                while i + 1 < ring.count {
                    path.addLine(to: CGPoint(x: ring[i], y: ring[i + 1]))
                    i += 2
                }
                path.closeSubpath()
            }
            return Country(code: entry.c, path: path)
        }
        allCodes = file.all
    }

    /// Country under a point in map coordinates (even-odd, so holes such as
    /// Lesotho inside South Africa resolve to the inner country).
    func country(at point: CGPoint) -> String? {
        countries.last { $0.path.boundingRect.insetBy(dx: -2, dy: -2).contains(point) && $0.path.contains(point, eoFill: true) }?.code
            ?? nearbyCountry(at: point)
    }

    /// Small islands are hard to hit: accept a tap a few points away.
    private func nearbyCountry(at point: CGPoint) -> String? {
        let tolerance: CGFloat = 6
        return countries.first { $0.path.boundingRect.insetBy(dx: -tolerance, dy: -tolerance).contains(point) && $0.path.boundingRect.width < 20 }?.code
    }
}

/// The world map drawn with each country's fill. `fill` returns the opacity
/// (0…1) of the accent for a country code; 0 leaves it as an outline.
struct WorldMapCanvas: View {
    let fill: (String) -> Double
    var accent: Color = ALIColors.worldMapAccent
    /// Highlighted for a moment after a tap.
    var highlighted: String? = nil
    /// Line width in screen points (kept constant while zooming).
    var lineWidth: CGFloat = 0.6
    var zoom: CGFloat = 1

    var body: some View {
        let data = WorldMapData.shared
        Canvas { context, canvasSize in
            let scale = canvasSize.width / data.size.width
            context.scaleBy(x: scale, y: scale)
            let stroke = lineWidth / (scale * zoom)
            for country in data.countries {
                let amount = fill(country.code)
                if amount > 0 {
                    context.fill(country.path, with: .color(accent.opacity(0.35 + 0.65 * amount)), style: FillStyle(eoFill: true))
                }
                if country.code == highlighted {
                    context.fill(country.path, with: .color(ALIColors.ink.opacity(0.25)), style: FillStyle(eoFill: true))
                }
                context.stroke(country.path, with: .color(ALIColors.ink.opacity(0.45)), lineWidth: stroke)
            }
        }
        .aspectRatio(data.size.width / data.size.height, contentMode: .fit)
    }
}
