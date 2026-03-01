from __future__ import annotations

import os
import shlex
import subprocess
import shutil
import time
from dataclasses import dataclass
from typing import Iterable, Optional, Sequence, Tuple, Dict, Any

@dataclass
class CmdResult:
    argv: Sequence[str]
    rc: int
    out: str
    err: str
    runtime_s: float

import subprocess, time

def run_cmd(argv, timeout_s=10):
    import subprocess, time

    t0 = time.time()

    try:
        p = subprocess.run(
            argv,
            capture_output=True,
            timeout=timeout_s,
            text=True   # <-- forces stdout/stderr to be str
        )
        return CmdResult(
            argv=argv,
            rc=p.returncode,
            out=p.stdout or "",
            err=p.stderr or "",
            runtime_s=time.time() - t0,
        )

    except subprocess.TimeoutExpired as e:
        # IMPORTANT: normalize types
        out = e.stdout.decode(errors="ignore") if isinstance(e.stdout, bytes) else (e.stdout or "")
        err = e.stderr.decode(errors="ignore") if isinstance(e.stderr, bytes) else (e.stderr or "")

        return CmdResult(
            argv=argv,
            rc=124,
            out=out,
            err=err + "\n[timeout]",
            runtime_s=time.time() - t0,
        )


def shell_join(argv: Sequence[str]) -> str:
    return " ".join(shlex.quote(a) for a in argv)


def which(cmd):
    return shutil.which(cmd)
