import Darwin
import OSLog
import QuartzCore
import UIKit

struct LunarExplorerFrameStatistics: Equatable {
    let sampleCount: Int
    let meanMilliseconds: Double
    let p95Milliseconds: Double
    let p99Milliseconds: Double
    let maximumMilliseconds: Double
    let nominalMilliseconds: Double
    let missedFrameCount: Int

    static func summarize(
        durationsMilliseconds: [Double],
        nominalMilliseconds: Double
    ) -> Self? {
        guard !durationsMilliseconds.isEmpty else { return nil }
        let sorted = durationsMilliseconds.sorted()
        let mean = sorted.reduce(0, +) / Double(sorted.count)
        // visionOS Simulator currently reports a 90 Hz target while delivering
        // steady 60 Hz callbacks. Count hitches against the slower of the
        // advertised target and observed median so stable Simulator cadence is
        // not mislabeled as a missed frame.
        let observedMedian = sorted[sorted.count / 2]
        let missedThreshold = max(
            nominalMilliseconds,
            observedMedian
        ) * 1.5
        return Self(
            sampleCount: sorted.count,
            meanMilliseconds: mean,
            p95Milliseconds: percentile(0.95, in: sorted),
            p99Milliseconds: percentile(0.99, in: sorted),
            maximumMilliseconds: sorted.last ?? 0,
            nominalMilliseconds: nominalMilliseconds,
            missedFrameCount: sorted.count { $0 > missedThreshold }
        )
    }

    private static func percentile(
        _ percentile: Double,
        in sorted: [Double]
    ) -> Double {
        let index = Int(ceil(percentile * Double(sorted.count - 1)))
        return sorted[index]
    }
}

/// Launch-flagged frame and memory sampler for repeatable Release baselines.
/// Normal app launches never create a display link or query process memory.
@MainActor
final class LunarExplorerPerformanceProbe: NSObject {
    static let shared = LunarExplorerPerformanceProbe()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "io.positron.LM",
        category: "LunarExplorerPerformance"
    )
    private let reportingIntervalSeconds = 5.0
    private var displayLink: CADisplayLink?
    private var previousTimestamp: CFTimeInterval?
    private var windowStartTimestamp: CFTimeInterval?
    private var durationsMilliseconds = [Double]()
    private var nominalDurationsMilliseconds = [Double]()
    private var runLabel = "interactive"

    func start(arguments: [String]) {
        guard arguments.contains("--lunar-explorer-profile"),
              displayLink == nil else { return }
        runLabel = argumentValue(
            prefix: "--lunar-explorer-profile-label=",
            in: arguments
        ) ?? argumentValue(
            prefix: "--lunar-explorer-preset=",
            in: arguments
        ) ?? "interactive"
        let link = CADisplayLink(
            target: self,
            selector: #selector(displayLinkDidFire(_:))
        )
        link.add(to: .main, forMode: .common)
        displayLink = link
        logger.notice(
            "Explorer performance probe started preset=\(self.runLabel, privacy: .public)"
        )
    }

    func stop() {
        reportWindow()
        displayLink?.invalidate()
        displayLink = nil
        previousTimestamp = nil
        windowStartTimestamp = nil
        durationsMilliseconds.removeAll(keepingCapacity: false)
        nominalDurationsMilliseconds.removeAll(keepingCapacity: false)
    }

    @objc
    private func displayLinkDidFire(_ link: CADisplayLink) {
        defer {
            previousTimestamp = link.timestamp
        }
        guard let previousTimestamp else {
            windowStartTimestamp = link.timestamp
            return
        }
        durationsMilliseconds.append(
            (link.timestamp - previousTimestamp) * 1_000
        )
        nominalDurationsMilliseconds.append(
            (link.targetTimestamp - link.timestamp) * 1_000
        )
        guard let windowStartTimestamp,
              link.timestamp - windowStartTimestamp
                >= reportingIntervalSeconds else { return }
        reportWindow()
        self.windowStartTimestamp = link.timestamp
    }

    private func reportWindow() {
        let nominal = median(nominalDurationsMilliseconds)
        guard let statistics = LunarExplorerFrameStatistics.summarize(
            durationsMilliseconds: durationsMilliseconds,
            nominalMilliseconds: nominal
        ) else { return }
        let memory = physicalFootprintMegabytes().map {
            String(format: "%.1f", $0)
        } ?? "unavailable"
        let message = String(
            format: "Explorer performance preset=%@ frames=%d mean=%.2fms p95=%.2fms p99=%.2fms max=%.2fms nominal=%.2fms missed=%d physical=%@MiB",
            runLabel,
            statistics.sampleCount,
            statistics.meanMilliseconds,
            statistics.p95Milliseconds,
            statistics.p99Milliseconds,
            statistics.maximumMilliseconds,
            statistics.nominalMilliseconds,
            statistics.missedFrameCount,
            memory
        )
        logger.notice("\(message, privacy: .public)")
        durationsMilliseconds.removeAll(keepingCapacity: true)
        nominalDurationsMilliseconds.removeAll(keepingCapacity: true)
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    private func argumentValue(
        prefix: String,
        in arguments: [String]
    ) -> String? {
        guard let argument = arguments.first(where: {
            $0.hasPrefix(prefix)
        }) else { return nil }
        return String(argument.dropFirst(prefix.count))
    }

    private func physicalFootprintMegabytes() -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size
                / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    $0,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Double(info.phys_footprint) / 1_048_576
    }
}
