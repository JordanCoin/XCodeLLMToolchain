/// Code templates for generating crash scenarios
public enum CodeTemplates {

    // MARK: - Primitive Templates

    /// Generate base crash code for a primitive (no modifiers)
    public static func baseCrash(for primitive: CrashPrimitive) -> String {
        switch primitive {
        case .forceUnwrapNil:
            return """
            let value: String? = nil
            let unwrapped = value!
            print(unwrapped)
            """

        case .arrayOutOfBounds:
            return """
            let array = [1, 2, 3]
            let element = array[10]
            print(element)
            """

        case .dictionaryKeyMissing:
            return """
            let dict: [String: Int] = ["a": 1, "b": 2]
            let value = dict["missing"]!
            print(value)
            """

        case .failedTypeCast:
            return """
            let anything: Any = "I am a string"
            let number = anything as! Int
            print(number)
            """

        case .unownedAfterDealloc:
            return """
            class Owner { var name = "Owner" }
            class Reference { unowned var owner: Owner; init(_ o: Owner) { owner = o } }
            var ref: Reference!
            do {
                let owner = Owner()
                ref = Reference(owner)
            }
            print(ref.owner.name)
            """

        case .integerOverflow:
            return """
            let x = Int.max
            let y = x + 1
            print(y)
            """

        case .divisionByZero:
            return """
            let x = 42
            let y = 0
            let result = x / y
            print(result)
            """

        case .preconditionFailure:
            return """
            let value = -1
            precondition(value >= 0, "Value must be non-negative")
            print(value)
            """

        case .fatalErrorCall:
            return """
            let condition = false
            if !condition {
                fatalError("Condition was not met")
            }
            """

        case .stringIndexOutOfBounds:
            return """
            let str = "Hello"
            let idx = str.index(str.startIndex, offsetBy: 100)
            print(str[idx])
            """

        case .stackOverflow:
            return """
            func recurse(_ n: Int) {
                let _ = [Int](repeating: n, count: 100)
                recurse(n + 1)
            }
            recurse(0)
            """
        }
    }

    // MARK: - Modifier Templates

    /// Wrap crash code with a modifier
    public static func applyModifier(
        _ modifier: ComplexityModifier,
        to crashExpression: String,
        primitive: CrashPrimitive,
        depth: Int = 0
    ) -> String {
        let indent = String(repeating: "    ", count: depth)

        switch modifier {
        case .functionIndirection:
            return wrapInFunctionChain(crashExpression, depth: 3)

        case .closureCapture:
            return wrapInClosure(crashExpression)

        case .computedProperty:
            return wrapInComputedProperty(crashExpression, primitive: primitive)

        case .subscriptAccess:
            return wrapInSubscript(crashExpression, primitive: primitive)

        case .lazyInitialization:
            return wrapInLazyVar(crashExpression)

        case .genericWrapper:
            return wrapInGeneric(crashExpression, primitive: primitive)

        case .protocolWitness:
            return wrapInProtocol(crashExpression, primitive: primitive)

        case .typeErasure:
            return wrapInTypeErasure(crashExpression, primitive: primitive)

        case .associatedType:
            return wrapInAssociatedType(crashExpression, primitive: primitive)

        case .asyncAwait:
            return wrapInAsync(crashExpression)

        case .taskDetached:
            return wrapInDetachedTask(crashExpression)

        case .actorIsolation:
            return wrapInActor(crashExpression)

        case .weakCapture:
            return wrapInWeakCapture(crashExpression)

        case .unownedCapture:
            return wrapInUnownedCapture(crashExpression)

        case .deinitTiming:
            return wrapInDeinit(crashExpression, primitive: primitive)

        case .resultBuilder:
            return wrapInResultBuilder(crashExpression)

        case .throwingContext:
            return wrapInThrowingContext(crashExpression)

        case .optionalChaining:
            return wrapInOptionalChain(crashExpression, primitive: primitive)
        }
    }

    // MARK: - Specific Wrappers

    private static func wrapInFunctionChain(_ code: String, depth: Int) -> String {
        var result = """
        func level0() {
        \(code.indented(1))
        }

        """
        for i in 1..<depth {
            result += """
            func level\(i)() {
                level\(i-1)()
            }

            """
        }
        result += "level\(depth-1)()"
        return result
    }

    private static func wrapInClosure(_ code: String) -> String {
        return """
        let crashingClosure: () -> Void = {
        \(code.indented(1))
        }

        let executor: (@escaping () -> Void) -> Void = { action in
            action()
        }

        executor(crashingClosure)
        """
    }

    private static func wrapInComputedProperty(_ code: String, primitive: CrashPrimitive) -> String {
        let returnType = typeForPrimitive(primitive)
        return """
        struct Container {
            var trigger: \(returnType) {
        \(crashExpressionOnly(code, primitive: primitive).indented(2))
            }
        }

        let container = Container()
        print(container.trigger)
        """
    }

    private static func wrapInSubscript(_ code: String, primitive: CrashPrimitive) -> String {
        let returnType = typeForPrimitive(primitive)
        return """
        struct DataStore {
            private var storage: [\(returnType)?] = [nil, nil, nil]

            subscript(index: Int) -> \(returnType) {
        \(crashExpressionOnly(code, primitive: primitive).indented(2))
            }
        }

        let store = DataStore()
        print(store[0])
        """
    }

    private static func wrapInLazyVar(_ code: String) -> String {
        return """
        class LazyContainer {
            lazy var crashValue: String = {
        \(code.indented(2))
                return "never reached"
            }()
        }

        let container = LazyContainer()
        print(container.crashValue)
        """
    }

    private static func wrapInGeneric(_ code: String, primitive: CrashPrimitive) -> String {
        return """
        struct Wrapper<T> {
            private var value: T?

            init(_ value: T?) {
                self.value = value
            }

            func unwrap() -> T {
                return value!
            }
        }

        let wrapper = Wrapper<String>(nil)
        print(wrapper.unwrap())
        """
    }

    private static func wrapInProtocol(_ code: String, primitive: CrashPrimitive) -> String {
        return """
        protocol Crashable {
            func crash()
        }

        struct CrashImpl: Crashable {
            func crash() {
        \(code.indented(2))
            }
        }

        func executeCrashable(_ c: any Crashable) {
            c.crash()
        }

        executeCrashable(CrashImpl())
        """
    }

    private static func wrapInTypeErasure(_ code: String, primitive: CrashPrimitive) -> String {
        return """
        protocol ValueProvider {
            associatedtype Value
            func getValue() -> Value
        }

        struct AnyValueProvider<T>: ValueProvider {
            private let _getValue: () -> T

            init<P: ValueProvider>(_ provider: P) where P.Value == T {
                _getValue = provider.getValue
            }

            func getValue() -> T {
                _getValue()
            }
        }

        struct CrashingProvider: ValueProvider {
            func getValue() -> String {
                let value: String? = nil
                return value!
            }
        }

        let erased = AnyValueProvider(CrashingProvider())
        print(erased.getValue())
        """
    }

    private static func wrapInAssociatedType(_ code: String, primitive: CrashPrimitive) -> String {
        return """
        protocol Container {
            associatedtype Element
            var elements: [Element] { get }
            func first() -> Element
        }

        struct CrashingContainer: Container {
            typealias Element = String
            var elements: [String] = []

            func first() -> String {
                return elements[0]  // Crash: empty array
            }
        }

        func processContainer<C: Container>(_ c: C) -> C.Element {
            return c.first()
        }

        let container = CrashingContainer()
        print(processContainer(container))
        """
    }

    private static func wrapInAsync(_ code: String) -> String {
        return """
        func asyncCrash() async {
        \(code.indented(1))
        }

        func runAsync() {
            Task {
                await asyncCrash()
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))
        }

        runAsync()
        """
    }

    private static func wrapInDetachedTask(_ code: String) -> String {
        return """
        func triggerCrash() {
            Task.detached {
        \(code.indented(2))
            }
        }

        triggerCrash()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))
        """
    }

    private static func wrapInActor(_ code: String) -> String {
        return """
        actor CrashActor {
            func performCrash() {
        \(code.indented(2))
            }
        }

        let actor = CrashActor()

        Task {
            await actor.performCrash()
        }

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))
        """
    }

    private static func wrapInWeakCapture(_ code: String) -> String {
        return """
        class Target {
            var value: String? = nil
        }

        var target: Target? = Target()
        let closure: () -> Void = { [weak target] in
            print(target!.value!)
        }

        target = nil
        closure()
        """
    }

    private static func wrapInUnownedCapture(_ code: String) -> String {
        return """
        class Owner {
            var name = "Owner"
        }

        class Dependent {
            unowned let owner: Owner
            init(owner: Owner) { self.owner = owner }
            func printOwner() { print(owner.name) }
        }

        var dependent: Dependent!
        do {
            let owner = Owner()
            dependent = Dependent(owner: owner)
        }
        dependent.printOwner()
        """
    }

    private static func wrapInDeinit(_ code: String, primitive: CrashPrimitive) -> String {
        return """
        class CrashOnDeinit {
            var dependency: String? = nil

            deinit {
                print(dependency!)
            }
        }

        func trigger() {
            let _ = CrashOnDeinit()
        }

        trigger()
        """
    }

    private static func wrapInResultBuilder(_ code: String) -> String {
        return """
        @resultBuilder
        struct CrashBuilder {
            static func buildBlock(_ components: String...) -> [String] {
                let value: String? = nil
                return components + [value!]
            }
        }

        func buildCrash(@CrashBuilder content: () -> [String]) -> [String] {
            content()
        }

        let result = buildCrash {
            "first"
            "second"
        }
        print(result)
        """
    }

    private static func wrapInThrowingContext(_ code: String) -> String {
        return """
        enum CrashError: Error {
            case shouldNotHappen
        }

        func mightThrow() throws {
        \(code.indented(1))
        }

        func caller() {
            do {
                try mightThrow()
            } catch {
                print("Caught: \\(error)")
            }
        }

        caller()
        """
    }

    private static func wrapInOptionalChain(_ code: String, primitive: CrashPrimitive) -> String {
        return """
        struct Level3 {
            var value: String! = nil
        }

        struct Level2 {
            var next: Level3? = Level3()
        }

        struct Level1 {
            var next: Level2? = Level2()
        }

        struct Root {
            var next: Level1? = Level1()
        }

        let root = Root()
        print(root.next!.next!.next!.value!)
        """
    }

    // MARK: - Helpers

    private static func typeForPrimitive(_ primitive: CrashPrimitive) -> String {
        switch primitive {
        case .forceUnwrapNil, .dictionaryKeyMissing, .stringIndexOutOfBounds:
            return "String"
        case .arrayOutOfBounds, .integerOverflow, .divisionByZero:
            return "Int"
        case .failedTypeCast:
            return "Int"
        case .unownedAfterDealloc:
            return "String"
        case .preconditionFailure, .fatalErrorCall, .stackOverflow:
            return "Void"
        }
    }

    private static func crashExpressionOnly(_ code: String, primitive: CrashPrimitive) -> String {
        // Extract just the crashing expression for use in getters/subscripts
        // Must return the appropriate type or crash trying
        switch primitive {
        case .forceUnwrapNil:
            return """
            let value: String? = nil
            return value!
            """
        case .arrayOutOfBounds:
            return """
            let array = [1, 2, 3]
            return array[10]
            """
        case .dictionaryKeyMissing:
            return """
            let dict: [String: Int] = ["a": 1]
            return String(dict["missing"]!)
            """
        case .failedTypeCast:
            return """
            let anything: Any = "string"
            return anything as! Int
            """
        case .integerOverflow:
            return """
            let x = Int.max
            return x + 1
            """
        case .divisionByZero:
            return """
            let x = 42
            let y = 0
            return x / y
            """
        case .stringIndexOutOfBounds:
            return """
            let str = "Hello"
            let idx = str.index(str.startIndex, offsetBy: 100)
            return String(str[idx])
            """
        case .preconditionFailure:
            return """
            precondition(false, "Triggered in getter")
            return ""
            """
        case .fatalErrorCall:
            return """
            fatalError("Triggered in getter")
            """
        case .unownedAfterDealloc:
            // This one is complex, fall back to fatalError
            return """
            fatalError("Unowned dealloc crash")
            """
        case .stackOverflow:
            // Recursion doesn't fit well in a getter, use fatalError
            return """
            fatalError("Stack overflow not suitable for getter")
            """
        }
    }
}

// MARK: - String Extension

extension String {
    func indented(_ levels: Int) -> String {
        let indent = String(repeating: "    ", count: levels)
        return self.split(separator: "\n", omittingEmptySubsequences: false)
            .map { indent + $0 }
            .joined(separator: "\n")
    }
}
