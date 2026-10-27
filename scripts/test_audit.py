#!/usr/bin/env python3
"""Exercise the publishing boundary using synthetic in-memory fixtures only."""
import contextlib
import importlib.util
import io
import pathlib
import struct

path = pathlib.Path(__file__).with_name("audit.py")
spec = importlib.util.spec_from_file_location("audit_under_test", path)
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


def check(files, expected):
    def fake_git(*args):
        if args[0] == "diff":
            return b"\0".join(name.encode() for name in files) + b"\0"
        return files[args[1][1:]]
    audit.git = fake_git
    output = io.StringIO()
    with contextlib.redirect_stderr(output), contextlib.redirect_stdout(output):
        result = audit.audit(True)
    assert result == expected
    return output.getvalue()


secret = "sk" + "-" + "A" * 32
report = check({"Sources/Example.swift": ("let value = \"" + secret + "\"").encode()}, 1)
assert secret not in report
check({"Sources/Example.swift": b'let endpoint = "https://api.deepseek.com"'}, 0)
check({"outputs/meeting.json": b"{}"}, 1)
check({".env": b"empty"}, 1)
local_path = "/" + "Users" + "/" + "fixture-person" + "/project"
check({"Tests/Fixture.swift": local_path.encode()}, 1)
metadata_png = b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 0) + b"eXIf" + bytes(4)
check({"docs/images/test.png": metadata_png}, 1)
print("Audit tests passed: secrets, personal paths, meeting files and image metadata blocked; matched values never printed.")
