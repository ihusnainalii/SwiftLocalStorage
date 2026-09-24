import Foundation

/// How long a saved value stays readable. After it expires, reads treat it as absent.
public enum CacheExpiration: Sendable, Hashable {
    case never
    case seconds(TimeInterval)
    case minutes(Int)
    case hours(Int)
    case days(Int)
    /// Expires at a fixed instant.
    case date(Date)

    /// The absolute expiry for a value saved at `now`, or `nil` for ``never``.
    public func expiresAt(from now: Date) -> Date? {
        switch self {
        case .never: nil
        case .seconds(let seconds): now + seconds
        case .minutes(let minutes): now + TimeInterval(minutes) * 60
        case .hours(let hours): now + TimeInterval(hours) * 3_600
        case .days(let days): now + TimeInterval(days) * 86_400
        case .date(let date): date
        }
    }
}
