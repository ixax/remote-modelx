"""Detects the CPU quota actually granted to this container.

torch.set_num_threads()/set_num_interop_threads() (see model.py's
load_model() docstring) need this container's cgroup `cpus:` quota, not
os.cpu_count() (the host's core count) -- left to that default, torch
oversubscribes past what docker-compose.yml grants and thread contention
eats the speedup that quota was raised for. Reading it straight from
cgroups here means docker-compose.yml's `cpus:` limit has exactly one
place it's set, instead of a second, easy-to-forget copy in a
RERANKER_NUM_THREADS env var.
"""

from __future__ import annotations

import math
import os
from pathlib import Path

_CGROUP_V2_MAX = Path("/sys/fs/cgroup/cpu.max")
_CGROUP_V1_QUOTA = Path("/sys/fs/cgroup/cpu/cpu.cfs_quota_us")
_CGROUP_V1_PERIOD = Path("/sys/fs/cgroup/cpu/cpu.cfs_period_us")


def detect_num_threads() -> int:
    quota_and_period = _read_cgroup_v2() or _read_cgroup_v1()
    if quota_and_period is None:
        # No quota set (bare metal, or a `cpus:` limit wasn't applied) --
        # fall back to the host's core count, torch's own default.
        return os.cpu_count() or 1
    quota, period = quota_and_period
    return max(1, math.ceil(quota / period))


def _read_cgroup_v2() -> tuple[int, int] | None:
    if not _CGROUP_V2_MAX.exists():
        return None
    quota_str, period_str = _CGROUP_V2_MAX.read_text().split()
    if quota_str == "max":
        return None
    return int(quota_str), int(period_str)


def _read_cgroup_v1() -> tuple[int, int] | None:
    if not (_CGROUP_V1_QUOTA.exists() and _CGROUP_V1_PERIOD.exists()):
        return None
    quota = int(_CGROUP_V1_QUOTA.read_text())
    if quota <= 0:
        return None
    return quota, int(_CGROUP_V1_PERIOD.read_text())
