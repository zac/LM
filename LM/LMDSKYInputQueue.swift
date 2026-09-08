import AGC

/// Serializes completed input events at the session/runtime boundary. A new
/// tap never cancels an older tap. Explicit teardown drops pending events but
/// keeps the active worker as a barrier until its PRO release has completed.
@MainActor
final class LMDSKYInputQueue {
    private struct Event {
        let key: DSKYKeyCode
        let sendKey: @MainActor (DSKYKeyCode) async -> Void
        let sendPRO: @MainActor (Bool) async -> Void
        let didSend: @MainActor () async -> Void
    }
    private var pending: [Event] = []
    private var worker: Task<Void, Never>?

    func enqueue(_ key: DSKYKeyCode,
                 sendKey: @escaping @MainActor (DSKYKeyCode) async -> Void,
                 sendPRO: @escaping @MainActor (Bool) async -> Void,
                 didSend: @escaping @MainActor () async -> Void = {}) {
        pending.append(Event(key: key, sendKey: sendKey, sendPRO: sendPRO, didSend: didSend))
        startIfNeeded()
    }

    /// Session stop discards events not yet dispatched. An in-flight runtime
    /// call cannot be undone; an active PRO always sends its release. Events
    /// accepted after this call wait behind that release in a fresh worker.
    func cancelPendingAndRelease() {
        pending.removeAll()
        worker?.cancel()
    }

    func waitUntilIdle() async {
        while let worker { await worker.value }
    }

    private func startIfNeeded() {
        guard worker == nil, !pending.isEmpty else { return }
        worker = Task { @MainActor in
            defer {
                self.worker = nil
                // New events may have arrived while a cancelled PRO released.
                self.startIfNeeded()
            }
            while !Task.isCancelled, !self.pending.isEmpty {
                let event = self.pending.removeFirst()
                await LMDSKYInputPulse.run(key: event.key, sendKey: event.sendKey, sendPRO: event.sendPRO)
                guard !Task.isCancelled else { return }
                await event.didSend()
            }
        }
    }
}
