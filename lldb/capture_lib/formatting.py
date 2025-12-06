
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


def trim_for_llm(output, max_frames=5, max_vars=3, max_chars=10000):
    """
    Trim crash data to fit Foundation Models' 4096 token limit.

    4096 tokens ≈ 16,000 chars total (input + output).
    Reserve ~6000 chars for output, so input budget is ~10,000 chars.

    Strategy: Be ruthless. Only keep what's essential for diagnosis.
    """
    trimmed = {}

    if "crash" in output and output["crash"]:
        crash = output["crash"]
        trimmed["crash"] = {
            "stop": crash.get("stop_description", "")[:200],
            "type": crash.get("crash_type", ""),
        }

        if crash.get("fault_address"):
            trimmed["crash"]["addr"] = crash.get("fault_address")

        # Only keep frames with SOURCE FILES (user code)
        # System frames rarely have file info, user code always does
        all_frames = crash.get("frames", [])
        user_frames = [f for f in all_frames if f.get("file") and not f.get("is_system", False)]

        # Filter out Swift/system prefixes even if they have file info
        user_frames = [f for f in user_frames if not any(
            f.get("function", "").startswith(p) for p in
            ["Swift.", "_swift_", "libswift", "@objc", "dispatch_", "CFRunLoop"]
        )]

        # Still nothing? Fall back to any frame with a file
        if not user_frames:
            user_frames = [f for f in all_frames if f.get("file")]

        # Last resort: top 3
        if not user_frames:
            user_frames = all_frames[:3]

        selected = user_frames[:max_frames]

        trimmed["frames"] = []
        for frame in selected:
            f = {
                "fn": frame.get("function", "?")[:100],  # Truncate long names
            }
            if frame.get("file"):
                # Just filename, not full path
                import os
                f["file"] = os.path.basename(frame.get("file", ""))
            if frame.get("line"):
                f["line"] = frame.get("line")

            # Only keep a few key variables, very short values
            if "variables" in frame and frame["variables"]:
                vars_compact = []
                for var in frame["variables"][:max_vars]:
                    v = var.get("value") or var.get("summary") or ""
                    vars_compact.append(f"{var.get('name')}={str(v)[:50]}")
                if vars_compact:
                    f["vars"] = vars_compact

            trimmed["frames"].append(f)

    # Skip codemap - too large, doesn't fit in 4096 tokens
    # Skip project_path - not needed for analysis

    # Final size check - if still too big, drop variables
    import json
    result_json = json.dumps(trimmed)
    if len(result_json) > max_chars:
        # Drop all variables to fit
        for f in trimmed.get("frames", []):
            f.pop("vars", None)

    return trimmed


def format_bytes(num_bytes):
    """Format bytes as human-readable string."""
    for unit in ['B', 'KB', 'MB', 'GB']:
        if abs(num_bytes) < 1024.0:
            return f"{num_bytes:.1f} {unit}"
        num_bytes /= 1024.0
    return f"{num_bytes:.1f} TB"
