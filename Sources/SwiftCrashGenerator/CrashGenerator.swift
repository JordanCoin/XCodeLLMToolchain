import Foundation

/// Main generator that composes crash primitives with complexity modifiers
public struct CrashGenerator {

    /// Random number generator (not Sendable, but struct is value type)
    private var rng: any RandomNumberGenerator

    /// Configuration for generation
    public struct Config: Sendable {
        /// Minimum complexity score
        public var minComplexity: Int
        /// Maximum complexity score
        public var maxComplexity: Int
        /// Maximum number of modifiers to apply
        public var maxModifiers: Int
        /// Whether to include imports in generated code
        public var includeImports: Bool
        /// Whether to wrap in main entry point
        public var wrapInMain: Bool

        public init(
            minComplexity: Int = 0,
            maxComplexity: Int = 10,
            maxModifiers: Int = 3,
            includeImports: Bool = true,
            wrapInMain: Bool = true
        ) {
            self.minComplexity = minComplexity
            self.maxComplexity = maxComplexity
            self.maxModifiers = maxModifiers
            self.includeImports = includeImports
            self.wrapInMain = wrapInMain
        }

        public static let simple = Config(maxComplexity: 0, maxModifiers: 0)
        public static let medium = Config(minComplexity: 1, maxComplexity: 4, maxModifiers: 2)
        public static let hard = Config(minComplexity: 4, maxComplexity: 10, maxModifiers: 3)
    }

    public var config: Config

    public init(config: Config = Config(), seed: UInt64? = nil) {
        self.config = config
        if let seed = seed {
            self.rng = SeededRandomNumberGenerator(seed: seed)
        } else {
            self.rng = SystemRandomNumberGenerator()
        }
    }

    /// Generate a single random crash
    public mutating func generate() -> GeneratedCrash {
        let primitive = CrashPrimitive.allCases.randomElement(using: &rng)!
        return generate(primitive: primitive)
    }

    /// Generate a crash for a specific primitive
    public mutating func generate(primitive: CrashPrimitive) -> GeneratedCrash {
        let modifiers = selectModifiers(for: primitive)
        return generate(primitive: primitive, modifiers: modifiers)
    }

    /// Generate a crash with specific primitive and modifiers
    public func generate(
        primitive: CrashPrimitive,
        modifiers: [ComplexityModifier]
    ) -> GeneratedCrash {
        let id = generateId(primitive: primitive, modifiers: modifiers)
        let code = generateCode(primitive: primitive, modifiers: modifiers)

        return GeneratedCrash(
            sourceCode: code,
            primitive: primitive,
            modifiers: modifiers,
            id: id
        )
    }

    /// Generate all simple (no modifier) crashes
    public func generateAllSimple() -> [GeneratedCrash] {
        return CrashPrimitive.allCases.map { primitive in
            generate(primitive: primitive, modifiers: [])
        }
    }

    /// Generate N random crashes
    public mutating func generateBatch(count: Int) -> [GeneratedCrash] {
        return (0..<count).map { _ in generate() }
    }

    /// Generate crashes for all primitive + single modifier combinations
    public func generateAllCombinations() -> [GeneratedCrash] {
        var results: [GeneratedCrash] = []

        for primitive in CrashPrimitive.allCases {
            // Base case (no modifiers)
            results.append(generate(primitive: primitive, modifiers: []))

            // Single modifier cases
            for modifier in ComplexityModifier.allCases {
                if modifier.compatiblePrimitives.contains(primitive) {
                    results.append(generate(primitive: primitive, modifiers: [modifier]))
                }
            }
        }

        return results
    }

    // MARK: - Private

    private mutating func selectModifiers(for primitive: CrashPrimitive) -> [ComplexityModifier] {
        guard config.maxModifiers > 0 else { return [] }

        let compatible = ComplexityModifier.allCases.filter {
            $0.compatiblePrimitives.contains(primitive)
        }

        guard !compatible.isEmpty else { return [] }

        var selected: [ComplexityModifier] = []
        var currentScore = 0
        let targetModifierCount = Int.random(in: 0...config.maxModifiers, using: &rng)

        for _ in 0..<targetModifierCount {
            let candidates = compatible.filter { modifier in
                !selected.contains(modifier) &&
                (currentScore + modifier.complexityScore) <= config.maxComplexity
            }

            guard let modifier = candidates.randomElement(using: &rng) else { break }

            selected.append(modifier)
            currentScore += modifier.complexityScore

            if currentScore >= config.maxComplexity { break }
        }

        // Check minimum complexity
        if currentScore < config.minComplexity {
            // Try to add more modifiers to meet minimum
            let needed = config.minComplexity - currentScore
            let candidates = compatible.filter { modifier in
                !selected.contains(modifier) &&
                modifier.complexityScore >= needed
            }
            if let modifier = candidates.randomElement(using: &rng) {
                selected.append(modifier)
            }
        }

        return selected
    }

    private func generateCode(
        primitive: CrashPrimitive,
        modifiers: [ComplexityModifier]
    ) -> String {
        var code = CodeTemplates.baseCrash(for: primitive)

        // Apply modifiers in sequence
        for modifier in modifiers {
            code = CodeTemplates.applyModifier(modifier, to: code, primitive: primitive)
        }

        // Wrap in full program structure
        return wrapInProgram(code)
    }

    private func wrapInProgram(_ code: String) -> String {
        var result = ""

        if config.includeImports {
            result += "import Foundation\n\n"
        }

        if config.wrapInMain {
            result += "// Generated crash test\n"
            result += code
        } else {
            result += code
        }

        return result
    }

    private func generateId(
        primitive: CrashPrimitive,
        modifiers: [ComplexityModifier]
    ) -> String {
        let modPart = modifiers.isEmpty ? "base" : modifiers.map(\.rawValue).joined(separator: "_")
        let hash = abs("\(primitive.rawValue)_\(modPart)_\(Date().timeIntervalSince1970)".hashValue)
        return "\(primitive.rawValue)_\(modPart)_\(String(hash, radix: 16).prefix(8))"
    }
}

// MARK: - Seeded RNG for reproducible generation

struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        // xorshift64
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

// MARK: - Batch Generation Result

public struct GenerationResult: Sendable {
    public let crashes: [GeneratedCrash]
    public let config: CrashGenerator.Config
    public let timestamp: Date

    public var summary: String {
        let byPrimitive = Dictionary(grouping: crashes, by: \.primitive)
        let byComplexity = Dictionary(grouping: crashes) { crash in
            switch crash.complexityScore {
            case 0: return "simple"
            case 1...3: return "medium"
            default: return "hard"
            }
        }

        return """
        Generated \(crashes.count) crash scenarios
        By primitive: \(byPrimitive.mapValues(\.count))
        By complexity: \(byComplexity.mapValues(\.count))
        """
    }
}
