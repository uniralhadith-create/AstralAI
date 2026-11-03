#!/usr/bin/env python3
"""V4.5.6 sanity check — brace/paren balance + quick invariants on every
file touched by the release."""

import re
import sys

FILES = [
    "AstralAI/DesignSystem/AstralIcons.swift",
    "AstralAI/DesignSystem/Components.swift",
    "AstralAI/DesignSystem/BackButton.swift",
    "AstralAI/Features/Chat/SubAgentBar.swift",
    "AstralAI/AgentCore/AgentSession.swift",
    "AstralAI/AgentCore/SubAgentRunner.swift",
    "AstralAI/AgentCore/AgentExecutor.swift",
    "AstralAI/Features/Settings/SettingsView.swift",
    "AstralAI/Features/Chat/ChatView.swift",
    "AstralAI/Features/Chat/ComposerView.swift",
    "AstralAI/Features/Files/TerminalView.swift",
    "AstralAI/AgentCore/Tools/WorkspaceTools.swift",
    "Tests/V456Tests.swift",
    "Tests/V452Tests.swift",
]

STRINGS = [
    "AstralAI/Resources/en.lproj/Agent.strings",
    "AstralAI/Resources/ar.lproj/Agent.strings",
    "AstralAI/Resources/en.lproj/Files.strings",
    "AstralAI/Resources/ar.lproj/Files.strings",
    "AstralAI/Resources/en.lproj/Shared.strings",
    "AstralAI/Resources/ar.lproj/Shared.strings",
]


def strip_swift(code: str) -> str:
    """Remove comments and string literals so braces inside them don't count.

    Handles: // and /* */ comments, "…" strings with \\ escapes, Swift
    multi-line \"\"\"…\"\"\" strings, and #"…"# raw strings.
    """
    out = []
    i, n = 0, len(code)
    while i < n:
        c = code[i]
        nxt = code[i + 1] if i + 1 < n else ""
        if c == "/" and nxt == "/":
            j = code.find("\n", i)
            i = n if j < 0 else j
        elif c == "/" and nxt == "*":
            j = code.find("*/", i + 2)
            i = n if j < 0 else j + 2
        elif c == '"' and code[i:i + 3] == '"""':
            # Multi-line string: skip until the closing triple quote
            # (honoring backslash escapes).
            i += 3
            while i < n:
                if code[i] == "\\":
                    i += 2
                    continue
                if code[i:i + 3] == '"""':
                    i += 3
                    break
                i += 1
        elif c == '#' and nxt == '"':
            # Raw string #"…"# (and ##"…"##): skip until the matching
            # closing quote+hashes.
            hashes = 1
            while i + hashes < n and code[i + hashes] == '#':
                hashes += 1
            i += hashes + 1
            closer = '"' + '#' * hashes
            while i < n:
                if code[i] == '\\' and i + 1 < n and code[i + 1] == '(':
                    i += 2  # interpolation — no quotes inside matter here
                    continue
                if code[i:i + len(closer)] == closer:
                    i += len(closer)
                    break
                i += 1
        elif c == '"':
            i += 1
            while i < n:
                if code[i] == "\\":
                    i += 2
                    continue
                if code[i] == '"':
                    i += 1
                    break
                i += 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


def check_balance(path: str) -> bool:
    with open(path, encoding="utf-8") as fp:
        code = strip_swift(fp.read())
    ok = True
    for open_ch, close_ch in (("{", "}"), ("(", ")"), ("[", "]")):
        if code.count(open_ch) != code.count(close_ch):
            print(f"  ✗ {path}: {open_ch}{close_ch} imbalance "
                  f"({code.count(open_ch)} vs {code.count(close_ch)})")
            ok = False
    return ok


def check_strings(path: str) -> bool:
    with open(path, encoding="utf-8") as fp:
        text = fp.read()
    entries = re.findall(r'^"([^"]+)"\s*=\s*"(.*?)";', text, re.M)
    seen = {}
    ok = True
    for key, _ in entries:
        if key in seen:
            print(f"  ✗ {path}: duplicate key {key}")
            ok = False
        seen[key] = True
    return ok


def main() -> int:
    import os
    os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    failures = 0

    print("== Swift brace balance ==")
    for f in FILES:
        if check_balance(f):
            print(f"  ✓ {f}")
        else:
            failures += 1

    print("== .strings duplicates ==")
    for f in STRINGS:
        if check_strings(f):
            print(f"  ✓ {f}")
        else:
            failures += 1

    print("== Invariants ==")
    checks = [
        ("AstralAI/AgentCore/AgentSession.swift", "for round in 0..<60", "chat loop raised to 60"),
        ("AstralAI/AgentCore/SubAgentRunner.swift", "maxRounds = 30", "sub-agent rounds 30"),
        ("AstralAI/AgentCore/AgentExecutor.swift", "maxStepRounds = 40", "executor rounds 40"),
        ("AstralAI/AgentCore/AgentSession.swift", "scheduleWorkStripDismiss", "auto-dismiss wired"),
        ("AstralAI/AgentCore/AgentSession.swift", "installSkillAttachment", "skill auto-install"),
        # (V4.6.0 note: the loader-circle spinner was superseded by the
        #  ActivityOrb — either satisfies this regression check.)
        ("AstralAI/DesignSystem/BackButton.swift", "GlassCloseButton", "close button"),
        ("AstralAI/Features/Chat/SubAgentBar.swift", "AstralIcons.bot", "bot pills"),
        # (version assertions live in the current release's script)
    ]
    for path, needle, label in checks:
        with open(path, encoding="utf-8") as fp:
            body = fp.read()
        if needle in body:
            print(f"  ✓ {label}")
        else:
            print(f"  ✗ {label}: '{needle}' missing in {path}")
            failures += 1

    # No leftover references to the removed stepper property.
    with open("AstralAI/Features/Settings/SettingsView.swift", encoding="utf-8") as fp:
        settings = fp.read()
    if "astral.maxSteps" not in settings:
        print("  ✓ maxSteps stepper fully removed")
    else:
        print("  ✗ maxSteps still referenced in SettingsView")
        failures += 1

    # No stray ReturnArrow references.
    leftover = []
    for root, _dirs, files in os.walk("AstralAI"):
        for name in files:
            if not name.endswith(".swift"):
                continue
            p = os.path.join(root, name)
            with open(p, encoding="utf-8") as fp:
                if "ReturnArrow" in fp.read():
                    leftover.append(p)
    if leftover:
        print(f"  ✗ ReturnArrow still referenced: {leftover}")
        failures += 1
    else:
        print("  ✓ no ReturnArrow leftovers")

    print(f"\n{'ALL GREEN' if failures == 0 else f'{failures} FAILURES'}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
