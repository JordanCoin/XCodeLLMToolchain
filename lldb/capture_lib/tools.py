
import os
import shutil
import json
import subprocess

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


def find_xcode_llm_binary():
    """Find the xcode-llm binary."""
    common_paths = [
        shutil.which("xcode-llm"),
        "/opt/homebrew/bin/xcode-llm",
        "/usr/local/bin/xcode-llm",
        os.path.expanduser("~/Code/XcodeLLMToolchain/.build/debug/xcode-llm"),
        os.path.expanduser("~/Code/XcodeLLMToolchain/.build/release/xcode-llm"),
        # Legacy paths for transition
        os.path.expanduser("~/Code/memory-explainer/.build/debug/xcode-llm"),
        os.path.expanduser("~/Code/memory-explainer/.build/release/xcode-llm"),
    ]

    for p in common_paths:
        if p and os.path.exists(p) and os.access(p, os.X_OK):
            return p
    return None


# Alias for backwards compatibility
find_memory_explainer_binary = find_xcode_llm_binary
