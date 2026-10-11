#!/usr/bin/env python3
"""Private, bounded perf flight recorder for CheckLag. Never signals TF2."""
import argparse
from collections import Counter
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import time

MARKER = "checklag-native-v1"
MAX_BYTES = 384 * 1024 * 1024
LINE = re.compile(r"\[checklag\.smx\] \[CheckLag\](?:\[(Frame|Host)\])? (v=3\|.*)$")
FIELDS = {
    "v", "alert_tick", "rate", "expected", "frame_peak_ms", "frame_tick", "humans",
    "entities", "snapshot_kind", "rank", "previous_tick", "frame_ms", "budget_ms",
    "age_ms", "same_tick_scope", "scope_ms", "call_seq", "outside_largest_ms",
    "host_seq", "window_ms", "thread_cpu_ms", "runnable_wait_ms", "major_faults",
    "minor_faults", "process_read_bytes", "process_write_bytes", "probe_ms", "flags",
}

def parse_line(line):
    match = LINE.search(line.rstrip())
    if not match:
        return None
    fields = dict(part.split("=", 1) for part in match[2].split("|") if "=" in part)
    if not fields.get("alert_tick", "").isdigit():
        return None
    return match[1] or "Alert", {k: v for k, v in fields.items() if k in FIELDS}

def identity(pid):
    proc = Path("/proc") / str(pid)
    if (proc / "comm").read_text().strip() != "srcds_linux":
        raise ValueError("Target is not a TF2 srcds_linux main thread")
    # Identity guard only. Never retain/print the command line or process fields.
    stat = (proc / "stat").read_text()
    return stat.rsplit(")", 1)[1].split()[19]

def private_directory(path):
    path = Path(path)
    if path.is_symlink():
        raise ValueError("Output must not be a symlink")
    path.mkdir(mode=0o700, parents=False, exist_ok=True)
    if path.stat().st_uid != os.geteuid() or path.stat().st_mode & 0o077:
        raise ValueError("Output must be owned by the recorder and mode 0700")
    if any(path.iterdir()):
        raise ValueError("Output must be an empty dedicated directory")
    return path.resolve()

def write_json(path, value):
    with path.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, indent=2)
        stream.write("\n")

def capture_pending(root, pending, sealed, owned, keep):
    """Copy already sealed segments only; all deletion targets were created here."""
    if not sealed:
        return
    for event in list(pending):
        if sealed[-1].stat().st_mtime_ns < event["observed_realtime_ns"]:
            continue
        # Last 20 seconds cover CheckLag's five-second history and sealing latency.
        selected = [p for p in sealed if p.stat().st_mtime_ns >= event["observed_realtime_ns"] - 20_000_000_000]
        if not selected:
            continue
        destination = root / ("alert-%d-%s" % (event["observed_realtime_ns"], event["alert"]["alert_tick"]))
        destination.mkdir(mode=0o700)
        segments = []
        for source in selected[-3:]:
            if source.is_symlink() or not source.is_file():
                raise ValueError("Unexpected perf segment")
            target = destination / source.name
            # Hardlink immutable sealed perf files: rolling retention only unlinks.
            os.link(source, target)
            segments.append(target.name)
        event["segments"] = segments
        event["format"] = MARKER
        event["timing_note"] = "Observed log time; frame timing approximate within polling/log-write latency"
        write_json(destination / "metadata.json", event)
        owned.append(destination)
        pending.remove(event)
        while len(owned) > keep:
            old = owned.pop(0)
            if old.parent != root or old.is_symlink() or not (old / "metadata.json").is_file():
                raise ValueError("Retention ownership guard failed")
            shutil.rmtree(old)
        print("Captured alert tick %s (%d private segments)" %
              (event["alert"]["alert_tick"], len(segments)), flush=True)

def record(args):
    if os.geteuid() != 0:
        raise ValueError("Run with sudo; kernel perf policy is left unchanged")
    if not 1 <= args.frequency <= 99 or not 1 <= args.keep <= 10 or not 1 <= args.hours <= 24:
        raise ValueError("Limits: frequency 1..99, retained alerts 1..10, hours 1..24")
    os.umask(0o077)
    root = private_directory(args.output)
    start_identity = identity(args.pid)
    rolling = root / "rolling"
    rolling.mkdir(mode=0o700)
    write_json(root / "recorder.json", {
        "format": MARKER, "pid": args.pid, "process_start_ticks": start_identity,
        "frequency_hz": args.frequency, "stack_bytes": 8192, "keep_alerts": args.keep,
        "start_realtime_ns": time.time_ns(), "start_monotonic_ns": time.monotonic_ns(),
        "duration_hours": args.hours, "max_unique_bytes": MAX_BYTES,
        "segment_seconds": 10, "note": "Small sampling gaps between perf processes",
    })
    environment = os.environ.copy()
    environment["DEBUGINFOD_URLS"] = ""
    streams, pending, owned, sealed = {}, [], [], []
    stopping, number = False, 0
    def stop(_signal, _frame):
        nonlocal stopping
        stopping = True
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    with (root / "perf-private.log").open("x") as perf_log:
        def start_segment(index):
            path = rolling / ("perf.data.%06d" % index)
            command = ["perf", "record", "-e", "cpu-clock:u", "-F", str(args.frequency),
                       "--call-graph", "dwarf,8192", "--clockid", "mono",
                       "--no-inherit", "--no-buildid-cache", "-m", "256",
                       "-o", str(path), "-t", str(args.pid), "--", "sleep", "10"]
            return subprocess.Popen(command, stdout=perf_log, stderr=perf_log, env=environment), path
        perf, current = start_segment(number)
        started = time.monotonic()
        try:
            while not stopping and time.monotonic() - started < args.hours * 3600:
                if identity(args.pid) != start_identity:
                    raise RuntimeError("TF2 process identity changed; refusing to follow a recycled PID")
                now = time.monotonic()
                for path in sorted(Path(args.log_dir).glob("L[0-9]*.log"))[-2:]:
                    if path not in streams:
                        stream = path.open(errors="replace")
                        if path.stat().st_mtime_ns < int((time.time() - (now - started)) * 1e9) or now - started < 1.0:
                            stream.seek(0, 2)
                        streams[path] = stream
                for path in list(streams):
                    if path not in sorted(streams)[-2:]:
                        streams.pop(path).close()
                for stream in streams.values():
                    for line in stream:
                        parsed = parse_line(line)
                        if parsed is None:
                            continue
                        kind, fields = parsed
                        if kind == "Alert":
                            if fields.get("snapshot_kind") == "manual":
                                continue
                            pending.append({"alert": fields, "frames": [], "hosts": [],
                                "observed_realtime_ns": time.time_ns(),
                                "observed_monotonic_ns": time.monotonic_ns()})
                            if len(pending) > 10:
                                raise RuntimeError("Pending alert limit reached")
                        else:
                            for event in reversed(pending):
                                if event["alert"]["alert_tick"] == fields["alert_tick"]:
                                    event["frames" if kind == "Frame" else "hosts"].append(fields)
                                    break
                if perf.poll() is not None:
                    if perf.returncode != 0:
                        raise RuntimeError("perf stopped (exit/signal %d); inspect private log" % perf.returncode)
                    sealed.append(current)
                    capture_pending(root, pending, sealed, owned, args.keep)
                    while len(sealed) > 6:
                        old = sealed.pop(0)
                        if old.parent != rolling or old.is_symlink():
                            raise ValueError("Rolling retention ownership guard failed")
                        old.unlink()
                    number += 1
                    perf, current = start_segment(number)
                files = [p for p in root.rglob("*") if p.is_file()]
                sizes = {(p.stat().st_dev, p.stat().st_ino): p.stat().st_size for p in files}
                if sum(sizes.values()) > MAX_BYTES:
                    raise RuntimeError("Private capture byte limit reached; recording stopped safely")
                time.sleep(0.1)
        finally:
            if perf.poll() is None:
                # Signal only our child perf process, never the TF2 target.
                perf.send_signal(signal.SIGINT)
                try:
                    perf.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    perf.kill()
                    perf.wait(timeout=5)
            if current.is_file() and current not in sealed:
                sealed.append(current)
            capture_pending(root, pending, sealed, owned, args.keep)
            for stream in streams.values():
                stream.close()

def sample_stacks(lines):
    """Parse symbol-only perf script output. Never expose raw stack bytes/registers."""
    timestamp, stack = None, []
    for line in lines:
        if not line.strip():
            if timestamp is not None:
                yield timestamp, tuple(stack)
            timestamp, stack = None, []
            continue
        header = re.search(r"\b([0-9]+\.[0-9]+):\s+\S+:", line)
        if header:
            if timestamp is not None:
                yield timestamp, tuple(stack)
            timestamp, stack = float(header[1]), []
        elif timestamp is not None and line[0].isspace():
            match = re.match(r"\s*(?:[0-9a-f]+\s+)?(.+?)\s+\((.+)\)\s*$", line.rstrip())
            if match:
                symbol = re.sub(r"\+0x[0-9a-f]+(?:/0x[0-9a-f]+)?$", "", match[1])
                symbol = re.sub(r"^(?:0x)?[0-9a-f]{8,}$", "[unknown]", symbol)
                stack.append(symbol + " (" + Path(match[2]).name + ")")
    if timestamp is not None:
        yield timestamp, tuple(stack)

def report(args):
    capture = Path(args.capture)
    metadata = json.loads((capture / "metadata.json").read_text())
    if metadata.get("format") != MARKER:
        raise ValueError("Not a CheckLag native capture")
    frame = next((f for f in metadata["frames"] if f.get("rank") == "1"), None)
    if frame is None:
        raise ValueError("No worst-frame timing; inspect capture metadata")
    end = metadata["observed_monotonic_ns"] / 1e9 - float(frame["age_ms"]) / 1000
    start = end - float(frame["frame_ms"]) / 1000
    counts = Counter()
    saw_stack = False
    environment = os.environ.copy()
    environment["DEBUGINFOD_URLS"] = ""
    if args.library_path:
        environment["LD_LIBRARY_PATH"] = args.library_path
    for name in metadata["segments"]:
        if Path(name).name != name:
            raise ValueError("Invalid segment path")
        # Debian's i386 perf --ns formatting is broken; microsecond precision is ample.
        command = [args.perf, "script", "-i", str(capture / name),
                   "-F", "comm,tid,time,event,ip,sym,dso"]
        with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                              text=True, env=environment) as process:
            for timestamp, stack in sample_stacks(process.stdout):
                # A leaf-only report is what unsupported compat unwinding yields.
                saw_stack = saw_stack or len(stack) > 1
                if start - 0.15 <= timestamp <= end + 0.15 and stack:
                    counts[stack[:32]] += 1
            if process.wait() != 0:
                raise RuntimeError("perf decoding failed; raw diagnostics withheld")
    if not saw_stack:
        raise RuntimeError("No unwound stacks: use a perf decoder matching the target architecture")
    print("Alert tick %s: frame %.3f ms; %d on-CPU samples in approximate frame window (+/-150 ms)." %
          (metadata["alert"]["alert_tick"], float(frame["frame_ms"]), sum(counts.values())))
    print("Statistical CPU evidence, not exact exclusive timing. Sleeping/blocked intervals have no CPU samples.")
    for stack, count in counts.most_common(min(max(args.top, 1), 20)):
        print("\n%d samples:\n  %s" % (count, "\n  <- ".join(stack)))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    recorder = commands.add_parser("record")
    recorder.add_argument("--pid", type=int, required=True)
    recorder.add_argument("--log-dir", required=True)
    recorder.add_argument("--output", required=True)
    recorder.add_argument("--frequency", type=int, default=99)
    recorder.add_argument("--keep", type=int, default=10)
    recorder.add_argument("--hours", type=float, default=24)
    reporter = commands.add_parser("report")
    reporter.add_argument("--capture", required=True)
    reporter.add_argument("--top", type=int, default=10)
    reporter.add_argument("--perf", default="perf", help="Matching-architecture perf decoder")
    reporter.add_argument("--library-path", help="Private decoder library directory")
    args = parser.parse_args()
    try:
        (record if args.command == "record" else report)(args)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        parser.exit(1, type(error).__name__ + ": " + str(error) + "\n")

if __name__ == "__main__":
    main()
