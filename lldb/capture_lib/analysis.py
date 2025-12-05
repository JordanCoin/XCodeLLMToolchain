
import lldb
import os
from .utils import run_lldb_command

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
            "is_system": False,
            "file": None,
            "line": None,
            "column": None,
            "pc": hex(frame.GetPC()),
            "sp": hex(frame.GetSP()),
            "fp": hex(frame.GetFP()),
        }

        # Heuristic: Check if system frame
        if frame_info["module"]:
             mod_path = str(frame.GetModule().GetFileSpec())
             if mod_path.startswith("/System") or mod_path.startswith("/usr/lib") or ".app/Contents/Developer" in mod_path:
                 frame_info["is_system"] = True

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
