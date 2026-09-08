import LunarMap
import Foundation

/// One interactive degree of freedom. The calibrated projection converts virtual
/// altitude into the extent represented by the 1.6-metre product window. Reference
/// launches may pin width/tilt to inspect a particular LOD at a particular scale.
struct LunarExplorerCamera: Equatable, Sendable {
    struct Reference: Equatable, Sendable {
        var width: Double
        var tilt: Double
        var siteHeightMeters: Float = -0.35
        var fixedGlobeCoordinate: LMSelenographicCoordinate?
    }

    var altitude = 7_500.0
    static let calibratedWindowWidthMeters = 1.6
    var windowWidthMeters = calibratedWindowWidthMeters
    var reference: Reference? = .init(width: 24_000, tilt: 72)

    var width: Double {
        if let reference { return reference.width }
        let calibrated = Self.altitudes.firstIndex(of: altitude).map { Self.widths[$0] }
            ?? exp(Self.extent.value(at: log(altitude)))
        return calibrated * windowWidthMeters / Self.calibratedWindowWidthMeters
    }
    var tilt: Double { reference?.tilt ?? Self.inclination.value(at: log(altitude)) }
    var siteHeightMeters: Float { reference?.siteHeightMeters ?? 1.45 }

    mutating func setWidth(_ width: Double) {
        if reference != nil { reference?.width = width }
        else { altitude = Self.altitude(forWidth: width, windowWidthMeters: windowWidthMeters) }
    }

    static func altitude(forWidth width: Double, windowWidthMeters: Double = calibratedWindowWidthMeters) -> Double {
        let target = log(width * calibratedWindowWidthMeters / windowWidthMeters)
        // Monotonic projection, with exact calibration endpoints and no
        // iteration on observable state.
        if let index = widths.firstIndex(of: width * calibratedWindowWidthMeters / windowWidthMeters) { return altitudes[index] }
        var low = log(1.5), high = log(1_500_000.0)
        for _ in 0..<52 {
            let middle = (low + high) / 2
            if extent.value(at: middle) < target { low = middle } else { high = middle }
        }
        return exp((low + high) / 2)
    }

    // Shape-preserving C1 calibration. Named presets select only altitude;
    // width and inclination are derived from the same camera, never separately
    // interpolated mutable state. Reference launch values remain independent.
    private static let altitudes = [1.5, 2, 40, 180, 1_200, 7_500, 30_000, 1_000_000, 1_500_000.0]
    private static let widths = [8, 20, 180, 700, 4_000, 24_000, 120_000, 4_400_000, 5_000_000.0]
    private static let extent = Curve(x: altitudes.map(log), y: widths.map(log))
    private static let inclination = Curve(
        x: altitudes.map(log), y: [38, 38, 50, 58, 66, 72, 72, 0, 0])

    private struct Curve: Sendable {
        let x: [Double], y: [Double], slopes: [Double]
        init(x: [Double], y: [Double]) {
            self.x = x; self.y = y
            let d = zip(y, y.dropFirst()).enumerated().map { i, pair in
                (pair.1 - pair.0) / (x[i + 1] - x[i])
            }
            var result = [Double](repeating: 0, count: x.count)
            result[0] = d[0]; result[x.count - 1] = d[d.count - 1]
            for i in 1..<(x.count - 1) where d[i - 1] * d[i] > 0 {
                let a = x[i] - x[i - 1], b = x[i + 1] - x[i]
                let w1 = 2 * b + a, w2 = b + 2 * a
                result[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
            }
            self.slopes = result
        }
        func value(at value: Double) -> Double {
            if value <= x[0] { return y[0] }
            if value >= x[x.count - 1] { return y[y.count - 1] }
            let i = (0..<(x.count - 1)).first { value <= x[$0 + 1] }!
            if value == x[i + 1] { return y[i + 1] }
            let h = x[i + 1] - x[i], t = (value - x[i]) / h
            let t2 = t * t, t3 = t2 * t, m = slopes
            return (2 * t3 - 3 * t2 + 1) * y[i] + (t3 - 2 * t2 + t) * h * m[i]
                + (-2 * t3 + 3 * t2) * y[i + 1] + (t3 - t2) * h * m[i + 1]
        }
    }
}

/// Heading used by the corridor planner. A 2.5-degree margin around each
/// 7.5-degree midpoint prevents repeated requests when a release wobbles there.
struct LunarExplorerPlanningHeading: Equatable, Sendable {
    private(set) var degrees = 0.0
    mutating func commit(_ heading: Double) {
        guard heading.isFinite else { return }
        let wrapped = (heading - degrees + 180).truncatingRemainder(dividingBy: 360)
        let delta = (wrapped + 360).truncatingRemainder(dividingBy: 360) - 180
        guard abs(delta) > 10 else { return }
        degrees = ((degrees + (delta / 15).rounded() * 15) + 360).truncatingRemainder(dividingBy: 360)
    }
}
