#!/usr/bin/env python3
import os
import json
import time
import socket
import webbrowser
from pathlib import Path
from collections import defaultdict

ROOT = Path(__file__).parent

CURRENT = ROOT / "current"
REPORT  = ROOT / "report"
BASELINE = ROOT / "baseline"

OUT_JSON = REPORT / "summary.json"
OUT_TXT  = REPORT / "summary.txt"
OUT_HTML = REPORT / "index.html"

TS = time.strftime("%Y-%m-%d %H:%M:%S")
HOST = socket.gethostname()

EXTS = (".txt", ".json", ".log")

def classify(name: str) -> str:
  n = name.lower()

  if any(k in n for k in ["net", "dns", "route", "port"]):
    return "network"
  if any(k in n for k in ["proc", "ps", "top"]):
    return "process"
  if any(k in n for k in ["launch", "persist", "cron", "login"]):
    return "persistence"
  if any(k in n for k in ["ext", "kext", "sip"]):
    return "system"
  if any(k in n for k in ["trust", "sign", "code"]):
    return "trust"
  return "other"

def gather_files():
  buckets = defaultdict(list)

  for base in [CURRENT, REPORT]:
    if not base.exists():
      continue

    for f in base.rglob("*"):
      if f.suffix.lower() in EXTS and f.is_file():
        rel = f.relative_to(ROOT)
        cat = classify(f.name)
        buckets[cat].append(str(rel))

  return buckets

def build_summary(buckets):
  total = sum(len(v) for v in buckets.values())

  return {
    "timestamp": TS,
    "host": HOST,
    "total_files": total,
    "categories": buckets
  }

def write_json(summary):
  OUT_JSON.write_text(json.dumps(summary, indent=2))

def write_txt(summary):
  lines = []
  lines.append("audit snapshot")
  lines.append("----------------")
  lines.append(f"time: {summary['timestamp']}")
  lines.append(f"host: {summary['host']}")
  lines.append("")
  lines.append("counts:")

  for k, v in summary["categories"].items():
    lines.append(f"  {k:12} {len(v)}")

  OUT_TXT.write_text("\n".join(lines))

def write_html(summary):
  sections = []

  for cat, files in sorted(summary["categories"].items()):
    if not files:
      continue

    items = "\n".join(
      f'<li><a href="../{f}">{Path(f).name}</a></li>'
      for f in sorted(files)
    )

    sections.append(f"""
<h3>{cat}</h3>
<ul>
{items}
</ul>
""")

  html = f"""
<html>
<head>
  <title>audit summary</title>
  <style>
  body {{
    font-family: monospace;
    background: #111;
    color: #ddd;
    padding: 30px;
  }}
  a {{ color: #9cc; text-decoration: none; }}
  h2 {{ color: #a8c; }}
  h3 {{ color: #8ab; }}
  </style>
</head>
<body>

<h2>audit snapshot</h2>

<p>
host: {summary['host']}<br>
time: {summary['timestamp']}<br>
files indexed: {summary['total_files']}
</p>

{"".join(sections)}

</body>
</html>
"""
  OUT_HTML.write_text(html)

def open_browser():
  webbrowser.open(f"file://{OUT_HTML.resolve()}")

def console(summary):
  print("\naudit summary")
  print("-------------")
  print(f"host: {summary['host']}")
  print(f"time: {summary['timestamp']}\n")

  for k, v in summary["categories"].items():
    print(f"{k:12} {len(v)}")

  print(f"\ndashboard: {OUT_HTML}\n")

def main():
  buckets = gather_files()
  summary = build_summary(buckets)

  write_json(summary)
  write_txt(summary)
  write_html(summary)

  console(summary)
  open_browser()

if __name__ == "__main__":
  main()
