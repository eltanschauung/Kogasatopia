CREATE TABLE IF NOT EXISTS resource_guard_incidents (
    incident_id CHAR(36) NOT NULL PRIMARY KEY,
    host_name VARCHAR(128) NOT NULL,
    occurred_at BIGINT UNSIGNED NOT NULL,
    event_name VARCHAR(64) NOT NULL,
    reasons VARCHAR(255) NOT NULL,
    sample_interval_seconds DOUBLE NOT NULL,
    consecutive_samples INT NOT NULL,
    cpu_pct DOUBLE NOT NULL,
    max_core_pct DOUBLE NOT NULL,
    memory_pct DOUBLE NOT NULL,
    iowait_pct DOUBLE NOT NULL,
    steal_pct DOUBLE NOT NULL,
    swap_pct DOUBLE NOT NULL,
    disk_pct DOUBLE NOT NULL,
    action VARCHAR(64) NOT NULL,
    action_detail VARCHAR(255) NOT NULL DEFAULT '',
    evidence_json LONGTEXT NOT NULL,
    created_at BIGINT UNSIGNED NOT NULL,
    updated_at BIGINT UNSIGNED NOT NULL,
    KEY idx_host_time (host_name, occurred_at),
    KEY idx_event_time (event_name, occurred_at),
    KEY idx_action_time (action, occurred_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS resource_guard_incident_processes (
    incident_id CHAR(36) NOT NULL,
    pid INT UNSIGNED NOT NULL,
    process_started_at DOUBLE NOT NULL,
    process_name VARCHAR(128) NOT NULL,
    systemd_unit VARCHAR(255) NOT NULL,
    cpu_pct DOUBLE NOT NULL,
    rss_bytes BIGINT UNSIGNED NOT NULL,
    read_bytes_per_second BIGINT UNSIGNED NULL,
    write_bytes_per_second BIGINT UNSIGNED NULL,
    threads INT UNSIGNED NOT NULL,
    PRIMARY KEY (incident_id, pid),
    KEY idx_process_name (process_name),
    CONSTRAINT fk_resource_guard_incident FOREIGN KEY (incident_id)
        REFERENCES resource_guard_incidents (incident_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
