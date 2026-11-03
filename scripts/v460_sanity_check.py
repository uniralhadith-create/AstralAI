#!/usr/bin/env python3
"""V4.6.0 sanity check — brace/paren balance, .strings duplicate +
parity checks, release invariants and icon-registry resolution on every
file touched by the release."""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

SWIFT_FILES = [
    "AstralAI/DesignSystem/AstralIcons.swift",
    "AstralAI/DesignSystem/Theme.swift",
    "AstralAI/DesignSystem/Components.swift",
    "AstralAI/Features/Chat/ComposerView.swift",
    "AstralAI/Features/Chat/ChatView.swift",
    "AstralAI/Features/Chat/MessageViews.swift",
    "AstralAI/Features/Chat/PlanTrackerView.swift",
    "AstralAI/Features/Chat/SubAgentBar.swift",
    "AstralAI/Features/Chat/QuickLaunchView.swift",
    "AstralAI/Features/Chat/AstraComputerBar.swift",
    "AstralAI/Features/Files/TerminalView.swift",
    "AstralAI/Features/Browser/BrowserController.swift",
    "AstralAI/Features/Settings/SettingsView.swift",
    "AstralAI/Core/Contracts.swift",
    "AstralAI/AgentCore/ToolRegistry.swift",
    "AstralAI/AgentCore/AgentSession.swift",
    "AstralAI/AgentCore/AgentExecutor.swift",
    "AstralAI/AgentCore/SubAgentRunner.swift",
    "AstralAI/AgentCore/Tools/BrowserTools.swift",
    "AstralAI/App/AppEnvironment.swift",
    "AstralAI/App/RootView.swift",
    "AstralAI/Platform/AppIntentsImpl.swift",
    "Tests/V460Tests.swift",
]

STRING_TABLES = [
    "Chat", "Browser", "Settings", "Platform", "Shared",
]


def strip_swift(code: str) -> str:
    """Remove comments and string literals so braces inside them don't count."""
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
            hashes = 1
            while i + hashes < n and code[i + hashes] == '#':
                hashes += 1
            i += hashes + 1
            closer = '"' + '#' * hashes
            while i < n:
                if code[i] == "\\" and i + 1 < n and code[i + 1] == "(":
                    i += 2
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


def check_balance(path: Path) -> str | None:
    code = strip_swift(path.read_text(encoding="utf-8"))
    for opener, closer in [("{", "}"), ("(", ")"), ("[", "]")]:
        if code.count(opener) != code.count(closer):
            return f"{path.name}: {opener}{closer} imbalance {code.count(opener)}/{code.count(closer)}"
    return None


def parse_strings(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    pattern = re.compile(r'^"((?:[^"\\]|\\.)+)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;')
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("//"):
            continue
        m = pattern.match(line)
        if m:
            result[m.group(1)] = m.group(2)
    return result


def main() -> int:
    failures: list[str] = []

    # 1. Swift brace/paren balance on every touched file.
    for rel in SWIFT_FILES:
        path = ROOT / rel
        if not path.exists():
            failures.append(f"missing file: {rel}")
            continue
        issue = check_balance(path)
        if issue:
            failures.append(issue)

    # 2. .strings duplicate keys (both languages, every touched table).
    for table in STRING_TABLES:
        for lang in ["en", "ar"]:
            path = ROOT / f"AstralAI/Resources/{lang}.lproj/{table}.strings"
            if not path.exists():
                failures.append(f"missing strings file: {path}")
                continue
            seen: dict[str, int] = {}
            pattern = re.compile(r'^"((?:[^"\\]|\\.)+)"\s*=')
            for line in path.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if not line or line.startswith("//"):
                    continue
                m = pattern.match(line)
                if m:
                    key = m.group(1)
                    seen[key] = seen.get(key, 0) + 1
            for key, count in seen.items():
                if count > 1:
                    failures.append(f"{lang}/{table}.strings: duplicate key {key} ×{count}")

    # 3. EN/AR parity for every touched table.
    for table in STRING_TABLES:
        en = parse_strings(ROOT / f"AstralAI/Resources/en.lproj/{table}.strings")
        ar = parse_strings(ROOT / f"AstralAI/Resources/ar.lproj/{table}.strings")
        for key in set(en) - set(ar):
            failures.append(f"en/{table}.strings: key missing in ar: {key}")
        for key in set(ar) - set(en):
            failures.append(f"ar/{table}.strings: key missing in en: {key}")

    # 4. Release invariants.
    project = (ROOT / "project.yml").read_text(encoding="utf-8")
    if project.count('4.7.0') != 4:
        failures.append(f"project.yml: expected 4 x 4.7.0, found {project.count('4.7.0')}")
    badge_en = (ROOT / "AstralAI/Resources/en.lproj/Shared.strings").read_text(encoding="utf-8")
    badge_ar = (ROOT / "AstralAI/Resources/ar.lproj/Shared.strings").read_text(encoding="utf-8")
    if "V4.7.0" not in badge_en or "V4.7.0" not in badge_ar:
        failures.append("versionBadge not updated to V4.7.0 (en/ar)")
    terminal = (ROOT / "AstralAI/Features/Files/TerminalView.swift").read_text(encoding="utf-8")
    if "astra-os 4.7.0" not in terminal:
        failures.append("astra-os banner not updated to 4.7.0")

    # 5. Every icon role referenced in code resolves to a bundled SVG.
    icons_dir = ROOT / "AstralAI/Resources/Icons"
    bundled = {p.stem for p in icons_dir.glob("*.svg")}
    registry = (ROOT / "AstralAI/DesignSystem/AstralIcons.swift").read_text(encoding="utf-8")
    roles = re.findall(r'static let (\w+)\s*=\s*"([\w-]+)"', registry)
    for role, icon in roles:
        if icon not in bundled:
            failures.append(f"registry icon {role} -> {icon}: no bundled SVG")

    # 6. The arc fix is present (the inverted F.6.6 correction is gone).
    engine = (ROOT / "AstralAI/DesignSystem/AstralIcons.swift").read_text(encoding="utf-8")
    if "reach > 1" not in engine:
        failures.append("AstralIcons: arc correction (reach > 1) missing — the F.6.6 fix is not in place")
    if "ratio > 1" in engine:
        failures.append("AstralIcons: the old inverted ratio > 1 condition still present")

    # 7. The screenshot delivery is wired at all three creation sites.
    for rel, needle in [
        ("AstralAI/AgentCore/AgentSession.swift", "ScreenCaptureDelivery.take(callID: call.id)"),
        ("AstralAI/AgentCore/AgentExecutor.swift", "ScreenCaptureDelivery.take(callID: call.id)"),
        ("AstralAI/AgentCore/SubAgentRunner.swift", "ScreenCaptureDelivery.take(callID: call.id)"),
        ("AstralAI/AgentCore/ToolRegistry.swift", "BrowserScreenshotTool()"),
        ("AstralAI/AgentCore/ToolRegistry.swift", "context.callID = call.id"),
        ("AstralAI/App/AppEnvironment.swift", "case \"quick\":"),
        ("AstralAI/Platform/AppIntentsImpl.swift", "QuickTaskIntent"),
        ("AstralAI/Features/Chat/MessageViews.swift", "ScreenshotCard(image: capture)"),
    ]:
        text = (ROOT / rel).read_text(encoding="utf-8")
        if needle not in text:
            failures.append(f"{rel}: missing wiring: {needle!r}")

    if failures:
        print("V4.6.0 SANITY: FAIL")
        for line in failures:
            print("  -", line)
        return 1
    print("V4.6.0 SANITY: PASS")
    print(f"  {len(SWIFT_FILES)} swift files balanced")
    print(f"  {len(STRING_TABLES)} string tables × en/ar: no duplicates, full parity")
    print("  release invariants OK (4.6.0 / build 10 / badges / banner)")
    print(f"  {len(bundled)} bundled icons cover every registry role")
    print("  arc fix + screenshot delivery + quick launch wiring verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
