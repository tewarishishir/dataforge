"""Incident cumulative metrics.

Same metrics and grains as the daily pipeline, but counting every event up to
and including SNAPSHOT_DATE rather than only those on it. The only difference
from the daily file is the comparison operator, which is why the two are kept
structurally identical: a reviewer can diff them.

Globals are injected by common/cumulative_runner.py.
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
INSERT INTO {TARGET_CATALOG}.Incident_{grain}_Metrics_Snapshot_Cumulative
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
  AND CAST({event_column} AS DATE) <= DATE '{SNAPSHOT_DATE}'
GROUP BY {key_list}
"""
        )
