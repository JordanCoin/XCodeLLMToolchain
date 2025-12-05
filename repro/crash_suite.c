/**
 * Crash Suite - Various crash types for testing memory-explainer
 *
 * Compile: clang -g -O0 -fsanitize=address crash_suite.c -o crash_suite
 * Usage:   ./crash_suite <crash_type>
 *
 * In LLDB: lldb ./crash_suite -- use_after_free
 *          (lldb) run
 *          (lldb) crash_explain --json
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// 1. NULL pointer dereference
void crash_null_deref() {
    int *ptr = NULL;
    printf("Dereferencing NULL...\n");
    *ptr = 42;
}

// 2. Use-after-free
void crash_use_after_free() {
    char *buffer = malloc(64);
    strcpy(buffer, "Hello, World!");
    printf("Buffer: %s\n", buffer);
    free(buffer);
    printf("Accessing freed memory...\n");
    buffer[0] = 'X';  // UAF
}

// 3. Double free
void crash_double_free() {
    char *buffer = malloc(64);
    strcpy(buffer, "Test data");
    free(buffer);
    printf("Double freeing...\n");
    free(buffer);  // Double free
}

// 4. Buffer overflow (heap)
void crash_heap_overflow() {
    char *buffer = malloc(16);
    printf("Writing past heap buffer...\n");
    strcpy(buffer, "This string is way too long for the buffer!");
}

// 5. Stack buffer overflow
void crash_stack_overflow() {
    char buffer[16];
    printf("Writing past stack buffer...\n");
    strcpy(buffer, "This string is way too long for the stack buffer!");
}

// 6. Stack exhaustion (infinite recursion)
void crash_recursion(int depth) {
    char stack_hog[4096];  // Eat stack space faster
    stack_hog[0] = depth;
    printf("Recursion depth: %d\n", depth);
    crash_recursion(depth + 1);
}

// 7. Unaligned access (may not crash on ARM64 but will with sanitizers)
void crash_unaligned() {
    char buffer[16] = {0};
    int *misaligned = (int *)(buffer + 1);
    printf("Unaligned access...\n");
    *misaligned = 0xDEADBEEF;
}

// 8. Division by zero (won't crash on ARM64, but useful for testing)
void crash_div_zero() {
    volatile int x = 0;
    printf("Dividing by zero...\n");
    int result = 42 / x;
    printf("Result: %d\n", result);
}

// 9. Simulated retain cycle leak (not a crash, but memory issue)
typedef struct Node {
    struct Node *next;
    char data[1024];
} Node;

void leak_retain_cycle() {
    printf("Creating retain cycle leak...\n");
    for (int i = 0; i < 1000; i++) {
        Node *a = malloc(sizeof(Node));
        Node *b = malloc(sizeof(Node));
        a->next = b;
        b->next = a;  // Cycle - neither can be freed
    }
    printf("Leaked ~2MB in retain cycles\n");
}

// 10. Wild pointer
void crash_wild_pointer() {
    int *wild = (int *)0xDEADBEEF;
    printf("Dereferencing wild pointer...\n");
    *wild = 42;
}

void print_usage() {
    printf("Usage: crash_suite <crash_type>\n\n");
    printf("Crash types:\n");
    printf("  null_deref      - NULL pointer dereference\n");
    printf("  use_after_free  - Access memory after free\n");
    printf("  double_free     - Free same pointer twice\n");
    printf("  heap_overflow   - Write past heap buffer\n");
    printf("  stack_overflow  - Write past stack buffer\n");
    printf("  recursion       - Infinite recursion (stack exhaustion)\n");
    printf("  unaligned       - Unaligned memory access\n");
    printf("  div_zero        - Division by zero\n");
    printf("  retain_cycle    - Memory leak via cycles (no crash)\n");
    printf("  wild_pointer    - Dereference garbage address\n");
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        print_usage();
        return 1;
    }

    const char *crash_type = argv[1];
    printf("=== Crash Suite: %s ===\n\n", crash_type);

    if (strcmp(crash_type, "null_deref") == 0) {
        crash_null_deref();
    } else if (strcmp(crash_type, "use_after_free") == 0) {
        crash_use_after_free();
    } else if (strcmp(crash_type, "double_free") == 0) {
        crash_double_free();
    } else if (strcmp(crash_type, "heap_overflow") == 0) {
        crash_heap_overflow();
    } else if (strcmp(crash_type, "stack_overflow") == 0) {
        crash_stack_overflow();
    } else if (strcmp(crash_type, "recursion") == 0) {
        crash_recursion(0);
    } else if (strcmp(crash_type, "unaligned") == 0) {
        crash_unaligned();
    } else if (strcmp(crash_type, "div_zero") == 0) {
        crash_div_zero();
    } else if (strcmp(crash_type, "retain_cycle") == 0) {
        leak_retain_cycle();
    } else if (strcmp(crash_type, "wild_pointer") == 0) {
        crash_wild_pointer();
    } else {
        printf("Unknown crash type: %s\n\n", crash_type);
        print_usage();
        return 1;
    }

    printf("\n(If you see this, the crash didn't happen)\n");
    return 0;
}
