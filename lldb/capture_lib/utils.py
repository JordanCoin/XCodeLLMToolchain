
import lldb

def run_lldb_command(debugger, cmd):
    """Run an LLDB command and return the output."""
    result = lldb.SBCommandReturnObject()
    debugger.GetCommandInterpreter().HandleCommand(cmd, result)
    if result.Succeeded():
        return result.GetOutput()
    return None
