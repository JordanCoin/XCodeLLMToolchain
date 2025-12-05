#!/usr/bin/env python3
"""
LLDB memory analysis scripts for memory-explainer.

Captures crash context and memory usage info, outputs structured JSON
that can be piped to codemap and/or Foundation Models for explanation.

Installation:
    Add to ~/.lldbinit-Xcode:
    command script import ~/Code/memory-explainer/lldb/crash_capture.py

Commands:
    (lldb) crash_explain           # Analyze current crash
    (lldb) crash_explain --json    # Raw JSON output

    (lldb) memory_explain          # Analyze memory usage
    (lldb) memory_explain --top 20 # Show top 20 allocations
    (lldb) memory_explain --json   # Raw JSON output
"""

import lldb
import json
import subprocess
import os


def get_crash_info(thread, target, include_memory=False):
    """Extract crash information from the current thread."""

    crash_info = {
        "stop_reason": thread.GetStopReasonDataCount(),
        "stop_description": thread.GetStopDescription(256),
        "thread_id": thread.GetThreadID(),
        "frames": [],
        "registers": {},
    }

    # Map stop reason enum to string
    stop_reasons = {
        lldb.eStopReasonInvalid: "invalid",
        lldb.eStopReasonNone: "none",
        lldb.eStopReasonTrace: "trace",
        lldb.eStopReasonBreakpoint: "breakpoint",
        lldb.eStopReasonWatchpoint: "watchpoint",
        lldb.eStopReasonSignal: "signal",
        lldb.eStopReasonException: "exception",
        lldb.eStopReasonExec: "exec",
        lldb.eStopReasonPlanComplete: "plan_complete",
        lldb.eStopReasonThreadExiting: "thread_exiting",
        lldb.eStopReasonInstrumentation: "instrumentation",
    }
    crash_info["stop_reason_type"] = stop_reasons.get(
        thread.GetStopReason(), "unknown"
    )

    # Collect stack frames
    for frame in thread:
        frame_info = {
            "index": frame.GetFrameID(),
            "function": frame.GetFunctionName() or "<unknown>",
            "module": frame.GetModule().GetFileSpec().GetFilename() if frame.GetModule() else None,
            "file": None,
            "line": None,
            "column": None,
            "pc": hex(frame.GetPC()),
            "sp": hex(frame.GetSP()),
            "fp": hex(frame.GetFP()),
        }

        # Get source location if available
        line_entry = frame.GetLineEntry()
        if line_entry.IsValid():
            file_spec = line_entry.GetFileSpec()
            frame_info["file"] = str(file_spec)
            frame_info["line"] = line_entry.GetLine()
            frame_info["column"] = line_entry.GetColumn()

        # Get local variables
        variables = []
        for var in frame.GetVariables(True, True, True, True):
            var_info = {
                "name": var.GetName(),
                "type": var.GetTypeName(),
                "value": var.GetValue(),
                "summary": var.GetSummary(),
            }
            variables.append(var_info)

        if variables:
            frame_info["variables"] = variables

        crash_info["frames"].append(frame_info)

    # Get registers from first frame
    if thread.GetNumFrames() > 0:
        frame = thread.GetFrameAtIndex(0)
        for reg_group in frame.GetRegisters():
            group_name = reg_group.GetName()
            crash_info["registers"][group_name] = {}
            for reg in reg_group:
                crash_info["registers"][group_name][reg.GetName()] = reg.GetValue()

    # Get crash address for memory crashes
    if crash_info["stop_reason_type"] == "exception":
        # Try to extract the faulting address
        if "EXC_BAD_ACCESS" in crash_info["stop_description"]:
            crash_info["crash_type"] = "memory_access"
            # Parse address from description like "EXC_BAD_ACCESS (code=1, address=0x...)"
            desc = crash_info["stop_description"]
            if "address=" in desc:
                try:
                    addr_str = desc.split("address=")[1].split(")")[0]
                    crash_info["fault_address"] = addr_str

                    # If requested, try to read memory around fault address
                    if include_memory:
                        try:
                            addr = int(addr_str, 16)
                            error = lldb.SBError()
                            # Read 64 bytes before and after
                            mem_before = target.GetProcess().ReadMemory(
                                max(0, addr - 64), 64, error
                            )
                            if mem_before:
                                crash_info["memory_before"] = mem_before.hex()
                        except:
                            pass
                except:
                    pass

    return crash_info


def get_codemap_context(project_path, crash_file):
    """Run codemap to get dependency context for the crashed file."""

    if not project_path or not crash_file:
        return None

    try:
        # Check if codemap is available
        result = subprocess.run(
            ["which", "codemap"],
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            return {"error": "codemap not found. Install with: brew install jordancoin/tap/codemap"}

        # Get dependencies
        deps_result = subprocess.run(
            ["codemap", "--deps", "--json", project_path],
            capture_output=True,
            text=True,
            timeout=10
        )

        if deps_result.returncode == 0:
            deps = json.loads(deps_result.stdout)

            # Find info about the crashed file
            crash_file_name = os.path.basename(crash_file)
            relevant_files = []

            for f in deps.get("files", []):
                if crash_file_name in f.get("path", ""):
                    relevant_files.append(f)
                # Also find files that import the crashed file
                for imp in f.get("imports", []):
                    if crash_file_name in imp:
                        relevant_files.append({
                            "imports_crash_file": True,
                            **f
                        })

            return {
                "project": project_path,
                "crash_file": crash_file,
                "relevant_files": relevant_files,
            }

    except subprocess.TimeoutExpired:
        return {"error": "codemap timed out"}
    except json.JSONDecodeError:
        return {"error": "codemap output not valid JSON"}
    except Exception as e:
        return {"error": str(e)}

    return None


def format_crash_summary(crash_info, codemap_context=None):
    """Format crash info as human-readable summary."""

    lines = []
    lines.append("=" * 60)
    lines.append("CRASH ANALYSIS")
    lines.append("=" * 60)

    # Crash type
    lines.append(f"\nStop reason: {crash_info['stop_description']}")

    if crash_info.get("fault_address"):
        lines.append(f"Fault address: {crash_info['fault_address']}")

    # Top frames
    lines.append("\nStack trace (top 5 frames):")
    for frame in crash_info["frames"][:5]:
        loc = ""
        if frame.get("file") and frame.get("line"):
            loc = f" at {frame['file']}:{frame['line']}"
        lines.append(f"  #{frame['index']} {frame['function']}{loc}")

    if len(crash_info["frames"]) > 5:
        lines.append(f"  ... and {len(crash_info['frames']) - 5} more frames")

    # codemap context
    if codemap_context and not codemap_context.get("error"):
        lines.append("\nCode context (from codemap):")
        for f in codemap_context.get("relevant_files", [])[:3]:
            if f.get("imports_crash_file"):
                lines.append(f"  → {f['path']} imports the crashed file")
            else:
                funcs = f.get("functions", [])
                lines.append(f"  → {f['path']} ({len(funcs)} functions)")

    lines.append("\n" + "=" * 60)

    return "\n".join(lines)


def crash_explain(debugger, command, result, internal_dict):
    """
    Main LLDB command: crash_explain

    Usage:
        crash_explain           - Show formatted crash summary
        crash_explain --json    - Output raw JSON
        crash_explain --full    - Include memory dump
        crash_explain --codemap /path/to/project - Include codemap context
    """

    args = command.split()
    output_json = "--json" in args
    include_memory = "--full" in args

    # Get codemap project path if specified
    project_path = None
    if "--codemap" in args:
        idx = args.index("--codemap")
        if idx + 1 < len(args):
            project_path = args[idx + 1]

    target = debugger.GetSelectedTarget()
    if not target:
        result.PutCString("Error: No target selected")
        return

    process = target.GetProcess()
    if not process:
        result.PutCString("Error: No process running")
        return

    thread = process.GetSelectedThread()
    if not thread:
        result.PutCString("Error: No thread selected")
        return

    # Gather crash info
    crash_info = get_crash_info(thread, target, include_memory)

    # Try to get project path from first source file if not specified
    if not project_path:
        for frame in crash_info["frames"]:
            if frame.get("file"):
                # Walk up to find project root (look for .git, Package.swift, etc.)
                path = frame["file"]
                for _ in range(10):  # Max 10 levels up
                    parent = os.path.dirname(path)
                    if os.path.exists(os.path.join(parent, ".git")):
                        project_path = parent
                        break
                    if os.path.exists(os.path.join(parent, "Package.swift")):
                        project_path = parent
                        break
                    if parent == path:
                        break
                    path = parent
                if project_path:
                    break

    # Get codemap context
    codemap_context = None
    crash_file = None
    for frame in crash_info["frames"]:
        if frame.get("file"):
            crash_file = frame["file"]
            break

    if project_path and crash_file:
        codemap_context = get_codemap_context(project_path, crash_file)

    # Output
    if output_json:
        output = {
            "crash": crash_info,
            "codemap": codemap_context,
        }
        result.PutCString(json.dumps(output, indent=2))
    else:
        summary = format_crash_summary(crash_info, codemap_context)
        result.PutCString(summary)

        # Hint about JSON output
        result.PutCString("\nTip: Use 'crash_explain --json' for structured output")
        if not codemap_context:
            result.PutCString("Tip: Use 'crash_explain --codemap /path' to include code context")


def run_lldb_command(debugger, cmd):
    """Run an LLDB command and return the output."""
    result = lldb.SBCommandReturnObject()
    debugger.GetCommandInterpreter().HandleCommand(cmd, result)
    if result.Succeeded():
        return result.GetOutput()
    return None


def get_heap_info(debugger, target, top_n=10):
    """
    Get heap allocation information.

    Uses LLDB's heap inspection to find:
    - Total heap size
    - Object counts by class/type
    - Largest allocations
    """
    heap_info = {
        "total_size": 0,
        "allocations_by_type": [],
        "largest_allocations": [],
        "potential_leaks": [],
    }

    # Try to get heap summary using expression evaluation
    # This works for Objective-C/Swift apps with Foundation

    # Method 1: Use malloc_zone_statistics for total heap info
    malloc_stats = run_lldb_command(debugger,
        'expression -l objc -O -- (void)malloc_zone_print(malloc_default_zone(), 1)'
    )

    # Method 2: Use heap command if available (from lldb heap module)
    # This gives us class-level breakdown
    heap_output = run_lldb_command(debugger, 'heap -c')

    if heap_output:
        # Parse heap output: "Class Name                  Count    Total Size"
        lines = heap_output.strip().split('\n')
        for line in lines[2:top_n+2]:  # Skip header lines
            parts = line.split()
            if len(parts) >= 3:
                try:
                    class_name = parts[0]
                    count = int(parts[1])
                    size = int(parts[2])
                    heap_info["allocations_by_type"].append({
                        "class": class_name,
                        "count": count,
                        "total_bytes": size,
                    })
                    heap_info["total_size"] += size
                except (ValueError, IndexError):
                    continue

    # Method 3: For Swift, try to enumerate objects
    # Get all ObjC classes and their instance counts
    objc_classes = run_lldb_command(debugger,
        'expression -l objc -O -- [NSClassFromString(@"NSObject") description]'
    )

    # Try to get malloc stack logging info if enabled
    # (requires MallocStackLogging=1 environment variable)
    malloc_history = run_lldb_command(debugger, 'command script import lldb.macosx.heap')

    return heap_info


def get_memory_regions(debugger, target):
    """Get memory region information from the process."""
    regions = []

    process = target.GetProcess()
    if not process:
        return regions

    # Get memory regions
    region_list = run_lldb_command(debugger, 'memory region --all')

    if region_list:
        for line in region_list.strip().split('\n'):
            if '[' in line and ']' in line:
                regions.append(line.strip())

    return regions


def get_swift_object_counts(debugger, class_names):
    """Try to get instance counts for specific Swift/ObjC classes."""
    counts = {}

    for class_name in class_names:
        # Use ObjC runtime to count instances
        result = run_lldb_command(debugger,
            f'expression -l objc -O -- (int)[NSClassFromString(@"{class_name}") instanceCount]'
        )
        if result and result.strip().isdigit():
            counts[class_name] = int(result.strip())

    return counts


def find_project_root(debugger, target):
    """Try to find the project root from debug symbols."""
    # Look at the main executable's source files
    for module in target.module_iter():
        for cu in module.compile_unit_iter():
            file_spec = cu.GetFileSpec()
            if file_spec.IsValid():
                path = str(file_spec)
                # Walk up to find project root
                for _ in range(10):
                    parent = os.path.dirname(path)
                    if os.path.exists(os.path.join(parent, ".git")):
                        return parent
                    if os.path.exists(os.path.join(parent, "Package.swift")):
                        return parent
                    if os.path.exists(os.path.join(parent, ".xcodeproj")):
                        return os.path.dirname(parent)
                    if parent == path:
                        break
                    path = parent
    return None


def memory_explain(debugger, command, result, internal_dict):
    """
    LLDB command: memory_explain

    Analyzes current memory usage and provides context for LLM explanation.

    Usage:
        memory_explain              - Show memory analysis summary
        memory_explain --top 20     - Show top 20 allocation types
        memory_explain --json       - Output raw JSON
        memory_explain --classes Foo,Bar - Focus on specific classes
    """

    args = command.split()
    output_json = "--json" in args

    # Parse --top N
    top_n = 10
    if "--top" in args:
        idx = args.index("--top")
        if idx + 1 < len(args):
            try:
                top_n = int(args[idx + 1])
            except ValueError:
                pass

    # Parse --classes
    focus_classes = []
    if "--classes" in args:
        idx = args.index("--classes")
        if idx + 1 < len(args):
            focus_classes = args[idx + 1].split(",")

    target = debugger.GetSelectedTarget()
    if not target:
        result.PutCString("Error: No target selected")
        return

    process = target.GetProcess()
    if not process:
        result.PutCString("Error: No process running")
        return

    result.PutCString("Analyzing memory usage...")

    # Gather memory info
    heap_info = get_heap_info(debugger, target, top_n)
    regions = get_memory_regions(debugger, target)

    # Get focused class counts if specified
    if focus_classes:
        class_counts = get_swift_object_counts(debugger, focus_classes)
        heap_info["focus_classes"] = class_counts

    # Try to get project context
    project_path = find_project_root(debugger, target)
    codemap_context = None

    if project_path:
        try:
            deps_result = subprocess.run(
                ["codemap", "--deps", project_path],
                capture_output=True,
                text=True,
                timeout=10
            )
            if deps_result.returncode == 0:
                codemap_context = deps_result.stdout
        except:
            pass

    # Build analysis output
    analysis = {
        "heap": heap_info,
        "memory_regions_count": len(regions),
        "project_path": project_path,
        "codemap_available": codemap_context is not None,
    }

    if output_json:
        output = {
            "memory": analysis,
            "codemap": codemap_context,
        }
        result.PutCString(json.dumps(output, indent=2))
    else:
        # Human-readable output
        lines = []
        lines.append("=" * 60)
        lines.append("MEMORY ANALYSIS")
        lines.append("=" * 60)

        if heap_info["allocations_by_type"]:
            lines.append(f"\nTop {len(heap_info['allocations_by_type'])} allocations by type:")
            lines.append(f"{'Class':<40} {'Count':>10} {'Size':>12}")
            lines.append("-" * 64)

            for alloc in heap_info["allocations_by_type"]:
                size_str = format_bytes(alloc["total_bytes"])
                lines.append(f"{alloc['class']:<40} {alloc['count']:>10} {size_str:>12}")
        else:
            lines.append("\nNote: Heap analysis requires the 'heap' command.")
            lines.append("Try: (lldb) command script import lldb.macosx.heap")
            lines.append("Then run: memory_explain")

        if heap_info.get("focus_classes"):
            lines.append(f"\nFocused classes:")
            for cls, count in heap_info["focus_classes"].items():
                lines.append(f"  {cls}: {count} instances")

        lines.append(f"\nMemory regions: {len(regions)}")

        if project_path:
            lines.append(f"Project: {project_path}")
            if codemap_context:
                lines.append("codemap: available (use --json for full context)")

        lines.append("\n" + "=" * 60)
        lines.append("\nTip: Use 'memory_explain --json | memory-explainer -' for LLM analysis")

        result.PutCString("\n".join(lines))


def format_bytes(num_bytes):
    """Format bytes as human-readable string."""
    for unit in ['B', 'KB', 'MB', 'GB']:
        if abs(num_bytes) < 1024.0:
            return f"{num_bytes:.1f} {unit}"
        num_bytes /= 1024.0
    return f"{num_bytes:.1f} TB"


def __lldb_init_module(debugger, internal_dict):
    """Called when the module is loaded by LLDB."""

    # Import heap module for memory analysis
    debugger.HandleCommand('command script import lldb.macosx.heap')

    debugger.HandleCommand(
        'command script add -f crash_capture.crash_explain crash_explain'
    )
    debugger.HandleCommand(
        'command script add -f crash_capture.memory_explain memory_explain'
    )

    print("memory-explainer loaded!")
    print("  crash_explain  - Analyze crashes")
    print("  memory_explain - Analyze memory usage")
