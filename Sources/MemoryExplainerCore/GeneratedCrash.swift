import Foundation
import FoundationModels

/// Structured crash data for generation - ensures valid crash format
@Generable
public struct GeneratedCrash {
    @Guide(description: "The crash error message (e.g., 'EXC_BAD_ACCESS', 'Fatal error: Unexpectedly found nil')")
    public var stopDescription: String

    @Guide(description: "Category of crash")
    public var crashType: CrashType

    @Guide(description: "Stack frames showing the call path to the crash (2-5 frames)")
    public var frames: [StackFrame]
}

@Generable
public enum CrashType: String {
    case nullPointer = "null_pointer"
    case useAfterFree = "use_after_free"
    case forceUnwrapNil = "force_unwrap_nil"
    case arrayOutOfBounds = "array_out_of_bounds"
    case typeCastFailure = "type_cast_failure"
    case unownedDealloc = "unowned_dealloc"
    case raceCondition = "race_condition"
    case stackOverflow = "stack_overflow"
    case assertionFailure = "assertion_failure"
    case memoryCorruption = "memory_corruption"
}

@Generable
public struct StackFrame {
    @Guide(description: "Function name (use realistic Swift/iOS names like 'viewDidLoad', 'fetchUserData')")
    public var function: String

    @Guide(description: "Source file name (e.g., 'UserViewController.swift', 'NetworkManager.swift')")
    public var file: String

    @Guide(description: "Line number in the file")
    public var line: Int

    @Guide(description: "Local variables at this frame (1-3 variables)")
    public var variables: [FrameVariable]
}

@Generable
public struct FrameVariable {
    @Guide(description: "Variable name")
    public var name: String

    @Guide(description: "Swift type (e.g., 'String?', 'Int', '[User]')")
    public var type: String

    @Guide(description: "Current value or state")
    public var value: String
}

// MARK: - JSON Conversion

extension GeneratedCrash {
    /// Convert to JSON format expected by the explainer
    public func toJSON() -> [String: Any] {
        return [
            "crash": [
                "stop_description": stopDescription,
                "crash_type": crashType.rawValue,
                "frames": frames.map { frame in
                    [
                        "function": frame.function,
                        "file": frame.file,
                        "line": frame.line,
                        "variables": frame.variables.map { v in
                            ["name": v.name, "type": v.type, "value": v.value]
                        }
                    ] as [String: Any]
                }
            ]
        ]
    }

    public func toJSONString() -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: toJSON(), options: .prettyPrinted) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
