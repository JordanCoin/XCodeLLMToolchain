
import lldb
import json
import os
import subprocess
from .analysis import (
    get_crash_info, 
    get_heap_info, 
    get_memory_regions, 
    find_project_root
)
from .tools import (
    find_codemap_binary, 
    get_codemap_context, 
    find_memory_explainer_binary
)
from .formatting import (
    format_crash_summary, 
    trim_for_llm, 
    format_bytes
)
from .utils import run_lldb_command


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
            "value": str(var.GetValue())[:100],  # Truncate
            "summary": str(var.GetSummary())[:100],
        }
        context["variables"].append(var_info)

    # Get call stack
    for f in thread:
        if f.GetFrameID() < 10:  # Top 10 frames
            context["call_stack"].append({
                "index": f.GetFrameID(),
                "function": f.GetFunctionName(),
            })

    if output_json:
        result.PutCString(json.dumps(context, indent=2))
        return

    # Send to LLM
    explainer_bin = find_memory_explainer_binary()
    if not explainer_bin:
        result.PutCString("Error: memory-explainer not found")
        return

    result.PutCString("🧠 Analyzing breakpoint state...")

    try:
        json_data = json.dumps({"breakpoint": context})
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
    except Exception as e:
        result.PutCString(f"Error: {e}")
