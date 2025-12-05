#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void cause_crash(int *ptr) {
    printf("About to crash...\n");
    // Write to NULL pointer to cause EXC_BAD_ACCESS
    *ptr = 42;
}

void intermediate_frame(int *ptr) {
    cause_crash(ptr);
}

int main() {
    printf("Starting crash test...\n");
    
    int *ptr = NULL;
    intermediate_frame(ptr);
    
    return 0;
}
