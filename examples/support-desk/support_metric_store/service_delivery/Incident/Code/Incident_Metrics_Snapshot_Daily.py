"""Incident daily metrics.

Counts incident lifecycle events that occurred on SNAPSHOT_DATE, at three grains.
Every metric column follows total_{entity}_{verb}_count.

An incident is resolved when closed_at is set. In the source, closed_at is
populated exactly for incidents whose status is 'resolved', so the metric reads
the timestamp rather than filtering on the status label.

Globals (SOURCE_ZONE, SNAPSHOT_DATE, SOURCE_CATALOG, TARGET_CATALOG, CADENCE)
are injected by common/daily_runner.py.
"""

GRAIN_KEYS = {
    "Account": ["account_id"],
    "Workspace": ["account_id", "workspace_id"],
    "User": ["account_id", "user_id"],
}

METRICS = {
    "total_incident_create_count": "created_at",
    "total_incident_resolve_count": "closed_at",
}

STATEMENTS = []

for grain, keys in GRAIN_KEYS.items():
    key_list = ", ".join(keys)
    for metric, event_column in METRICS.items():
        STATEMENTS.append(
            f"""
INSERT INTO {TARGET_CATALOG}.Incident_{grain}_Metrics_Snapshot_Daily
SELECT
    DATE '{SNAPSHOT_DATE}' AS SNAPSHOT_DATE,
    {key_list},
    '{metric}' AS metric_name,
    COUNT(DISTINCT incident_id) AS metric_value,
    now() AS LOAD_TIMESTAMP,
    '{SOURCE_ZONE}' AS SOURCE_ZONE
FROM {SOURCE_CATALOG}.incidents
WHERE is_deleted = false
  AND {event_column} IS NOT NULL
  AND CAST({event_column} AS DATE) = DATE '{SNAPSHOT_DATE}'
GROUP BY {key_list}
"""
        )
