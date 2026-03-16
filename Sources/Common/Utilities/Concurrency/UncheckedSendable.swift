@dynamicMemberLookup
@propertyWrapper
public struct UncheckedSendable<Value>: @unchecked Sendable {
    public var value: Value

    public init(_ value: Value) {
        self.value = value
    }

    public init(wrappedValue: Value) {
        self.value = wrappedValue
    }

    public var wrappedValue: Value {
        _read { yield self.value }
        _modify { yield &self.value }
    }

    public var projectedValue: Self {
        get { self }
        set { self = newValue }
    }

    public subscript<Subject>(dynamicMember keyPath: KeyPath<Value, Subject>) -> Subject {
        self.value[keyPath: keyPath]
    }

    public subscript<Subject>(dynamicMember keyPath: WritableKeyPath<Value, Subject>) -> Subject {
        _read { yield self.value[keyPath: keyPath] }
        _modify { yield &self.value[keyPath: keyPath] }
    }
}

extension UncheckedSendable: Equatable where Value: Equatable {}

extension UncheckedSendable: Hashable where Value: Hashable {}
