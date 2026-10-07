"""vm_pool.py -- thin wrapper over the `vagrant` CLI for the test-VM fleet.

The Vagrantfile lives in __automata/vagrant and defines machines test1..testN
on the Hyper-V provider. This module is what inbox_pump.py uses to bring workers
up, check liveness, and reset them to a clean snapshot after a crash.
"""
from __future__ import annotations
import os
import subprocess
from pathlib import Path

_VAGRANT_DIR = Path(__file__).resolve().parents[1] / "vagrant"
_VAGRANT_EXE = os.environ.get("VAGRANT_EXE", r"C:\Program Files\Vagrant\bin\vagrant.exe")


def _run(args: list[str], timeout: int = 1800) -> subprocess.CompletedProcess:
    env = dict(os.environ, VAGRANT_DEFAULT_PROVIDER="hyperv")
    return subprocess.run(
        [_VAGRANT_EXE, *args],
        cwd=str(_VAGRANT_DIR), env=env,
        capture_output=True, text=True, timeout=timeout,
    )


def status(name: str) -> str:
    """vagrant machine state: running / poweroff / not_created / aborted ..."""
    cp = _run(["status", name], timeout=120)
    for line in cp.stdout.splitlines():
        if line.strip().startswith(name):
            # e.g. "test1  running (hyperv)"
            rest = line.split(name, 1)[1].strip()
            return rest.split()[0] if rest else "unknown"
    return "unknown"


def is_alive(name: str) -> bool:
    return status(name) == "running"


def up(name: str, timeout: int = 1800) -> bool:
    return _run(["up", name], timeout=timeout).returncode == 0


def halt(name: str, timeout: int = 300) -> bool:
    return _run(["halt", name], timeout=timeout).returncode == 0


def snapshot_save(name: str, snap: str = "clean", timeout: int = 600) -> bool:
    return _run(["snapshot", "save", name, snap, "--force"], timeout=timeout).returncode == 0


def snapshot_restore(name: str, snap: str = "clean", timeout: int = 600) -> bool:
    """Hard reset a worker to its clean baseline (after a crash / periodically)."""
    return _run(["snapshot", "restore", name, snap, "--no-provision"], timeout=timeout).returncode == 0


def worker_names(count: int) -> list[str]:
    return [f"test{i}" for i in range(1, count + 1)]
