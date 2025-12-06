/**
 * Swift Crash Suite - Common iOS/macOS crash types for testing memory-explainer
 *
 * Build:   cd repro/SwiftCrashSuite && swift build
 * Usage:   .build/debug/SwiftCrashSuite <crash_type>
 *
 * In LLDB: lldb .build/debug/SwiftCrashSuite -- force_unwrap
 *          (lldb) run
 *          (lldb) crash_explain --json
 */

import Foundation

// MARK: - 1. Force Unwrap Nil
func crashForceUnwrap() {
    let maybeString: String? = nil
    print("Force unwrapping nil...")
    print(maybeString!)  // 💥 Fatal error: Unexpectedly found nil
}

// MARK: - 2. Array Index Out of Bounds
func crashArrayBounds() {
    let array = [1, 2, 3]
    print("Accessing index 10 of 3-element array...")
    print(array[10])  // 💥 Fatal error: Index out of range
}

// MARK: - 3. Implicitly Unwrapped Optional
func crashImplicitUnwrap() {
    var iuo: String! = "Hello"
    iuo = nil
    print("Using nil IUO...")
    print(iuo.count)  // 💥 Fatal error: Unexpectedly found nil
}

// MARK: - 4. Dictionary Force Unwrap
func crashDictionaryForceUnwrap() {
    let dict: [String: Int] = ["a": 1, "b": 2]
    print("Force unwrapping missing key...")
    let value: Int = dict["missing"]!  // 💥 Fatal error: Unexpectedly found nil
    print(value)
}

// MARK: - 5. Failed Type Cast
func crashTypeCast() {
    let anything: Any = "I'm a string"
    print("Force casting String to Int...")
    let number = anything as! Int  // 💥 Could not cast value of type 'String' to 'Int'
    print(number)
}

// MARK: - 6. Precondition Failure
func crashPrecondition() {
    let age = -5
    print("Checking precondition (age >= 0)...")
    precondition(age >= 0, "Age must be non-negative")  // 💥 Precondition failed
}

// MARK: - 7. Assertion Failure (debug only)
func crashAssertion() {
    let isValid = false
    print("Checking assertion...")
    assert(isValid, "Validation failed")  // 💥 Assertion failed (debug builds only)
    print("This won't print in debug")
}

// MARK: - 8. fatalError
func crashFatalError() {
    print("Calling fatalError...")
    fatalError("Intentional crash for testing")  // 💥 Fatal error
}

// MARK: - 9. Arithmetic Overflow (debug)
@inline(never)
func crashOverflow() {
    print("Causing integer overflow...")
    var x = Int.max
    x = x &+ 1  // Use overflow operator to avoid compile-time error
    // The actual crash happens with checked arithmetic at runtime
    let y = Int.max
    let z = y + Int(CommandLine.arguments.count)  // 💥 Runtime overflow
    print(x, z)
}

// MARK: - 10. Unowned Reference After Dealloc
class Owner {
    var name: String
    init(name: String) { self.name = name }
}

class Reference {
    unowned var owner: Owner
    init(owner: Owner) { self.owner = owner }
}

func crashUnowned() {
    var ref: Reference?
    do {
        let owner = Owner(name: "Test")
        ref = Reference(owner: owner)
        print("Owner: \(ref!.owner.name)")
    }
    // owner is deallocated here
    print("Accessing unowned after dealloc...")
    print(ref!.owner.name)  // 💥 Fatal error: Attempted to read an unowned reference
}

// MARK: - 11. Range Error
func crashRange() {
    let str = "Hello"
    print("Accessing invalid string index...")
    let idx = str.index(str.startIndex, offsetBy: 100)  // 💥 String index is out of bounds
    print(str[idx])
}

// MARK: - 12. Stack Overflow (Swift)
func crashSwiftRecursion(_ n: Int = 0) {
    let _ = [Int](repeating: n, count: 100)  // Eat stack
    print("Depth: \(n)")
    crashSwiftRecursion(n + 1)  // 💥 Stack overflow
}

// MARK: - 13. Division by Zero (Int)
@inline(never)
func crashDivisionByZero() {
    let x = 42
    let y = CommandLine.arguments.count - CommandLine.arguments.count  // Runtime zero
    print("Dividing by zero...")
    print(x / y)  // 💥 Division by zero (for integers)
}

// MARK: - 14. nil Coalescing Chain Gone Wrong
func crashOptionalChain() {
    struct User { var profile: Profile? }
    struct Profile { var settings: Settings? }
    struct Settings { var theme: String! }

    let user = User(profile: Profile(settings: Settings(theme: nil)))
    print("Accessing nil in optional chain...")
    print(user.profile!.settings!.theme!)  // 💥 Unexpectedly found nil
}

// MARK: - Usage
func printUsage() {
    print("""
    Swift Crash Suite - Test iOS/macOS crash types

    Usage: SwiftCrashSuite <crash_type>

    Crash types:
      force_unwrap      - Force unwrap nil optional
      array_bounds      - Array index out of bounds
      implicit_unwrap   - Implicitly unwrapped optional is nil
      dict_unwrap       - Force unwrap missing dictionary key
      type_cast         - Failed as! type cast
      precondition      - Precondition failure
      assertion         - Assertion failure (debug only)
      fatal_error       - Explicit fatalError()
      overflow          - Integer overflow (debug only)
      unowned           - Unowned reference after dealloc
      range             - String index out of bounds
      recursion         - Stack overflow via recursion
      div_zero          - Integer division by zero
      optional_chain    - Nil in deeply nested optionals
    """)
}

// MARK: - Main
let args = CommandLine.arguments
guard args.count == 2 else {
    printUsage()
    exit(1)
}

let crashType = args[1]
print("=== Swift Crash Suite: \(crashType) ===\n")

switch crashType {
case "force_unwrap":
    crashForceUnwrap()
case "array_bounds":
    crashArrayBounds()
case "implicit_unwrap":
    crashImplicitUnwrap()
case "dict_unwrap":
    crashDictionaryForceUnwrap()
case "type_cast":
    crashTypeCast()
case "precondition":
    crashPrecondition()
case "assertion":
    crashAssertion()
case "fatal_error":
    crashFatalError()
case "overflow":
    crashOverflow()
case "unowned":
    crashUnowned()
case "range":
    crashRange()
case "recursion":
    crashSwiftRecursion()
case "div_zero":
    crashDivisionByZero()
case "optional_chain":
    crashOptionalChain()
default:
    print("Unknown crash type: \(crashType)\n")
    printUsage()
    exit(1)
}

print("\n(If you see this, the crash didn't happen)")
