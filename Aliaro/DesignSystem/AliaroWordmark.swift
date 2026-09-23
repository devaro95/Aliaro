import SwiftUI
import UIKit
import CoreText

/// Aliaro's wordmark: "Aliaro" with a salmon dot over the "i", aligned to
/// the top of the "l" (matching the app icon) rather than sitting just
/// above the "i" itself. Static by default; `animated: true` (used by
/// `SplashView`) types the letters in one by one, wave-style, and drops
/// the dot into place last, calling `onFinished` once it settles.
struct AliaroWordmark: View {
    var size: CGFloat = 48
    var textColor: Color = ALIColors.ink
    var dotColor: Color = ALIColors.primary
    var animated: Bool = false
    var onFinished: (() -> Void)? = nil

    private static let letters: [Character] = Array("Aliaro")
    private static let iIndex = 2

    @State private var visibleCount: Int
    @State private var showDot: Bool
    @State private var isExiting = false

    private let letterStagger: Double = 0.09
    private let letterSpringResponse: Double = 0.5
    private let dotDelayAfterLetters: Double = 0.3
    private let dotSpringDuration: Double = 0.5
    private let holdBeforeExit: Double = 0.45
    private let exitDuration: Double = 0.3

    init(
        size: CGFloat = 48,
        textColor: Color = ALIColors.ink,
        dotColor: Color = ALIColors.primary,
        animated: Bool = false,
        onFinished: (() -> Void)? = nil
    ) {
        self.size = size
        self.textColor = textColor
        self.dotColor = dotColor
        self.animated = animated
        self.onFinished = onFinished
        _visibleCount = State(initialValue: animated ? 0 : Self.letters.count)
        _showDot = State(initialValue: !animated)
    }

    private var dotSize: CGFloat { size * 8 / 48 }
    private var dotDropDistance: CGFloat { size * 28 / 48 }
    // The "i" is rendered smaller than the rest of the word, baseline-aligned,
    // so the dot (sized off the "l") clears it with a gap — same fix as the app icon.
    private let iScale: CGFloat = 0.78

    /// The distance from the baseline to the visual top (ink, not font
    /// metric) of the "l" glyph. UIFont.ascender includes extra clearance
    /// for accents/diacritics, which left a visible gap above the dot;
    /// the glyph's actual bounding box is what the dot's top edge is
    /// pinned to, so it sits almost flush against the "i" while its top
    /// stays level with the top of the "l".
    private var lAscender: CGFloat {
        let weighted = UIFont.systemFont(ofSize: size, weight: .black)
        let descriptor = weighted.fontDescriptor.withDesign(.rounded) ?? weighted.fontDescriptor
        let font = UIFont(descriptor: descriptor, size: size)
        let ctFont = font as CTFont

        var glyph = CGGlyph()
        var chars: [UniChar] = Array("l".utf16)
        guard CTFontGetGlyphsForCharacters(ctFont, &chars, &glyph, 1) else {
            return font.ascender
        }

        var glyphs = [glyph]
        let rect = CTFontGetBoundingRectsForGlyphs(ctFont, .horizontal, &glyphs, nil, 1)
        return rect.maxY
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 2 / 48) {
            ForEach(Self.letters.indices, id: \.self) { index in
                letterView(for: index)
            }
        }
        .foregroundStyle(textColor)
        .opacity(isExiting ? 0 : 1)
        .onAppear {
            guard animated else { return }
            animateIn()
        }
    }

    @ViewBuilder
    private func letterView(for index: Int) -> some View {
        let isVisible = index < visibleCount

        if index == Self.iIndex {
            // "i" cell: the dotless stem plus the dot, both pinned to the
            // word's shared baseline so the dot's height is exact — not an
            // approximation based on the "i"'s own (smaller) top.
            ZStack(alignment: Alignment(horizontal: .center, vertical: .firstTextBaseline)) {
                Text("ı")
                    .font(.system(size: size * iScale, weight: .black, design: .rounded))
                Circle()
                    .fill(dotColor)
                    .frame(width: dotSize, height: dotSize)
                    .alignmentGuide(.firstTextBaseline) { _ in lAscender }
                    .offset(y: showDot ? 0 : -dotDropDistance)
                    .opacity(showDot ? 1 : 0)
                    .scaleEffect(showDot ? 1 : 0.3)
                    .animation(animated ? .interpolatingSpring(stiffness: 300, damping: 11) : nil, value: showDot)
            }
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : size * 18 / 48)
            .scaleEffect(isVisible ? 1 : 0.6)
            .animation(animated ? .spring(response: letterSpringResponse, dampingFraction: 0.55) : nil, value: isVisible)
        } else {
            Text(String(Self.letters[index]))
                .font(.system(size: size, weight: .black, design: .rounded))
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : size * 18 / 48)
                .scaleEffect(isVisible ? 1 : 0.6)
                .animation(animated ? .spring(response: letterSpringResponse, dampingFraction: 0.55) : nil, value: isVisible)
        }
    }

    private func animateIn() {
        for index in Self.letters.indices {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * letterStagger) {
                visibleCount = index + 1
            }
        }

        let allLettersSettled = Double(Self.letters.count - 1) * letterStagger + letterSpringResponse
        DispatchQueue.main.asyncAfter(deadline: .now() + allLettersSettled + dotDelayAfterLetters) {
            showDot = true
        }

        let totalDuration = allLettersSettled + dotDelayAfterLetters + dotSpringDuration + holdBeforeExit
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
            withAnimation(.easeOut(duration: exitDuration)) { isExiting = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + exitDuration) { onFinished?() }
        }
    }
}

extension AliaroWordmark {
    /// The wordmark as an `Image`, to drop inline into running text —
    /// `Text("Get \(AliaroWordmark.inlineImage(size: 15, colorScheme: scheme)) Premium")`
    /// — with the same salmon-dot "i" as the real logo. Rendered once per
    /// size/color scheme and cached; `baselineOffset` it by
    /// `inlineBaselineOffset(size:)` so it sits on the text's baseline.
    @MainActor
    static func inlineImage(size: CGFloat, colorScheme: ColorScheme) -> Image {
        let key = "\(size)-\(colorScheme == .dark ? "dark" : "light")"
        if let cached = inlineCache[key] { return Image(uiImage: cached).renderingMode(.original) }
        let renderer = ImageRenderer(content: AliaroWordmark(size: size).environment(\.colorScheme, colorScheme))
        renderer.scale = 3
        let image = renderer.uiImage ?? UIImage()
        inlineCache[key] = image
        return Image(uiImage: image).renderingMode(.original)
    }

    /// The rendered wordmark's frame includes the font's descent below the
    /// baseline; shifting it down by that much lines its letters up with
    /// the surrounding text.
    static func inlineBaselineOffset(size: CGFloat) -> CGFloat {
        let weighted = UIFont.systemFont(ofSize: size, weight: .black)
        let descriptor = weighted.fontDescriptor.withDesign(.rounded) ?? weighted.fontDescriptor
        return UIFont(descriptor: descriptor, size: size).descender
    }

    @MainActor private static var inlineCache: [String: UIImage] = [:]
}
