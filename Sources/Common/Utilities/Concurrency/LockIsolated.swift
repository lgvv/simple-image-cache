import Foundation

@dynamicMemberLookup
public final class LockIsolated<Value>: @unchecked Sendable {
    private var _value: Value
    private let lock = NSRecursiveLock()

    public init(_ value: @autoclosure @Sendable () throws -> Value) rethrows {
        self._value = try value()
    }

    public subscript<Subject: Sendable>(dynamicMember keyPath: KeyPath<Value, Subject>) -> Subject {
        self.lock.sync {
            self._value[keyPath: keyPath]
        }
    }

    public func withValue<T: Sendable>(
        _ operation: @Sendable (inout Value) throws -> T
    ) rethrows -> T {
        try self.lock.sync {
            var value = self._value
            defer { self._value = value }
            return try operation(&value)
        }
    }

    public func setValue(_ newValue: @autoclosure @Sendable () throws -> Value) rethrows {
        try self.lock.sync {
            self._value = try newValue()
        }
    }
}

public extension LockIsolated where Value: Sendable {
    var value: Value {
        self.lock.sync {
            self._value
        }
    }
}

public extension NSRecursiveLock {
    @inlinable @discardableResult
    @_spi(Internals) func sync<R>(work: () throws -> R) rethrows -> R {
        lock()
        defer { self.unlock() }
        return try work()
    }
}
