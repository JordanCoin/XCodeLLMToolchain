#!/usr/bin/env python3
"""
XcodeLLM - LLDB crash capture and analysis.

Captures crash context (stack trace, memory info, crash reason) and outputs
structured JSON that can be piped to codemap and/or Foundation Models.

Installation:
    Add to ~/.lldbinit-Xcode:
    command script import ~/Code/XcodeLLMToolchain/lldb/plugin.py

Usage in LLDB:
    (lldb) crash_explain           # Basic crash info
    (lldb) crash_explain --full    # Include memory dump
    (lldb) crash_explain --json    # Raw JSON output
    (lldb) crash_explain --explain # LLM analysis
    (lldb) explain_here            # Explain current breakpoint
    (lldb) memory_explain          # Analyze memory
"""

import lldb
import sys
import os

# Ensure the package is importable
current_dir = os.path.dirname(os.path.abspath(__file__))
if current_dir not in sys.path:
    sys.path.append(current_dir)

try:
    from capture_lib.commands import crash_explain, memory_explain, explain_here
except ImportError as e:
    print(f"Error importing capture_lib: {e}")
    # Don't break if dependencies fail, but commands won't work
    pass

def __lldb_init_module(debugger, internal_dict):
    """Called when the module is loaded by LLDB."""

    debugger.HandleCommand(
        'command script add -f plugin.crash_explain crash_explain'
    )
    debugger.HandleCommand(
        'command script add -f plugin.memory_explain memory_explain'
    )
    debugger.HandleCommand(
        'command script add -f plugin.explain_here explain_here'
    )

    print("XcodeLLM loaded!")
    print("  explain_here   - Explain current state at any breakpoint")
    print("  crash_explain  - Analyze crashes (use --explain for LLM)")
    print("  memory_explain - Analyze memory usage")
