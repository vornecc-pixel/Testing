#!/usr/bin/env python3
"""Runs tests/run_tests.lua without needing a system Lua binary (uses lupa).

    pip install lupa
    python3 tests/run.py
"""
import os
import sys

try:
    import lupa
except ImportError:
    sys.exit("needs lupa:  pip install lupa")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

lua = lupa.LuaRuntime(unpack_returned_tuples=True)
lua.execute('package.path = "./tests/?.lua;" .. package.path')

# run_tests.lua calls os.exit(); capture the status instead of letting it
# terminate this process, then mirror it as our own exit code.
runner = lua.eval(
    """
    function(path)
        local realExit = os.exit
        local code = 0
        os.exit = function(c) code = c or 0; error({ __exit = true }, 0) end
        local ok, err = xpcall(function()
            return assert(loadfile(path))()
        end, function(e) return e end)
        os.exit = realExit
        if type(err) == "table" and err.__exit then return code end
        if not ok then return 1, tostring(err) end
        return code
    end
    """
)

result = runner("tests/run_tests.lua")
if isinstance(result, tuple):
    code, err = result
else:
    code, err = result, None
if err:
    print(f"Lua error: {err}", file=sys.stderr)
sys.exit(int(code or 0))
