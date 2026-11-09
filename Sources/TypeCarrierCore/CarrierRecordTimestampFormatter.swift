import Foundation

public enum CarrierRecordTimestampFormatter {
    /// Lists call this once per row on every render, and building a DateFormatter costs about
    /// 0.2 ms, so 200 rows spent ~40 ms per render. Reuse one formatter per time zone instead.
    public static func historyListText(for date: Date, timeZone: TimeZone = .current) -> String {
        cache.withLock { cached in
            if cached?.timeZone != timeZone {
                let formatter = DateFormatter()
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = timeZone
                formatter.dateFormat = "yyyy/M/d HH:mm"
                cached = formatter
            }
            return cached!.string(from: date)
        }
    }

    private static let cache = LockedFormatter()
}

private final class LockedFormatter: @unchecked Sendable {
    private let lock = NSLock()
    private var formatter: DateFormatter?

    func withLock<T>(_ body: (inout DateFormatter?) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&formatter)
    }
}
