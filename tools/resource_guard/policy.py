from dataclasses import dataclass


@dataclass(frozen=True)
class Decision:
    reasons: tuple[str, ...]
    stop_mge: bool


class Policy:
    """Diagnostic triggers never independently authorize a server stop."""

    def __init__(self, breaches=2, cooldown=300, last_stop=0):
        self.breaches = breaches
        self.cooldown = cooldown
        self.last_stop = last_stop
        self.last_incident = 0
        self.counts = {}
        self.thresholds = {
            "cpu_pct": 95.0, "memory_pct": 95.0,
            "max_core_pct": 98.0, "iowait_pct": 20.0, "steal_pct": 10.0,
        }

    def evaluate(self, sample):
        for key, threshold in self.thresholds.items():
            self.counts[key] = self.counts.get(key, 0) + 1 if sample[key] >= threshold else 0
        ready = tuple(key for key in self.thresholds if self.counts[key] >= self.breaches)
        # Preserve the old "CPU OR RAM" consecutive-breach policy, even if
        # one sample is high CPU and the next sample is high RAM.
        critical = sample["cpu_pct"] >= 95 or sample["memory_pct"] >= 95
        self.counts["critical"] = self.counts.get("critical", 0) + 1 if critical else 0
        stop = (self.counts["critical"] >= self.breaches
                and sample["occurred_at"] - self.last_stop >= self.cooldown)
        if stop and not any(key in ready for key in ("cpu_pct", "memory_pct")):
            ready += ("cpu_or_memory_pct",)
        if not ready:
            self.last_incident = 0
            return None
        if not stop and sample["occurred_at"] - self.last_incident < self.cooldown:
            return None
        self.last_incident = sample["occurred_at"]
        if stop:
            self.last_stop = sample["occurred_at"]
        return Decision(ready, stop)
