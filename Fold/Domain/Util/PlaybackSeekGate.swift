import Foundation

/// Retain a genuine seek across queued pre-seek notifications. After resume,
/// account for real playing time so a delayed/coalesced clock notification can
/// confirm the seek without freezing history at its requested starting point.
nonisolated struct PlaybackSeekGate {
    private(set) var target: Double?
    private var beganPlaying: TimeInterval?
    private var accumulatedPlaying: TimeInterval = 0
    private var playing = false

    mutating func begin(_ seconds: Double, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard seconds.isFinite, seconds >= 0 else { return }
        target = seconds; accumulatedPlaying = 0
        beganPlaying = playing ? now : nil
    }
    mutating func setPlaying(_ value: Bool, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard value != playing else { return }
        if let beganPlaying { accumulatedPlaying += max(0, now - beganPlaying) }
        playing = value
        beganPlaying = value ? now : nil
    }
    func elapsed(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Double {
        accumulatedPlaying + (beganPlaying.map { max(0, now - $0) } ?? 0)
    }
    mutating func accept(_ seconds: Double, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard seconds.isFinite, seconds >= 0 else { return false }
        guard let target else { return true }
        let elapsed = accumulatedPlaying + (beganPlaying.map { max(0, now - $0) } ?? 0)
        guard seconds >= max(0, target - 0.5), seconds <= target + elapsed + 0.5 else { return false }
        self.target = nil
        return true
    }
}
