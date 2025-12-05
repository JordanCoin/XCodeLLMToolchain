
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


def trim_for_llm(output, max_frames=50, max_vars=10):
    """
    Trim crash data to fit Foundation Models' ~32k token limit (macOS 26+).
    Prioritizes user code frames while keeping context.
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

        # Smart Frame Selection
        # 1. Always keep top 3 frames (context of crash)
        # 2. Keep all USER frames (up to limit)
        # 3. Skip middle system frames
        
        all_frames = crash.get("frames", [])
        keep_indices = set()
        
        # Always keep top 3
        for i in range(min(3, len(all_frames))):
            keep_indices.add(i)
            
        # Find user frames
        user_frame_count = 0
        for i, frame in enumerate(all_frames):
            if not frame.get("is_system", False):
                keep_indices.add(i)
                user_frame_count += 1
                if user_frame_count >= max_frames:
                    break
        
        # Sort indices
        sorted_indices = sorted(list(keep_indices))
        
        for i in sorted_indices:
            frame = all_frames[i]
            trimmed_frame = {
                "index": frame.get("index"),
                "function": frame.get("function", "<unknown>"),
                "file": frame.get("file"),
                "line": frame.get("line"),
                "is_system": frame.get("is_system"),
            }
            # Keep only first few variables, trim values
            if "variables" in frame:
                trimmed_vars = []
                for var in frame["variables"][:max_vars]:
                    trimmed_vars.append({
                        "name": var.get("name"),
                        "type": var.get("type"),
                        "value": str(var.get("value", ""))[:200],  # Increased truncation limit
                    })
                if trimmed_vars:
                    trimmed_frame["variables"] = trimmed_vars

            trimmed["crash"]["frames"].append(trimmed_frame)

    # Include full codemap if available (we have room now)
    if output.get("codemap"):
        trimmed["codemap"] = output["codemap"]
    if output.get("project_path"):
        trimmed["project_path"] = output["project_path"]

    return trimmed


def format_bytes(num_bytes):
    """Format bytes as human-readable string."""
    for unit in ['B', 'KB', 'MB', 'GB']:
        if abs(num_bytes) < 1024.0:
            return f"{num_bytes:.1f} {unit}"
        num_bytes /= 1024.0
    return f"{num_bytes:.1f} TB"
