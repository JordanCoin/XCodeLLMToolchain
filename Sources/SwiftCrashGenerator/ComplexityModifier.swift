/// Modifiers that make crashes harder to diagnose
public enum ComplexityModifier: String, CaseIterable, Sendable {
    // Structural complexity
    case functionIndirection = "function_indirection"
    case closureCapture = "closure_capture"
    case computedProperty = "computed_property"
    case subscriptAccess = "subscript_access"
    case lazyInitialization = "lazy_initialization"

    // Type system complexity
    case genericWrapper = "generic_wrapper"
    case protocolWitness = "protocol_witness"
    case typeErasure = "type_erasure"
    case associatedType = "associated_type"

    // Concurrency complexity
    case asyncAwait = "async_await"
    case taskDetached = "task_detached"
    case actorIsolation = "actor_isolation"

    // Memory complexity
    case weakCapture = "weak_capture"
    case unownedCapture = "unowned_capture"
    case deinitTiming = "deinit_timing"

    // Control flow complexity
    case resultBuilder = "result_builder"
    case throwingContext = "throwing_context"
    case optionalChaining = "optional_chaining"

    /// Human-readable description
    public var description: String {
        switch self {
        case .functionIndirection: return "Crash hidden behind function calls"
        case .closureCapture: return "Crash value captured in closure"
        case .computedProperty: return "Crash in computed property getter"
        case .subscriptAccess: return "Crash in custom subscript"
        case .lazyInitialization: return "Crash during lazy var initialization"
        case .genericWrapper: return "Crash hidden in generic type"
        case .protocolWitness: return "Crash behind protocol abstraction"
        case .typeErasure: return "Crash with type-erased wrapper"
        case .associatedType: return "Crash involving associated types"
        case .asyncAwait: return "Crash in async context"
        case .taskDetached: return "Crash in detached task"
        case .actorIsolation: return "Crash involving actor"
        case .weakCapture: return "Crash with weak reference"
        case .unownedCapture: return "Crash with unowned capture"
        case .deinitTiming: return "Crash during deinitialization"
        case .resultBuilder: return "Crash in result builder DSL"
        case .throwingContext: return "Crash in throwing function"
        case .optionalChaining: return "Crash in deep optional chain"
        }
    }

    /// Complexity score (1-3) for difficulty weighting
    public var complexityScore: Int {
        switch self {
        case .functionIndirection, .closureCapture, .optionalChaining:
            return 1
        case .computedProperty, .subscriptAccess, .lazyInitialization,
             .genericWrapper, .throwingContext, .weakCapture:
            return 2
        case .protocolWitness, .typeErasure, .associatedType,
             .asyncAwait, .taskDetached, .actorIsolation,
             .unownedCapture, .deinitTiming, .resultBuilder:
            return 3
        }
    }

    /// Which primitives this modifier can wrap
    public var compatiblePrimitives: [CrashPrimitive] {
        switch self {
        case .functionIndirection, .closureCapture, .computedProperty,
             .genericWrapper, .throwingContext, .optionalChaining:
            // Works with most primitives
            return CrashPrimitive.allCases.filter { $0 != .stackOverflow }

        case .subscriptAccess:
            return [.forceUnwrapNil, .arrayOutOfBounds, .dictionaryKeyMissing]

        case .lazyInitialization:
            return [.forceUnwrapNil, .failedTypeCast, .preconditionFailure, .fatalErrorCall]

        case .protocolWitness, .typeErasure, .associatedType:
            return [.forceUnwrapNil, .failedTypeCast, .arrayOutOfBounds]

        case .asyncAwait, .taskDetached, .actorIsolation:
            return CrashPrimitive.allCases.filter { $0 != .stackOverflow }

        case .weakCapture:
            return [.forceUnwrapNil]

        case .unownedCapture, .deinitTiming:
            return [.unownedAfterDealloc, .forceUnwrapNil]

        case .resultBuilder:
            return [.forceUnwrapNil, .arrayOutOfBounds, .failedTypeCast, .preconditionFailure]
        }
    }
}

/// Represents a generated crash with all metadata
public struct GeneratedCrash: Sendable {
    /// The compilable Swift source code
    public let sourceCode: String

    /// The base crash type
    public let primitive: CrashPrimitive

    /// Applied complexity modifiers (in order)
    public let modifiers: [ComplexityModifier]

    /// Overall complexity score
    public var complexityScore: Int {
        modifiers.reduce(0) { $0 + $1.complexityScore }
    }

    /// Unique identifier for this crash
    public let id: String

    /// Human-readable description of what this crash tests
    public var description: String {
        if modifiers.isEmpty {
            return "Simple \(primitive.description)"
        }
        let modDesc = modifiers.map(\.description).joined(separator: " + ")
        return "\(primitive.description) with \(modDesc)"
    }

    public init(
        sourceCode: String,
        primitive: CrashPrimitive,
        modifiers: [ComplexityModifier],
        id: String
    ) {
        self.sourceCode = sourceCode
        self.primitive = primitive
        self.modifiers = modifiers
        self.id = id
    }
}
