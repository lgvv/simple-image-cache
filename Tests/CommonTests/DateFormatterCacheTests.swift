@testable import Common
import Foundation
import Testing

@Suite
struct DateFormatterCacheTests {
    @Test("동일한 포맷에는 동일한 설정을 가진 DateFormatter를 반환")
    func returnsSameConfiguredFormatterForSameFormat() {
        // Given
        let sut = DateFormatterCache()

        // When
        let first = sut.formatter(format: "yyyy-MM-dd")
        let second = sut.formatter(format: "yyyy-MM-dd")

        // Then - thread-safety를 위해 매번 복사본 반환, 인스턴스는 다르지만 설정은 동일
        #expect(first !== second)
        #expect(first.dateFormat == second.dateFormat)
        #expect(first.locale == second.locale)
        #expect(first.timeZone == second.timeZone)
    }

    @Test("다른 포맷에는 다른 설정의 DateFormatter를 반환")
    func returnsDifferentlyConfiguredFormattersForDifferentFormats() {
        // Given
        let sut = DateFormatterCache()

        // When
        let date = sut.formatter(format: "yyyy-MM-dd")
        let time = sut.formatter(format: "HH:mm:ss")

        // Then
        #expect(date.dateFormat != time.dateFormat)
    }

    @Test("같은 포맷이어도 locale이 다르면 별도 설정의 formatter를 반환")
    func returnsDifferentLocaleFormattersForDifferentLocales() {
        // Given
        let sut = DateFormatterCache()

        // When
        let en = sut.formatter(format: "yyyy-MM-dd", locale: Locale(identifier: "en_US"))
        let ko = sut.formatter(format: "yyyy-MM-dd", locale: Locale(identifier: "ko_KR"))

        // Then
        #expect(en.locale != ko.locale)
    }

    @Test("생성된 formatter의 dateFormat이 요청한 값과 동일")
    func setsRequestedDateFormat() {
        // Given
        let sut = DateFormatterCache()

        // When
        let formatter = sut.formatter(format: "yyyy/MM/dd")

        // Then
        #expect(formatter.dateFormat == "yyyy/MM/dd")
    }

    // MARK: - Regression Tests

    @Test("회귀: 동시 접근 시 크래시 없이 올바른 포맷 반환")
    func regressionConcurrentAccessIsSafe() async {
        // DateFormatter는 thread-safe하지 않으므로 캐시가 복사본을 반환하지 않으면
        // 동시 접근 시 크래시나 잘못된 포맷 문자열이 반환될 수 있다
        let sut = DateFormatterCache()
        let format = "yyyy-MM-dd"

        await withTaskGroup(of: String?.self) { group in
            for _ in 0 ..< 20 {
                group.addTask {
                    sut.formatter(format: format).dateFormat
                }
            }
            for await result in group {
                #expect(result == format)
            }
        }
    }
}
