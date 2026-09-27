import os
import time
from pathlib import Path

import psutil


def rate(current, previous, elapsed):
    if previous is None or elapsed <= 0:
        return 0.0
    return max(0.0, current - previous) / elapsed


def busy(times):
    # Keep scheduler wait and hypervisor steal distinct from actual CPU work.
    return max(0.0, 100.0 - times.idle
               - getattr(times, "iowait", 0.0) - getattr(times, "steal", 0.0))


def pressure():
    result = {}
    for resource in ("cpu", "memory", "io"):
        try:
            for line in Path(f"/proc/pressure/{resource}").read_text().splitlines():
                parts = line.split()
                result[f"{resource}_{parts[0]}"] = float(
                    next(value.split("=")[1] for value in parts[1:] if value.startswith("avg10=")))
        except (OSError, ValueError, StopIteration):
            continue
    return result


def unit_for(pid):
    try:
        components = Path(f"/proc/{pid}/cgroup").read_text().replace("\n", "/").split("/")
        return next((part for part in reversed(components) if part.endswith(".service")), "")
    except OSError:
        return ""


class Collector:
    def __init__(self):
        self.previous = {}
        self.last_monotonic = time.monotonic()
        self.last_disk = psutil.disk_io_counters()
        self.last_net = psutil.net_io_counters()
        psutil.cpu_times_percent(interval=None)
        psutil.cpu_times_percent(interval=None, percpu=True)
        self.processes(1.0)  # Prime per-process counters, including existing servers.

    def processes(self, elapsed):
        current, rows = {}, []
        for proc in psutil.process_iter():
            try:
                with proc.oneshot():
                    started = proc.create_time()
                    cpu = proc.cpu_times()
                    rss = proc.memory_info().rss
                    name, threads = proc.name(), proc.num_threads()
                    try:
                        io = proc.io_counters()
                        reads, writes = io.read_bytes, io.write_bytes
                    except (psutil.AccessDenied, AttributeError):
                        reads = writes = None
                key = (proc.pid, started)
                total = cpu.user + cpu.system
                previous = self.previous.get(key)
                current[key] = (total, reads, writes)
                rows.append({
                    "pid": proc.pid, "started_at": started, "name": name,
                    "unit": unit_for(proc.pid), "threads": threads, "rss_bytes": rss,
                    "cpu_pct": round(100 * rate(total, previous[0] if previous else None, elapsed), 2),
                    "read_bps": (round(rate(reads, previous[1] if previous else None, elapsed))
                                 if reads is not None else None),
                    "write_bps": (round(rate(writes, previous[2] if previous else None, elapsed))
                                  if writes is not None else None),
                })
            except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                continue
        self.previous = current
        # Union of top CPU, RAM, and I/O processes; no passwords or command lines.
        selected = {}
        for score in (lambda row: row["cpu_pct"], lambda row: row["rss_bytes"],
                      lambda row: (row["read_bps"] or 0) + (row["write_bps"] or 0)):
            for row in sorted(rows, key=score, reverse=True)[:10]:
                selected[(row["pid"], row["started_at"])] = row
        return list(selected.values())

    def sample(self):
        now = time.monotonic()
        elapsed = now - self.last_monotonic
        self.last_monotonic = now
        cpu = psutil.cpu_times_percent(interval=None)
        cores = psutil.cpu_times_percent(interval=None, percpu=True)
        mem, swap = psutil.virtual_memory(), psutil.swap_memory()
        disk, net = psutil.disk_io_counters(), psutil.net_io_counters()
        row = {
            "occurred_at": int(time.time()), "interval_seconds": round(elapsed, 3),
            "cpu_pct": round(busy(cpu), 2),
            "max_core_pct": round(max((busy(core) for core in cores), default=0), 2),
            "iowait_pct": cpu.iowait, "steal_pct": cpu.steal,
            "memory_pct": mem.percent, "memory_available_bytes": mem.available,
            "swap_pct": swap.percent, "disk_pct": psutil.disk_usage("/").percent,
            "load": list(os.getloadavg()), "pressure": pressure(),
            "disk_read_bps": round(rate(disk.read_bytes, self.last_disk.read_bytes, elapsed)) if disk and self.last_disk else None,
            "disk_write_bps": round(rate(disk.write_bytes, self.last_disk.write_bytes, elapsed)) if disk and self.last_disk else None,
            "net_recv_bps": round(rate(net.bytes_recv, self.last_net.bytes_recv, elapsed)),
            "net_sent_bps": round(rate(net.bytes_sent, self.last_net.bytes_sent, elapsed)),
        }
        self.last_disk, self.last_net = disk, net
        return row, self.processes(elapsed)
