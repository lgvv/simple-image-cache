@testable import Common
import Foundation
import Testing

@Suite
struct LockIsolatedTests {
    @Test("초기값을 그대로 저장")
    func storesInitialValue() {
        // Given
        let sut = LockIsolated(42)

        // Then
        #expect(sut.value == 42)
    }

    @Test("withValue로 변경한 값 반영")
    func updatesValueViaWithValue() {
        // Given
        let sut = LockIsolated(0)

        // When
        sut.withValue { $0 = 10 }

        // Then
        #expect(sut.value == 10)
    }

    @Test("withValue는 클로저 반환값을 그대로 반환")
    func returnsClosureResultFromWithValue() {
        // Given
        let sut = LockIsolated([1, 2, 3])

        // When
        let count = sut.withValue { $0.count }

        // Then
        #expect(count == 3)
    }

    @Test("setValue로 저장된 값 교체")
    func replacesValueViaSetValue() {
        // Given
        let sut = LockIsolated("hello")

        // When
        sut.setValue("world")

        // Then
        #expect(sut.value == "world")
    }

    @Test("dynamicMemberLookup으로 내부 프로퍼티 접근 가능")
    func exposesPropertiesViaDynamicMemberLookup() {
        // Given
        struct Point: Sendable { var x: Int; var y: Int }
        let sut = LockIsolated(Point(x: 1, y: 2))

        // Then
        #expect(sut.x == 1)
        #expect(sut.y == 2)
    }

    @Test("여러 태스크에서 동시에 접근해도 값 안전하게 누적")
    func keepsConcurrentAccessSafe() async {
        // Given
        let sut = LockIsolated(0)

        // When
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 100 {
                group.addTask {
                    sut.withValue { $0 += 1 }
                }
            }
        }

        // Then
        #expect(sut.value == 100)
    }
}
