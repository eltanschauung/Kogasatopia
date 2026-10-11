#!/usr/bin/env python3
"""Summarize identity-free private trial output. Does not read server logs."""
import argparse
import json
from pathlib import Path
import statistics

def fields(line):
    parts = line.rstrip().split("|")
    return parts[0], dict(p.split("=", 1) for p in parts[1:] if "=" in p)

def summarize(path):
    start, summary, domains, samples, slow, coverage = {}, {}, {}, [], [], []
    for line in Path(path).read_text().splitlines():
        kind, values = fields(line)
        if kind == "start": start = values
        elif kind == "domains": domains = values
        elif kind == "coverage": coverage.append(values)
        elif kind == "summary": summary = values
        elif kind == "sample": samples.append(values)
        elif kind == "slow_frame": slow.append(values)
    if not summary: raise ValueError("Trial has not finished")
    return {"file": Path(path).name, "settings": start, "domains": domains, "summary": summary,
            "coverage": {k: {"min": min((int(s[k]) for s in coverage), default=0),
                              "max": max((int(s[k]) for s in coverage), default=0)}
                         for k in ("equipped_custom_weapons", "equipped_custom_hats")},
            "sample_rate_min": min((float(s["rate"]) for s in samples), default=0),
            "sample_rate_median": statistics.median([float(s["rate"]) for s in samples]) if samples else 0,
            "native_totals_ms": {k: round(sum(float(s[k]) for s in samples), 3)
                                 for k in ("native_total", "native_engine", "native_policy", "native_resolver", "native_sp")},
            "native_peaks_ms": {k: max((float(s[k]) for s in samples), default=0)
                                 for k in ("peak_total", "peak_engine", "peak_policy", "peak_resolver", "peak_sp")},
            "worst_frames": sorted(slow, key=lambda r: float(r["ms"]), reverse=True)[:10]}

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", nargs="+")
    args = parser.parse_args()
    print(json.dumps([summarize(path) for path in args.files], indent=2))
