#!/usr/bin/env python3
"""Audit the Git publishing boundary. Never print matched credential values."""
import argparse
import pathlib
import re
import struct
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
RULES = {
    "private key": re.compile(r"-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----"),
    "provider API key": re.compile(r"\bsk-[A-Za-z0-9_-]{20,}\b"),
    "GitHub token": re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{25,}|github_pat_[A-Za-z0-9_]{30,})\b"),
    "cloud access key": re.compile(r"\b(?:AKIA[A-Z0-9]{16}|LTAI[A-Za-z0-9]{16,})\b"),
}
PERSONAL_PATH = re.compile(re.escape("/" + "Users" + "/") + r"[^/\s]+/")
BLOCKED_PARTS = {"work", "outputs", ".build", "DerivedData", "private-data", "recordings", "meetings"}
BLOCKED_SUFFIXES = {".app", ".zip", ".dmg", ".pcm", ".wav", ".mp3", ".m4a", ".mp4", ".mov", ".key", ".pem", ".p12", ".pfx", ".keychain", ".keychain-db", ".sqlite", ".db"}

def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args])

def audit(staged):
    raw = git("diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z") if staged else git("ls-files", "-z")
    names = [p.decode("utf-8") for p in raw.split(b"\0") if p]
    if not names:
        print("No files selected for audit; nothing inspected.")
        return 0
    errors = []
    for name in names:
        path = pathlib.PurePosixPath(name)
        if any(p in BLOCKED_PARTS or p.endswith(".app") for p in path.parts) or path.suffix.lower() in BLOCKED_SUFFIXES or path.name == "meeting.json" or path.name.startswith("audio-") or (path.name.startswith(".env") and not path.name.endswith(".example")):
            errors.append((name, 0, "local data, credentials or build artifact"))
            continue
        data = git("show", ":" + name) if staged else (ROOT / name).read_bytes()
        if path.suffix.lower() == ".png":
            pos = 8
            while pos + 12 <= len(data):
                length = struct.unpack(">I", data[pos:pos + 4])[0]
                kind = data[pos + 4:pos + 8]
                if kind in {b"eXIf", b"tEXt", b"iTXt", b"zTXt"}:
                    errors.append((name, 0, "unreviewed image metadata"))
                pos += length + 12
            continue
        if path.suffix.lower() == ".icns":
            continue
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            errors.append((name, 0, "unreviewed binary file"))
            continue
        for number, line in enumerate(text.splitlines(), 1):
            for label, pattern in RULES.items():
                if pattern.search(line):
                    errors.append((name, number, label))
            if PERSONAL_PATH.search(line):
                errors.append((name, number, "personal absolute path"))
    for name, number, reason in errors:
        print(f"BLOCKED {name}:{number}: {reason}", file=sys.stderr)
    if errors:
        print("Audit failed. Matched values were not printed.", file=sys.stderr)
        return 1
    print(f"Publish audit passed: {len(names)} files; no detected credentials, personal paths or meeting artifacts.")
    return 0

def main():
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--staged", action="store_true")
    mode.add_argument("--tracked", action="store_true")
    args = parser.parse_args()
    return audit(args.staged)

if __name__ == "__main__":
    raise SystemExit(main())
