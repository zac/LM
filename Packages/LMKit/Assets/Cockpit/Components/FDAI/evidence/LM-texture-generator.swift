import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

private let width = 4096
private let height = 2048
private let tau = Double.pi * 2

private let offWhite = CGColor(red: 0.91, green: 0.90, blue: 0.85, alpha: 1)
private let nearBlack = CGColor(red: 0.018, green: 0.020, blue: 0.021, alpha: 1)
private let red = CGColor(red: 0.70, green: 0.075, blue: 0.065, alpha: 1)
private let darkRed = CGColor(red: 0.60, green: 0.055, blue: 0.05, alpha: 1)

private let polarCapRadiusDegrees = 15.0

private func radians(_ degrees: Double) -> Double {
    degrees * .pi / 180
}

private func texturePoint(latitude: Double, longitude: Double) -> CGPoint {
    CGPoint(
        x: (longitude + .pi) / tau * Double(width),
        y: (latitude + .pi / 2) / .pi * Double(height)
    )
}

private func stroke(
    _ context: CGContext,
    from start: CGPoint,
    to end: CGPoint,
    color: CGColor,
    width: CGFloat
) {
    context.setStrokeColor(color)
    context.setLineWidth(width)
    context.beginPath()
    context.move(to: start)
    context.addLine(to: end)
    context.strokePath()
}

private func drawCenteredText(
    _ text: String,
    at point: CGPoint,
    color: CGColor,
    size: CGFloat,
    rotation: CGFloat = 0,
    in context: CGContext
) {
    let font = CTFontCreateWithName("HelveticaNeue-Medium" as CFString, size, nil)
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
    context.saveGState()
    context.translateBy(x: point.x, y: point.y)
    context.rotate(by: rotation)
    context.textPosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
    CTLineDraw(line, context)
    context.restoreGState()
}

private func normalizedDegrees(_ degrees: Int) -> Int {
    (degrees % 360 + 360) % 360
}

private func abbreviatedDegrees(_ degrees: Int) -> String {
    String(normalizedDegrees(degrees) / 10)
}

private func isWhiteField(longitudeDegrees: Double) -> Bool {
    longitudeDegrees < 0
}

private func fieldColor(longitudeDegrees: Double) -> CGColor {
    isWhiteField(longitudeDegrees: longitudeDegrees) ? offWhite : nearBlack
}

private func inkColor(longitudeDegrees: Double) -> CGColor {
    isWhiteField(longitudeDegrees: longitudeDegrees) ? nearBlack : offWhite
}

private func drawRoundedRect(
    _ rect: CGRect,
    radius: CGFloat,
    color: CGColor,
    in context: CGContext
) {
    context.setFillColor(color)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.fillPath()
}

private func drawInstrumentLabel(
    _ text: String,
    latitudeDegrees: Double,
    longitudeDegrees: Double,
    boundaryTab: Bool = false,
    in context: CGContext
) {
    let point = texturePoint(
        latitude: radians(latitudeDegrees),
        longitude: radians(longitudeDegrees)
    )
    let oneDigit = text.count == 1
    let rect = CGRect(
        x: point.x - (oneDigit ? 25 : 29),
        y: point.y - (oneDigit ? 32 : 42),
        width: oneDigit ? 50 : 58,
        height: oneDigit ? 64 : 84
    )
    let background = boundaryTab ? offWhite : fieldColor(longitudeDegrees: longitudeDegrees)
    let foreground = boundaryTab ? nearBlack : inkColor(longitudeDegrees: longitudeDegrees)
    drawRoundedRect(rect, radius: 12, color: background, in: context)
    drawCenteredText(
        text,
        at: point,
        color: foreground,
        size: 55,
        rotation: .pi / 2,
        in: context
    )
}

private func drawWrappedPitchLabel(
    _ text: String,
    latitudeDegrees: Double,
    in context: CGContext
) {
    // The two clipped halves meet on the sphere to form one white label tab at the UV seam.
    drawInstrumentLabel(
        text,
        latitudeDegrees: latitudeDegrees,
        longitudeDegrees: -180,
        boundaryTab: true,
        in: context
    )
    drawInstrumentLabel(
        text,
        latitudeDegrees: latitudeDegrees,
        longitudeDegrees: 180,
        boundaryTab: true,
        in: context
    )
}

private func drawBackground(in context: CGContext) {
    // The color boundary is a pitch great circle through both yaw poles. In an
    // equirectangular texture it is vertical, with its other half at the UV seam.
    context.setFillColor(offWhite)
    context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
    context.setFillColor(nearBlack)
    context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
}

private func drawPitchSemicircles(in context: CGContext) {
    let capBottom = texturePoint(
        latitude: radians(-90 + polarCapRadiusDegrees),
        longitude: 0
    ).y
    let capTop = texturePoint(
        latitude: radians(90 - polarCapRadiusDegrees),
        longitude: 0
    ).y

    for longitudeDegrees in stride(from: -180, to: 180, by: 30) {
        let longitude = Double(longitudeDegrees)
        let x = texturePoint(latitude: 0, longitude: radians(longitude)).x

        if longitudeDegrees == -180 {
            // Both sides of the wrapped pitch-180 boundary retain contrast.
            stroke(
                context,
                from: CGPoint(x: 2, y: capBottom),
                to: CGPoint(x: 2, y: capTop),
                color: nearBlack,
                width: 5
            )
            stroke(
                context,
                from: CGPoint(x: CGFloat(width) - 2, y: capBottom),
                to: CGPoint(x: CGFloat(width) - 2, y: capTop),
                color: offWhite,
                width: 5
            )
        } else if longitudeDegrees == 0 {
            stroke(
                context,
                from: CGPoint(x: x - 2, y: capBottom),
                to: CGPoint(x: x - 2, y: capTop),
                color: nearBlack,
                width: 5
            )
            stroke(
                context,
                from: CGPoint(x: x + 2, y: capBottom),
                to: CGPoint(x: x + 2, y: capTop),
                color: offWhite,
                width: 5
            )
        } else {
            stroke(
                context,
                from: CGPoint(x: x, y: capBottom),
                to: CGPoint(x: x, y: capTop),
                color: inkColor(longitudeDegrees: longitude),
                width: 6
            )
        }

        // Five-degree yaw marks live on the pitch semicircle. The halfway mark
        // in each 30-degree cell is longer, matching the cross-shaped FDAI index.
        for latitudeDegrees in stride(from: -75, through: 75, by: 5) {
            let offset = normalizedDegrees(latitudeDegrees).isMultiple(of: 30)
                ? 0
                : abs(latitudeDegrees).isMultiple(of: 15) ? 22 : 12
            guard offset > 0 else { continue }
            let y = texturePoint(
                latitude: radians(Double(latitudeDegrees)),
                longitude: 0
            ).y
            stroke(
                context,
                from: CGPoint(x: x - CGFloat(offset), y: y),
                to: CGPoint(x: x + CGFloat(offset), y: y),
                color: inkColor(longitudeDegrees: longitude),
                width: 5
            )
        }
    }
}

private func drawYawCircles(in context: CGContext) {
    for latitudeDegrees in stride(from: -60, through: 60, by: 30) {
        let y = texturePoint(
            latitude: radians(Double(latitudeDegrees)),
            longitude: 0
        ).y

        // Each small circle is split only to switch ink color at the field boundary.
        stroke(
            context,
            from: CGPoint(x: 0, y: y),
            to: CGPoint(x: CGFloat(width) / 2, y: y),
            color: nearBlack,
            width: latitudeDegrees == 0 ? 7 : 6
        )
        stroke(
            context,
            from: CGPoint(x: CGFloat(width) / 2, y: y),
            to: CGPoint(x: CGFloat(width), y: y),
            color: offWhite,
            width: latitudeDegrees == 0 ? 7 : 6
        )

        guard latitudeDegrees != 0 else { continue }
        for longitudeDegrees in stride(from: -180, to: 180, by: 5) {
            let withinCell = normalizedDegrees(longitudeDegrees).isMultiple(of: 30)
                ? 0
                : abs(longitudeDegrees).isMultiple(of: 15) ? 22 : 12
            guard withinCell > 0 else { continue }
            let x = texturePoint(
                latitude: 0,
                longitude: radians(Double(longitudeDegrees))
            ).x
            stroke(
                context,
                from: CGPoint(x: x, y: y - CGFloat(withinCell)),
                to: CGPoint(x: x, y: y + CGFloat(withinCell)),
                color: inkColor(longitudeDegrees: Double(longitudeDegrees)),
                width: 5
            )
        }
    }

    // The zero-yaw circle is the high-resolution reference scale: one-degree
    // divisions, with progressively longer five-, ten-, and thirty-degree marks.
    let equatorY = texturePoint(latitude: 0, longitude: 0).y
    for longitudeDegrees in stride(from: -180, to: 180, by: 1) {
        let normalized = normalizedDegrees(longitudeDegrees)
        let length: CGFloat
        if normalized.isMultiple(of: 30) {
            length = 30
        } else if normalized.isMultiple(of: 10) {
            length = 22
        } else if normalized.isMultiple(of: 5) {
            length = 15
        } else {
            length = 8
        }
        let x = texturePoint(
            latitude: 0,
            longitude: radians(Double(longitudeDegrees))
        ).x
        stroke(
            context,
            from: CGPoint(x: x, y: equatorY - length),
            to: CGPoint(x: x, y: equatorY + length),
            color: inkColor(longitudeDegrees: Double(longitudeDegrees)),
            width: normalized.isMultiple(of: 5) ? 4 : 2.5
        )
    }
}

private func drawScaleLabels(in context: CGContext) {
    // Pitch values repeat midway between yaw circles on every major pitch semicircle.
    for longitudeDegrees in stride(from: -180, to: 180, by: 30) {
        let label = abbreviatedDegrees(-longitudeDegrees)
        for latitudeDegrees in [-45.0, -15.0, 15.0, 45.0] {
            if longitudeDegrees == -180 {
                drawWrappedPitchLabel(label, latitudeDegrees: latitudeDegrees, in: context)
            } else {
                drawInstrumentLabel(
                    label,
                    latitudeDegrees: latitudeDegrees,
                    longitudeDegrees: Double(longitudeDegrees),
                    boundaryTab: longitudeDegrees == 0,
                    in: context
                )
            }
        }
    }

    // Yaw values occupy the midpoint of each 30-degree pitch cell. They are
    // intentionally absent at zero yaw, where the dense one-degree scale lives.
    for latitudeDegrees in [-60, -30, 30, 60] {
        let label = abbreviatedDegrees(latitudeDegrees)
        for longitudeDegrees in stride(from: -165, through: 165, by: 30) {
            drawInstrumentLabel(
                label,
                latitudeDegrees: Double(latitudeDegrees),
                longitudeDegrees: Double(longitudeDegrees),
                in: context
            )
        }
    }
}

private func drawFDAIScales(in context: CGContext) {
    drawBackground(in: context)
    drawPitchSemicircles(in: context)
    drawYawCircles(in: context)
    drawScaleLabels(in: context)
}

private func yForDistanceFromNorthPole(_ degrees: Double) -> CGFloat {
    texturePoint(latitude: radians(90 - degrees), longitude: 0).y
}

private func drawRedPolarCaps(in context: CGContext) {
    let southEdge = yForDistanceFromNorthPole(180 - polarCapRadiusDegrees)
    let northEdge = yForDistanceFromNorthPole(polarCapRadiusDegrees)

    context.setFillColor(red)
    context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: southEdge))
    context.fill(CGRect(
        x: 0,
        y: northEdge,
        width: CGFloat(width),
        height: CGFloat(height) - northEdge
    ))

    // Pitch semicircles converge at both yaw poles.
    for longitudeDegrees in stride(from: -180, to: 180, by: 30) {
        let x = texturePoint(latitude: 0, longitude: radians(Double(longitudeDegrees))).x
        stroke(
            context,
            from: CGPoint(x: x, y: 0),
            to: CGPoint(x: x, y: southEdge),
            color: nearBlack,
            width: 6
        )
        stroke(
            context,
            from: CGPoint(x: x, y: northEdge),
            to: CGPoint(x: x, y: CGFloat(height)),
            color: nearBlack,
            width: 6
        )
    }

    for radiusDegrees in [5.0, 10.0] {
        let southY = yForDistanceFromNorthPole(180 - radiusDegrees)
        let northY = yForDistanceFromNorthPole(radiusDegrees)
        for y in [southY, northY] {
            stroke(
                context,
                from: CGPoint(x: 0, y: y),
                to: CGPoint(x: CGFloat(width), y: y),
                color: nearBlack,
                width: 6
            )
        }
    }

    let southHubEdge = yForDistanceFromNorthPole(180 - 4.0)
    let northHubEdge = yForDistanceFromNorthPole(4.0)
    context.setFillColor(darkRed)
    context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: southHubEdge))
    context.fill(CGRect(
        x: 0,
        y: northHubEdge,
        width: CGFloat(width),
        height: CGFloat(height) - northHubEdge
    ))
    for y in [southHubEdge, northHubEdge] {
        stroke(
            context,
            from: CGPoint(x: 0, y: y),
            to: CGPoint(x: CGFloat(width), y: y),
            color: nearBlack,
            width: 7
        )
    }

    // The black keyline and narrow white rim remain visible against either field.
    for y in [southEdge, northEdge] {
        stroke(
            context,
            from: CGPoint(x: 0, y: y),
            to: CGPoint(x: CGFloat(width), y: y),
            color: nearBlack,
            width: 15
        )
        stroke(
            context,
            from: CGPoint(x: 0, y: y),
            to: CGPoint(x: CGFloat(width), y: y),
            color: offWhite,
            width: 7
        )
    }
}

private func writeTexture(to outputURL: URL) throws {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    context.setShouldAntialias(true)
    context.setAllowsAntialiasing(true)
    drawFDAIScales(in: context)
    drawRedPolarCaps(in: context)

    guard
        let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        )
    else {
        throw CocoaError(.fileWriteUnknown)
    }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw CocoaError(.fileWriteUnknown)
    }
}

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: FDAITextureGenerator <output.png>\n", stderr)
    exit(EXIT_FAILURE)
}

do {
    let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
    try writeTexture(to: outputURL)
    print("Wrote \(outputURL.path) (\(width)x\(height))")
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
