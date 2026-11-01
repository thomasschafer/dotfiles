"""Prints the arguments and start time of macOS processes, as JSON keyed by PID.

rex/restore.lua runs this, as Rex reports a terminal's foreground process without its
arguments. A process that has exited, or can't be read, is left out.
"""

import ctypes
import json
import struct
import sys

CTL_KERN = 1
KERN_ARGMAX = 8
KERN_PROC = 14
KERN_PROC_PID = 1
KERN_PROCARGS2 = 49

libc = ctypes.CDLL(None, use_errno=True)


def sysctl(mib: list[int], size: int) -> bytes | None:
    buf = ctypes.create_string_buffer(size)
    length = ctypes.c_size_t(size)
    mib_array = (ctypes.c_int * len(mib))(*mib)
    if libc.sysctl(mib_array, len(mib), buf, ctypes.byref(length), None, 0) != 0:
        return None
    return buf.raw[: length.value]


def arg_max() -> int:
    raw = sysctl([CTL_KERN, KERN_ARGMAX], ctypes.sizeof(ctypes.c_int))
    if raw is None:
        raise OSError(ctypes.get_errno(), "sysctl kern.argmax failed")
    return struct.unpack("i", raw)[0]


def argv(pid: int, size: int) -> list[str] | None:
    # The buffer holds argc, the executable's path, NUL padding, then argc NUL-terminated
    # arguments, followed by the environment.
    raw = sysctl([CTL_KERN, KERN_PROCARGS2, pid], size)
    if raw is None or len(raw) < 4:
        return None
    argc = struct.unpack_from("i", raw)[0]
    rest = raw[4:]
    end_of_path = rest.find(b"\0")
    if end_of_path < 0:
        return None
    rest = rest[end_of_path:].lstrip(b"\0")
    args = rest.split(b"\0")[:argc]
    if len(args) != argc:
        return None
    return [arg.decode("utf-8", "surrogateescape") for arg in args]


def started_at(pid: int) -> float | None:
    # struct kinfo_proc starts with the process's start time, a struct timeval.
    raw = sysctl([CTL_KERN, KERN_PROC, KERN_PROC_PID, pid], 1024)
    if raw is None or len(raw) < 16:
        return None
    seconds, microseconds = struct.unpack_from("qi", raw)
    if seconds == 0:
        return None
    return seconds + microseconds / 1_000_000


def main() -> None:
    size = arg_max()
    result = {}
    for value in sys.argv[1:]:
        pid = int(value)
        args, start = argv(pid, size), started_at(pid)
        if args is not None and start is not None:
            result[str(pid)] = {"argv": args, "started_at": start}
    json.dump(result, sys.stdout)


main()
