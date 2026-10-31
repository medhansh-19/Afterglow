import Foundation

/// Temporarily skip an unhealthy provider, independently of the song cache.
/// The next lookup after the deadline probes it again and success clears the cooldown.
public struct LyricProviderBackoff: Sendable {
    private struct Failure: Sendable {
        let response: LyricHTTPResponse
        let until: Date
        let count: Int
    }
    private var failures: [String: Failure] = [:]
    public init() {}

    public func blockedResponse(host: String, now: Date) -> LyricHTTPResponse? {
        guard let failure = failures[host], now < failure.until else { return nil }
        return failure.response
    }

    public mutating func record(host: String, response: LyricHTTPResponse, retryAfter: String? = nil, now: Date) {
        guard response.status == 429 || (500...599).contains(response.status) else {
            failures[host] = nil
            return
        }
        let count = min(4, (failures[host]?.count ?? 0) + 1)
        let base = response.status == 429 ? 60.0 : 30.0
        var delay = min(300, base * pow(2, Double(count - 1)))
        if let retryAfter {
            if let seconds = Double(retryAfter), seconds.isFinite, seconds >= 0 {
                delay = max(delay, seconds)
            } else {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                if let deadline = formatter.date(from: retryAfter) {
                    delay = max(delay, deadline.timeIntervalSince(now))
                }
            }
        }
        failures[host] = Failure(response: response, until: now.addingTimeInterval(delay), count: count)
    }
}

actor LyricProviderHealth {
    static let shared = LyricProviderHealth()
    private var backoff = LyricProviderBackoff()
    func blockedResponse(host: String) -> LyricHTTPResponse? {
        backoff.blockedResponse(host: host, now: Date())
    }
    func record(host: String, response: LyricHTTPResponse, retryAfter: String? = nil) {
        backoff.record(host: host, response: response, retryAfter: retryAfter, now: Date())
    }
}
