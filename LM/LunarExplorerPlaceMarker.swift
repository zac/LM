import SwiftUI

/// Cartographic symbol, not a scale model of the hardware on the surface.
struct LunarExplorerPlaceMarker: View {
    var place: LMLunarPOICatalog.Place?

    var body: some View {
        HStack(spacing: 8) {
            LunarExplorerMarkerGlyph(isApollo: place?.category == "apollo")
                .frame(width: 80, height: 80)
            Text(place?.name ?? "Selected location")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.black.opacity(0.68), in: Capsule())
        }
        .frame(width: 260, height: 80, alignment: .leading)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(place?.name ?? "Selected location")
    }
}

/// Both symbols end at (24, 76) in an 80-point square. The scene positions
/// that foot at the geographic anchor, independently of the label's width.
struct LunarExplorerMarkerGlyph: View {
    var isApollo: Bool

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 80, y: size.height / 80)
            if isApollo { drawFlag(in: &context) }
            else { drawPin(in: &context) }
        }
    }

    private func outline(_ path: Path, in context: inout GraphicsContext) {
        context.stroke(path, with: .color(.black.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
        context.stroke(path, with: .color(.white),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
    }

    private func drawFlag(in context: inout GraphicsContext) {
        var pole = Path()
        pole.move(to: CGPoint(x: 24, y: 8))
        pole.addLine(to: CGPoint(x: 24, y: 76))
        outline(pole, in: &context)

        var cloth = Path()
        cloth.move(to: CGPoint(x: 24, y: 10))
        cloth.addCurve(to: CGPoint(x: 70, y: 10),
                       control1: CGPoint(x: 40, y: 4), control2: CGPoint(x: 54, y: 16))
        cloth.addCurve(to: CGPoint(x: 70, y: 50),
                       control1: CGPoint(x: 66, y: 22), control2: CGPoint(x: 73, y: 38))
        cloth.addCurve(to: CGPoint(x: 24, y: 50),
                       control1: CGPoint(x: 54, y: 56), control2: CGPoint(x: 40, y: 44))
        cloth.closeSubpath()
        // A thin silhouette edge replaces the heavy rectangular white frame.
        // The cloth supplies the contour; only the top has a support bar.
        context.stroke(cloth, with: .color(.black.opacity(0.65)), lineWidth: 2)
        var fabric = context
        fabric.clip(to: cloth)
        fabric.fill(cloth, with: .color(Color(red: 0.78, green: 0.12, blue: 0.18)))
        // Broad bands and a few star dots survive at map-marker sizes.
        for y in stride(from: 15, through: 47, by: 12) {
            fabric.fill(Path(CGRect(x: 24, y: y, width: 46, height: 6)), with: .color(.white))
        }
        fabric.fill(Path(CGRect(x: 24, y: 7, width: 22, height: 24)),
                    with: .color(Color(red: 0.10, green: 0.22, blue: 0.45)))
        for y in [14, 23] {
            for x in [30, 39] {
                fabric.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 3, height: 3)),
                            with: .color(.white))
            }
        }
        // A single quiet fold, with the top edge acting as the support bar.
        fabric.fill(Path(CGRect(x: 48, y: 7, width: 4, height: 50)),
                    with: .color(.black.opacity(0.12)))
        var support = Path()
        support.move(to: CGPoint(x: 24, y: 8))
        support.addLine(to: CGPoint(x: 71, y: 8))
        context.stroke(support, with: .color(.white),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    private func drawPin(in context: inout GraphicsContext) {
        var pin = Path()
        pin.move(to: CGPoint(x: 24, y: 76))
        pin.addCurve(to: CGPoint(x: 5, y: 32),
                     control1: CGPoint(x: 20, y: 59), control2: CGPoint(x: 5, y: 47))
        pin.addCurve(to: CGPoint(x: 43, y: 32),
                     control1: CGPoint(x: 5, y: 7), control2: CGPoint(x: 43, y: 7))
        pin.addCurve(to: CGPoint(x: 24, y: 76),
                     control1: CGPoint(x: 43, y: 47), control2: CGPoint(x: 28, y: 59))
        pin.closeSubpath()
        outline(pin, in: &context)
        context.fill(pin, with: .color(.blue))
        context.fill(Path(ellipseIn: CGRect(x: 17, y: 26, width: 14, height: 14)),
                     with: .color(.white))
    }
}

extension LunarExplorerSession {
    private static let markerPlaces = (try? LMLunarPOICatalog.load().features) ?? []
    var selectedMarkerPlace: LMLunarPOICatalog.Place? {
        Self.markerPlaces.first { $0.id == selectedPlaceID }
    }
}
