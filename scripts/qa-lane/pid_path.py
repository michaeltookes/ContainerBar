#!/usr/bin/env python3
"""Print the resolved executable path of a PID (proc_pidpath). Exit 1 when it cannot be resolved (callers fail closed)."""
import ctypes
import ctypes.util
import sys


def pid_path(pid: int) -> str:
    libproc = ctypes.CDLL(ctypes.util.find_library("proc") or "/usr/lib/libproc.dylib")
    buf = ctypes.create_string_buffer(4096)  # PROC_PIDPATHINFO_MAXSIZE
    n = libproc.proc_pidpath(ctypes.c_int(pid), buf, ctypes.c_uint32(len(buf)))
    return buf.value.decode() if n > 0 else ""


if __name__ == "__main__":
    try:
        path = pid_path(int(sys.argv[1])) if len(sys.argv) == 2 else ""
    except Exception:
        path = ""
    if not path:
        sys.exit(1)
    print(path)
