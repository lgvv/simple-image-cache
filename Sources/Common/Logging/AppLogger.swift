import Foundation
import os

/// OSLog 로거 생성 유틸리티
public enum AppLogger {
    private final class BundleToken {}

    private static let subsystem: String = {
        let bundleID = Bundle(for: BundleToken.self).bundleIdentifier ?? "Undefined"
        return bundleID
    }()

    /// 카테고리 로거 생성
    ///
    /// - Parameter category: 카테고리 이름
    /// - Returns: `Logger`
    public static func make(category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
