import Foundation

public enum ValidationResult {
    case valid
    case notValid(reasons: [String])
    
    public var reasons: [String] {
        if case .notValid(reasons: let reasons) = self {
            return reasons
        }
        return []
    }
    
    public var isValid: Bool {
        if case .valid = self {
            return true
        }
        return false
    }
}

public struct ValidationResultError : Error {
    public var reasons: [String]
    public init?(_ validationResult: ValidationResult) {
        if validationResult.reasons.isEmpty {
            return nil
        }
        self.reasons = validationResult.reasons
    }
}

public extension ValidationResult {
    
    static func combine(lhs: ValidationResult, rhs: ValidationResult) -> ValidationResult {
        return lhs.and(rhs)
    }
    
    func and(_ other: ValidationResult) -> ValidationResult {
        switch (self, other) {
        case (.valid, .valid):
            return .valid
        default:
            return .notValid(reasons: self.reasons + other.reasons)
        }
    }
    
}

public typealias Validator<T> = (T) -> ValidationResult
public typealias TransformingValidator<T, V> = (T) -> Validated<V>

public enum Validated<T> {
    case valid(T?)
    case notValid(reasons: [String])
    
    public func map<V>(_ transform: (T) -> Validated<V>) -> Validated<V> {
        switch self {
        case .valid(let value):
            let result = value.map(transform) ?? .valid(nil)
            return result
        case .notValid(reasons: let reasons):
            return .notValid(reasons: reasons)
        }
    }
    
    public func validate(with validator: Validator<T>) -> ValidationResult? {
        switch self {
        case .valid(let value):
            return value.map(validator)
        case .notValid(reasons: let reasons):
            return .notValid(reasons: reasons)
        }
    }
    
    public func finalize() -> ValidationResult {
        switch self {
        case .valid:
            return .valid
        case .notValid(reasons: let reasons):
            return .notValid(reasons: reasons)
        }
    }
}

public func val<T>(_ any: Any?, with validator: Validator<T>) -> ValidationResult? {
    if let value = any as? T {
        return validator(value)
    }
    return nil
}

public func transformingValidate<T, V>(_ any: Any?, with transformingValidator: TransformingValidator<T, V>) -> Validated<V>? {
    if let value = any as? T {
        return transformingValidator(value)
    }
    return nil
}
