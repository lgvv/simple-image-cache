import Foundation

/// `DateFormatter` 재사용 캐시
///
/// 동일한 `format` / `locale` / `timeZone` 조합 재사용
/// 반환값은 호출자별 복사본
public final class DateFormatterCache: Sendable {
    private let cache = LockIsolated<[String: DateFormatter]>([:])

    public init() {}

    public func formatter(
        format: String,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> DateFormatter {
        let key = "\(format)|\(locale.identifier)|\(timeZone.identifier)"
        let template = cache.withValue { cache -> DateFormatter in
            if let existing = cache[key] { return existing }
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = locale
            formatter.timeZone = timeZone
            cache[key] = formatter
            return formatter
        }
        // 호출자별 복사본 반환
        let copy = DateFormatter()
        copy.dateFormat = template.dateFormat
        copy.locale = template.locale
        copy.timeZone = template.timeZone
        return copy
    }
}
