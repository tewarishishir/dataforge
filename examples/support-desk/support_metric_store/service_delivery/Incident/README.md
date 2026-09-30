# Incident

Incident lifecycle metrics for the service delivery domain.

## Metrics

| Metric | Grains | Cadences | Source |
| --- | --- | --- | --- |
| `total_incident_create_count` | account, workspace, user | Daily, Cumulative | `incidents.created_at` |
| `total_incident_resolve_count` | account, workspace, user | Daily, Cumulative | `incidents.closed_at` |

Soft-deleted rows (`is_deleted = true`) are excluded from every metric.

An incident counts as resolved when `closed_at` is set. In the source,
`closed_at` is populated exactly for incidents whose `status` is `resolved`, so
the metric reads the timestamp rather than the status label.

`Code/__incident_test.sql` reconciles both metrics against the source. Every
query returns only violating rows, so an empty result is a pass.

## Development history

| Date | Change | Issue |
| --- | --- | --- |
| 2026-09-29 | Initial build: create and resolve counts at three grains | #3 |
