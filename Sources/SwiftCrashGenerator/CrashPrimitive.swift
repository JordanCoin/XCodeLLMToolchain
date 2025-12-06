/// Base crash types - the fundamental thing that explodes
public enum CrashPrimitive: String, CaseIterable, Sendable {
    case forceUnwrapNil = "force_unwrap_nil"
    case arrayOutOfBounds = "array_out_of_bounds"
    case dictionaryKeyMissing = "dictionary_key_missing"
    case failedTypeCast = "failed_type_cast"
    case unownedAfterDealloc = "unowned_after_dealloc"
    case integerOverflow = "integer_overflow"
    case divisionByZero = "division_by_zero"
    case preconditionFailure = "precondition_failure"
    case fatalErrorCall = "fatal_error_call"
    case stringIndexOutOfBounds = "string_index_out_of_bounds"
    case stackOverflow = "stack_overflow"

    /// Human-readable description
    public var description: String {
        switch self {
        case .forceUnwrapNil: return "Force unwrap of nil optional"
        case .arrayOutOfBounds: return "Array index out of bounds"
        case .dictionaryKeyMissing: return "Force unwrap missing dictionary key"
        case .failedTypeCast: return "Failed as! type cast"
        case .unownedAfterDealloc: return "Unowned reference after deallocation"
        case .integerOverflow: return "Integer overflow"
        case .divisionByZero: return "Integer division by zero"
        case .preconditionFailure: return "Precondition failure"
        case .fatalErrorCall: return "Explicit fatalError() call"
        case .stringIndexOutOfBounds: return "String index out of bounds"
        case .stackOverflow: return "Stack overflow via recursion"
        }
    }

    /// The Swift runtime error message pattern
    public var errorPattern: String {
        switch self {
        case .forceUnwrapNil: return "Unexpectedly found nil"
        case .arrayOutOfBounds: return "Index out of range"
        case .dictionaryKeyMissing: return "Unexpectedly found nil"
        case .failedTypeCast: return "Could not cast value"
        case .unownedAfterDealloc: return "Attempted to read an unowned reference"
        case .integerOverflow: return "arithmetic overflow"
        case .divisionByZero: return "Division by zero"
        case .preconditionFailure: return "Precondition failed"
        case .fatalErrorCall: return "Fatal error"
        case .stringIndexOutOfBounds: return "String index is out of bounds"
        case .stackOverflow: return "stack overflow"
        }
    }
}
