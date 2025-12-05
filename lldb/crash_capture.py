#!/usr/bin/env python3
"""
LLDB crash capture script for memory-explainer.

Captures crash context (stack trace, memory info, crash reason) and outputs
structured JSON that can be piped to codemap and/or Foundation Models.

Installation:
    Add to ~/.lldbinit-Xcode:
    command script import ~/Code/memory-explainer/lldb/crash_capture.py

Usage in LLDB:
    (lldb) crash_explain           # Basic crash info
    (lldb) crash_explain --full    # Include memory dump
    (lldb) crash_explain --json    # Raw JSON output
"""

import lldb
import json
import subprocess
import os
import shutil
import sys


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
        try:
            for var in frame.GetVariables(True, True, True, True):
                var_info = {
                    "name": var.GetName(),
                    "type": var.GetTypeName(),
                    "value": var.GetValue(),
                    "summary": var.GetSummary(),
                }
                variables.append(var_info)
        except Exception as e:
            # Don't fail the whole dump if variable inspect fails
            pass

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
                            # We catch errors here to prevent crashing the script
                            mem_before = target.GetProcess().ReadMemory(
                                max(0, addr - 64), 64, error
                            )
                            if error.Success() and mem_before:
                                crash_info["memory_before"] = mem_before.hex()
                            
                            # Read memory at address
                            mem_at = target.GetProcess().ReadMemory(
                                addr, 64, error
                            )
                            if error.Success() and mem_at:
                                crash_info["memory_at"] = mem_at.hex()

                        except ValueError:
                            pass  # int conversion failed
                        except Exception as e:
                            crash_info["memory_error"] = str(e)
                except Exception as e:
                    # Failed to parse address
                    pass

    return crash_info


def find_codemap_binary():
    """Find the codemap binary, looking in common paths if not in PATH."""
    
    # Check current PATH
    path = shutil.which("codemap")
    if path:
        return path
        
    # Check common locations for Homebrew
    common_paths = [
        "/opt/homebrew/bin/codemap",
        "/usr/local/bin/codemap",
        os.path.expanduser("~/go/bin/codemap")  # Common Go install path
    ]
    
    for p in common_paths:
        if os.path.exists(p) and os.access(p, os.X_OK):
            return p
            
    return None


def get_codemap_context(project_path, crash_file):
    """Run codemap to get dependency context for the crashed file."""

    if not project_path or not crash_file:
        return None

    try:
        codemap_bin = find_codemap_binary()
        if not codemap_bin:
            return {"error": "codemap not found. Install with: brew install jordancoin/tap/codemap"}

        # Get dependencies
        deps_result = subprocess.run(
            [codemap_bin, "--deps", "--json", project_path],
            capture_output=True,
            text=True,
            timeout=10,
            env=dict(os.environ, PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin") # Ensure basic path
        )

        if deps_result.returncode == 0:
            try:
                deps = json.loads(deps_result.stdout)
            except json.JSONDecodeError:
                return {"error": "codemap output not valid JSON"}

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
        else:
             return {"error": f"codemap failed with code {deps_result.returncode}: {deps_result.stderr}"}

    except subprocess.TimeoutExpired:
        return {"error": "codemap timed out"}
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
    elif codemap_context and codemap_context.get("error"):
         lines.append(f"\nCode context error: {codemap_context['error']}")

    lines.append("\n" + "=" * 60)

    return "\n".join(lines)


def find_memory_explainer_binary():
    """Find the memory-explainer binary."""
    common_paths = [
        shutil.which("memory-explainer"),
        "/opt/homebrew/bin/memory-explainer",
        "/usr/local/bin/memory-explainer",
        os.path.expanduser("~/Code/memory-explainer/MemoryExplainer/.build/debug/memory-explainer"),
        os.path.expanduser("~/Code/memory-explainer/MemoryExplainer/.build/release/memory-explainer"),
    ]

    for p in common_paths:
        if p and os.path.exists(p) and os.access(p, os.X_OK):
            return p
    return None


def trim_for_llm(output, max_frames=5, max_vars=3):
    """
    Trim crash data to fit Foundation Models' 4096 token limit.
    Keep only the essential info for diagnosis.
    """
    trimmed = {}

    if "crash" in output and output["crash"]:
        crash = output["crash"]
        trimmed["crash"] = {
            "stop_description": crash.get("stop_description", ""),
            "stop_reason_type": crash.get("stop_reason_type", ""),
            "crash_type": crash.get("crash_type", ""),
            "fault_address": crash.get("fault_address"),
            "frames": [],
        }

        # Keep only top N frames, trim each frame
        for frame in crash.get("frames", [])[:max_frames]:
            trimmed_frame = {
                "index": frame.get("index"),
                "function": frame.get("function", "<unknown>"),
                "file": frame.get("file"),
                "line": frame.get("line"),
            }
            # Keep only first few variables, trim values
            if "variables" in frame:
                trimmed_vars = []
                for var in frame["variables"][:max_vars]:
                    trimmed_vars.append({
                        "name": var.get("name"),
                        "type": var.get("type"),
                        "value": str(var.get("value", ""))[:50],  # Truncate long values
                    })
                if trimmed_vars:
                    trimmed_frame["variables"] = trimmed_vars

            trimmed["crash"]["frames"].append(trimmed_frame)

    # Skip codemap for now - too big
    # Just include project path
    if output.get("project_path"):
        trimmed["project_path"] = output["project_path"]

    return trimmed


def crash_explain(debugger, command, result, internal_dict):
    """
    Main LLDB command: crash_explain

    Usage:
        crash_explain           - Show formatted crash summary
        crash_explain --json    - Output raw JSON
        crash_explain --full    - Include memory dump
        crash_explain --explain - Send to memory-explainer for LLM analysis
        crash_explain --codemap /path/to/project - Include codemap context
    """

    args = command.split()
    output_json = "--json" in args
    include_memory = "--full" in args
    run_explainer = "--explain" in args

    # Get codemap project path if specified
    project_path = None
    if "--codemap" in args:
        try:
            idx = args.index("--codemap")
            if idx + 1 < len(args):
                project_path = args[idx + 1]
        except ValueError:
            pass

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

    # Build JSON output
    output = {
        "crash": crash_info,
        "codemap": codemap_context,
    }
    if project_path:
        output["project_path"] = project_path

    # Output
    if run_explainer:
        # Send directly to memory-explainer
        explainer_bin = find_memory_explainer_binary()
        if not explainer_bin:
            result.PutCString("Error: memory-explainer not found.")
            result.PutCString("Build it: cd ~/Code/memory-explainer/MemoryExplainer && swift build")
            return

        result.PutCString("🧠 Analyzing crash with Foundation Models...")

        # Trim data to fit token limit (Foundation Models has 4096 limit)
        trimmed_output = trim_for_llm(output)

        try:
            json_data = json.dumps(trimmed_output)
            proc = subprocess.run(
                [explainer_bin],
                input=json_data,
                capture_output=True,
                text=True,
                timeout=60  # LLM can take a bit
            )
            if proc.returncode == 0:
                result.PutCString(proc.stdout)
            else:
                result.PutCString(f"Error: {proc.stderr}")
        except subprocess.TimeoutExpired:
            result.PutCString("Error: Analysis timed out (60s)")
        except Exception as e:
            result.PutCString(f"Error running memory-explainer: {e}")

    elif output_json:
        result.PutCString(json.dumps(output, indent=2))
    else:
        summary = format_crash_summary(crash_info, codemap_context)
        result.PutCString(summary)

        # Hint about LLM analysis
        result.PutCString("\nTip: Use 'crash_explain --explain' for LLM analysis")
        result.PutCString("     Use 'crash_explain --json' for raw JSON output")


def __lldb_init_module(debugger, internal_dict):
    """Called when the module is loaded by LLDB."""

    debugger.HandleCommand(
        'command script add -f crash_capture.crash_explain crash_explain'
    )
    print("memory-explainer: 'crash_explain' command loaded")
    print("  Usage: crash_explain [--json] [--full] [--codemap /path/to/project]")
    return None


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

    Analyzes current memory usage using available LLDB introspection.

    Usage:
        memory_explain              - Show memory analysis with LLM
        memory_explain --json       - Output raw JSON
    """

    args = command.split()
    output_json = "--json" in args

    target = debugger.GetSelectedTarget()
    if not target:
        result.PutCString("Error: No target selected")
        return

    process = target.GetProcess()
    if not process:
        result.PutCString("Error: No process running")
        return

    result.PutCString("Gathering memory info...")

    memory_info = {
        "process": {
            "pid": process.GetProcessID(),
            "state": str(process.GetState()),
        },
        "modules": [],
        "threads": process.GetNumThreads(),
    }

    # Get loaded modules (dylibs) - indicates what's loaded in memory
    module_count = target.GetNumModules()
    app_modules = []
    framework_count = 0
    dylib_count = 0

    for i in range(min(module_count, 50)):  # Limit to prevent huge output
        module = target.GetModuleAtIndex(i)
        if module:
            path = str(module.GetFileSpec())
            if ".app/" in path:
                # App's own code
                app_modules.append(os.path.basename(path))
            elif "System/Library" in path or "/usr/lib" in path:
                framework_count += 1
            else:
                dylib_count += 1

    memory_info["modules"] = {
        "app_binaries": app_modules[:10],  # Limit
        "system_frameworks": framework_count,
        "other_dylibs": dylib_count,
        "total": module_count,
    }

    # Try to get malloc info via expression
    malloc_output = run_lldb_command(debugger,
        'expression -l objc -O -- (void)malloc_zone_print(malloc_default_zone(), 0)'
    )
    if malloc_output and "bytes" in malloc_output.lower():
        memory_info["malloc_info"] = malloc_output[:500]  # Truncate

    # Get basic process memory info if available
    mem_info_output = run_lldb_command(debugger, 'process status')
    if mem_info_output:
        memory_info["process_status"] = mem_info_output[:300]

    # Try vmmap-style info (may not work in all contexts)
    vm_output = run_lldb_command(debugger, 'memory region 0x0')
    if vm_output and "error" not in vm_output.lower():
        memory_info["has_vm_regions"] = True

    # Get project path
    project_path = find_project_root(debugger, target)
    if project_path:
        memory_info["project_path"] = project_path

    if output_json:
        result.PutCString(json.dumps({"memory": memory_info}, indent=2))
        return

    # Send to LLM for analysis
    explainer_bin = find_memory_explainer_binary()
    if not explainer_bin:
        # Fall back to just showing the data
        result.PutCString("\n" + "=" * 60)
        result.PutCString("MEMORY INFO")
        result.PutCString("=" * 60)
        result.PutCString(f"\nProcess: PID {memory_info['process']['pid']}")
        result.PutCString(f"Threads: {memory_info['threads']}")
        result.PutCString(f"Modules loaded: {memory_info['modules']['total']}")
        result.PutCString(f"  App binaries: {', '.join(memory_info['modules']['app_binaries'])}")
        result.PutCString(f"  System frameworks: {memory_info['modules']['system_frameworks']}")
        if project_path:
            result.PutCString(f"Project: {project_path}")
        result.PutCString("\nBuild memory-explainer for LLM analysis")
        return

    result.PutCString("🧠 Analyzing memory with Foundation Models...")

    try:
        json_data = json.dumps({"memory": memory_info})
        proc = subprocess.run(
            [explainer_bin],
            input=json_data,
            capture_output=True,
            text=True,
            timeout=60
        )
        if proc.returncode == 0:
            result.PutCString(proc.stdout)
        else:
            result.PutCString(f"Error: {proc.stderr}")
    except subprocess.TimeoutExpired:
        result.PutCString("Error: Analysis timed out")
    except Exception as e:
        result.PutCString(f"Error: {e}")


def format_bytes(num_bytes):
    """Format bytes as human-readable string."""
    for unit in ['B', 'KB', 'MB', 'GB']:
        if abs(num_bytes) < 1024.0:
            return f"{num_bytes:.1f} {unit}"
        num_bytes /= 1024.0
    return f"{num_bytes:.1f} TB"


def explain_here(debugger, command, result, internal_dict):
    """
    LLDB command: explain_here

    Explains the current execution state at any breakpoint or stop.
    Uses Foundation Models to analyze variables, call stack, and context.

    Usage:
        explain_here          - Explain current state with LLM
        explain_here --json   - Output raw JSON
    """
    args = command.split()
    output_json = "--json" in args

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

    # Find the first frame with user source code (skip system frames)
    user_frame = None
    for f in thread:
        le = f.GetLineEntry()
        if le.IsValid():
            file_path = str(le.GetFileSpec())
            # Skip system/framework code - look for user source
            if file_path and not file_path.startswith("/usr/") and not file_path.startswith("/System/") \
               and not "Xcode.app" in file_path and ".swift" in file_path or ".m" in file_path:
                user_frame = f
                break

    # Fall back to selected frame if no user code found
    frame = user_frame or thread.GetSelectedFrame()
    if not frame:
        result.PutCString("Error: No frame selected")
        return

    # Gather context about current location
    context = {
        "location": {
            "function": frame.GetFunctionName() or "<unknown>",
            "file": None,
            "line": None,
        },
        "stop_reason": thread.GetStopDescription(256),
        "variables": [],
        "call_stack": [],
    }

    # Get source location
    line_entry = frame.GetLineEntry()
    if line_entry.IsValid():
        file_spec = line_entry.GetFileSpec()
        context["location"]["file"] = file_spec.GetFilename()  # Just filename, not full path
        context["location"]["full_path"] = str(file_spec)
        context["location"]["line"] = line_entry.GetLine()

    # Get local variables (limit to prevent token overflow)
    for var in frame.GetVariables(True, True, False, True):  # args, locals, statics, scope
        var_info = {
            "name": var.GetName(),
            "type": var.GetTypeName(),
            "value": var.GetValue(),
        }
        # Add summary for complex types
        summary = var.GetSummary()
        if summary:
            var_info["summary"] = summary[:100]  # Truncate

        context["variables"].append(var_info)
        if len(context["variables"]) >= 10:  # Limit variables
            break

    # Get call stack (top 5 frames)
    for i, f in enumerate(thread):
        if i >= 5:
            break
        stack_frame = {
            "index": i,
            "function": f.GetFunctionName() or "<unknown>",
        }
        le = f.GetLineEntry()
        if le.IsValid():
            stack_frame["file"] = str(le.GetFileSpec().GetFilename())
            stack_frame["line"] = le.GetLine()
        context["call_stack"].append(stack_frame)

    # Try to get project path
    project_path = find_project_root(debugger, target)
    if project_path:
        context["project_path"] = project_path

    # Try to read source code around the breakpoint
    if context["location"].get("full_path") and context["location"].get("line"):
        try:
            source_path = context["location"]["full_path"]
            line_num = context["location"]["line"]
            if os.path.exists(source_path):
                with open(source_path, 'r') as f:
                    lines = f.readlines()
                    start = max(0, line_num - 5)
                    end = min(len(lines), line_num + 5)
                    source_snippet = []
                    for i in range(start, end):
                        marker = ">>>" if i + 1 == line_num else "   "
                        source_snippet.append(f"{marker} {i+1}: {lines[i].rstrip()}")
                    context["source_code"] = "\n".join(source_snippet)
        except Exception:
            pass  # Don't fail if we can't read source

    if output_json:
        result.PutCString(json.dumps({"context": context}, indent=2))
        return

    # Send to LLM
    explainer_bin = find_memory_explainer_binary()
    if not explainer_bin:
        result.PutCString("Error: memory-explainer not found.")
        result.PutCString("Build it: cd ~/Code/memory-explainer/MemoryExplainer && swift build")
        return

    result.PutCString(f"🔍 Analyzing: {context['location']['function']}")
    if context['location']['file']:
        result.PutCString(f"   at {context['location']['file']}:{context['location']['line']}")
    result.PutCString("")

    try:
        # Format for the LLM - use generic explain since it's not a crash
        llm_input = {
            "breakpoint": context,
            "project_path": project_path,
        }
        json_data = json.dumps(llm_input)

        proc = subprocess.run(
            [explainer_bin],
            input=json_data,
            capture_output=True,
            text=True,
            timeout=60
        )
        if proc.returncode == 0:
            result.PutCString(proc.stdout)
        else:
            result.PutCString(f"Error: {proc.stderr}")
    except subprocess.TimeoutExpired:
        result.PutCString("Error: Analysis timed out (60s)")
    except Exception as e:
        result.PutCString(f"Error: {e}")


def __lldb_init_module(debugger, internal_dict):
    """Called when the module is loaded by LLDB."""

    # Import heap module for memory analysis
    debugger.HandleCommand('command script import lldb.macosx.heap')

    debugger.HandleCommand(
        'command script add -o -f crash_capture.crash_explain crash_explain'
    )
    debugger.HandleCommand(
        'command script add -o -f crash_capture.memory_explain memory_explain'
    )
    debugger.HandleCommand(
        'command script add -o -f crash_capture.explain_here explain_here'
    )

    print("memory-explainer loaded!")
    print("  explain_here   - Explain current state at any breakpoint")
    print("  crash_explain  - Analyze crashes (use --explain for LLM)")
    print("  memory_explain - Analyze memory usage")
