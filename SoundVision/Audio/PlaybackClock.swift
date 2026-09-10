import AVFAudio
import Foundation

enum PlaybackClock {
    static var now: TimeInterval { seconds(forHostTime: mach_absolute_time()) }
    static func seconds(forHostTime time: UInt64) -> TimeInterval { AVAudioTime.seconds(forHostTime: time) }
    static func effectiveStart(requested: TimeInterval, now: TimeInterval) -> TimeInterval {
        max(requested, now + 0.06)
    }
}
