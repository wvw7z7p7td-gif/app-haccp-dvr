#!/usr/bin/env python3
"""Converte l'output di `flutter analyze` in annotazioni GitHub.

GitHub mostra al massimo ~10 annotazioni per livello e per passo, quindi:
 - errori e warning: un'annotazione per riga (con file e riga);
 - tutto l'elenco (info compresi): una sola annotazione di riepilogo.
"""
import re
import sys

LINE = re.compile(r"^\s*(error|warning|info)\s+[•-]\s+(.*?)\s+[•-]\s+(\S+?):(\d+):(\d+)\s+[•-]\s+(\S+)\s*$")


def esc(s: str) -> str:
    return s.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def main(path: str) -> None:
    items = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for raw in f:
            m = LINE.match(raw.rstrip("\n"))
            if m:
                items.append(m.groups())

    counts = {"error": 0, "warning": 0, "info": 0}
    for level, msg, file, line, col, rule in items:
        counts[level] += 1
        if level in ("error", "warning"):
            print(f"::{level} file={file},line={line},col={col},title={rule}::{esc(msg)}")

    summary = "\n".join(f"{lv}\t{file}:{line}\t{rule}\t{msg[:90]}"
                        for lv, msg, file, line, col, rule in items)
    title = f"flutter analyze: {counts['error']} errori, {counts['warning']} warning, {counts['info']} info"
    level = "error" if counts["error"] else ("warning" if counts["warning"] else "notice")
    if not items:
        summary = "Nessuna segnalazione."
    print(f"::{level} title={title}::{esc(summary)[:60000]}")


if __name__ == "__main__":
    main(sys.argv[1])
