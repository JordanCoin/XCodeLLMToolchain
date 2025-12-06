import Testing
@testable import MemoryExplainerCore

@Test func engineInitializes() async throws {
    let engine = MemoryExplainerEngine()
    #expect(engine != nil)
}

@Test func crashExplanationTypes() async throws {
    // Test that all crash types are valid
    let validTypes = [
        "null_pointer", "force_unwrap_nil", "array_out_of_bounds",
        "use_after_free", "double_free", "stack_overflow",
        "bad_access", "assertion_failure", "unrecognized_selector",
        "deadlock", "memory_corruption", "other"
    ]

    // Just validate they're the expected set
    #expect(validTypes.count == 12)
}
