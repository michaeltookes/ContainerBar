#!/usr/bin/env python3
"""Exit 0 only when the given keychain is readable AND currently unlocked (SecKeychainGetStatus, kSecUnlockStateStatus).

Fail closed: any error, missing framework or unreadable status exits 1 (resign.sh reports BLOCKED keychain-locked).
`security show-keychain-info` is not used: it reports timeout settings and succeeds on a locked keychain.
"""
import ctypes
import ctypes.util
import sys

K_SEC_UNLOCK_STATE_STATUS = 1


def unlocked(path: str) -> bool:
    try:
        sec = ctypes.CDLL("/System/Library/Frameworks/Security.framework/Security")
        cf = ctypes.CDLL(ctypes.util.find_library("CoreFoundation"))
        ref = ctypes.c_void_p()
        sec.SecKeychainOpen.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]
        sec.SecKeychainGetStatus.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint32)]
        if sec.SecKeychainOpen(path.encode(), ctypes.byref(ref)) != 0 or not ref.value:
            return False
        status = ctypes.c_uint32(0)
        rc = sec.SecKeychainGetStatus(ref, ctypes.byref(status))
        cf.CFRelease.argtypes = [ctypes.c_void_p]
        cf.CFRelease(ref)
        return rc == 0 and bool(status.value & K_SEC_UNLOCK_STATE_STATUS)
    except Exception:
        return False


if __name__ == "__main__":
    sys.exit(0 if len(sys.argv) == 2 and unlocked(sys.argv[1]) else 1)
