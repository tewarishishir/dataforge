-- Incident metric tests. Every query returns only violating rows, so an empty result is a pass.
-- Substitute {SOURCE_CATALOG} and {TARGET_CATALOG} before running, the same way the schema files are run.
-- Tests are scoped to the SNAPSHOT_DATEs actually loaded, so they can run after any backfill window.
-- No _update_count metrics exist for this entity, so no exclusions apply.

-- Test 1: Daily rollup. Account-grain totals equal a direct source count for every loaded date.
-- A day with no events writes no Daily rows, so loaded dates come from the Cumulative table,
-- which has rows for every date once any history exists. A missing Daily load shows up as actual 0.
WITH loaded_dates AS (
    SELECT DISTINCT
        SNAPSHOT_DATE
    FROM {TARGET_CATALOG}.Incident_Account_Metrics_Snapshot_Cumulative
)
, expected AS (
    SELECT
        d.SNAPSHOT_DATE
        ,m.metric_name
        ,COUNT(DISTINCT s.incident_id) AS expected_value
    FROM loaded_dates AS d
    CROSS JOIN (
        VALUES
            ('total_incident_create_count')
            ,('total_incident_resolve_count')
    ) AS m (metric_name)
    LEFT JOIN {SOURCE_CATALOG}.incidents AS s
        ON s.is_deleted = false
        AND CAST(
            CASE
                WHEN m.metric_name = 'total_incident_create_count'
                THEN s.created_at
                ELSE s.closed_at
            END AS DATE
        ) = d.SNAPSHOT_DATE
    GROUP BY ALL
)
, actual AS (
    SELECT
        SNAPSHOT_DATE
        ,metric_name
        ,SUM(metric_value) AS actual_value
    FROM {TARGET_CATALOG}.Incident_Account_Metrics_Snapshot_Daily
    GROUP BY ALL
)
SELECT
    'daily_rollup' AS test
    ,e.SNAPSHOT_DATE
    ,e.metric_name
    ,e.expected_value
    ,COALESCE(a.actual_value, 0) AS actual_value
FROM expected AS e
LEFT JOIN actual AS a
    ON a.SNAPSHOT_DATE = e.SNAPSHOT_DATE
    AND a.metric_name = e.metric_name
WHERE e.expected_value <> COALESCE(a.actual_value, 0)
ORDER BY 2, 3;

-- Test 2: Cumulative rollup. Account-grain totals equal a direct source count up to every loaded date.
WITH loaded_dates AS (
    SELECT DISTINCT
        SNAPSHOT_DATE
    FROM {TARGET_CATALOG}.Incident_Account_Metrics_Snapshot_Cumulative
)
, expected AS (
    SELECT
        d.SNAPSHOT_DATE
        ,m.metric_name
        ,COUNT(DISTINCT s.incident_id) AS expected_value
    FROM loaded_dates AS d
    CROSS JOIN (
        VALUES
            ('total_incident_create_count')
            ,('total_incident_resolve_count')
    ) AS m (metric_name)
    LEFT JOIN {SOURCE_CATALOG}.incidents AS s
        ON s.is_deleted = false
        AND CAST(
            CASE
                WHEN m.metric_name = 'total_incident_create_count'
                THEN s.created_at
                ELSE s.closed_at
            END AS DATE
        ) <= d.SNAPSHOT_DATE
    GROUP BY ALL
)
, actual AS (
    SELECT
        SNAPSHOT_DATE
        ,metric_name
        ,SUM(metric_value) AS actual_value
    FROM {TARGET_CATALOG}.Incident_Account_Metrics_Snapshot_Cumulative
    GROUP BY ALL
)
SELECT
    'cumulative_rollup' AS test
    ,e.SNAPSHOT_DATE
    ,e.metric_name
    ,e.expected_value
    ,COALESCE(a.actual_value, 0) AS actual_value
FROM expected AS e
LEFT JOIN actual AS a
    ON a.SNAPSHOT_DATE = e.SNAPSHOT_DATE
    AND a.metric_name = e.metric_name
WHERE e.expected_value <> COALESCE(a.actual_value, 0)
ORDER BY 2, 3;

-- Test 3: Grain consistency. Workspace and user totals equal account totals per date, metric, and cadence.
WITH grain_totals AS (
    SELECT 'Daily' AS cadence, 'account' AS grain, SNAPSHOT_DATE, metric_name, SUM(metric_value) AS total
    FROM {TARGET_CATALOG}.Incident_Account_Metrics_Snapshot_Daily GROUP BY ALL
    UNION ALL
    SELECT 'Daily', 'workspace', SNAPSHOT_DATE, metric_name, SUM(metric_value)
    FROM {TARGET_CATALOG}.Incident_Workspace_Metrics_Snapshot_Daily GROUP BY ALL
    UNION ALL
    SELECT 'Daily', 'user', SNAPSHOT_DATE, metric_name, SUM(metric_value)
    FROM {TARGET_CATALOG}.Incident_User_Metrics_Snapshot_Daily GROUP BY ALL
    UNION ALL
    SELECT 'Cumulative', 'account', SNAPSHOT_DATE, metric_name, SUM(metric_value)
    FROM {TARGET_CATALOG}.Incident_Account_Metrics_Snapshot_Cumulative GROUP BY ALL
    UNION ALL
    SELECT 'Cumulative', 'workspace', SNAPSHOT_DATE, metric_name, SUM(metric_value)
    FROM {TARGET_CATALOG}.Incident_Workspace_Metrics_Snapshot_Cumulative GROUP BY ALL
    UNION ALL
    SELECT 'Cumulative', 'user', SNAPSHOT_DATE, metric_name, SUM(metric_value)
    FROM {TARGET_CATALOG}.Incident_User_Metrics_Snapshot_Cumulative GROUP BY ALL
)
SELECT
    'grain_consistency' AS test
    ,cadence
    ,SNAPSHOT_DATE
    ,metric_name
    ,COUNT(*) AS grains_present
    ,MIN(total) AS min_total
    ,MAX(total) AS max_total
FROM grain_totals
GROUP BY ALL
HAVING COUNT(*) <> 3
    OR MIN(total) <> MAX(total)
ORDER BY 2, 3, 4;

-- Test 4: Uniqueness. One row per SNAPSHOT_DATE, grain key, and metric_name.
WITH keyed AS (
    SELECT 'Account_Daily' AS tbl, SNAPSHOT_DATE, CAST(account_id AS VARCHAR) AS grain_key, metric_name
    FROM {TARGET_CATALOG}.Incident_Account_Metrics_Snapshot_Daily
    UNION ALL
    SELECT 'Workspace_Daily', SNAPSHOT_DATE, account_id || '-' || workspace_id, metric_name
    FROM {TARGET_CATALOG}.Incident_Workspace_Metrics_Snapshot_Daily
    UNION ALL
    SELECT 'User_Daily', SNAPSHOT_DATE, account_id || '-' || user_id, metric_name
    FROM {TARGET_CATALOG}.Incident_User_Metrics_Snapshot_Daily
    UNION ALL
    SELECT 'Account_Cumulative', SNAPSHOT_DATE, CAST(account_id AS VARCHAR), metric_name
    FROM {TARGET_CATALOG}.Incident_Account_Metrics_Snapshot_Cumulative
    UNION ALL
    SELECT 'Workspace_Cumulative', SNAPSHOT_DATE, account_id || '-' || workspace_id, metric_name
    FROM {TARGET_CATALOG}.Incident_Workspace_Metrics_Snapshot_Cumulative
    UNION ALL
    SELECT 'User_Cumulative', SNAPSHOT_DATE, account_id || '-' || user_id, metric_name
    FROM {TARGET_CATALOG}.Incident_User_Metrics_Snapshot_Cumulative
)
SELECT
    'uniqueness' AS test
    ,tbl
    ,SNAPSHOT_DATE
    ,metric_name
    ,COUNT(*) AS duplicate_rows
FROM keyed
GROUP BY tbl, SNAPSHOT_DATE, grain_key, metric_name
HAVING COUNT(*) > 1
ORDER BY 2, 3, 4;

-- Test 5: NULL checks, metric_name domain, and non-positive values across all six tables.
WITH all_rows AS (
    SELECT 'Account_Daily' AS tbl, SNAPSHOT_DATE, metric_name, metric_value, account_id AS k1, account_id AS k2, LOAD_TIMESTAMP, SOURCE_ZONE
    FROM {TARGET_CATALOG}.Incident_Account_Metrics_Snapshot_Daily
    UNION ALL
    SELECT 'Workspace_Daily', SNAPSHOT_DATE, metric_name, metric_value, account_id, workspace_id, LOAD_TIMESTAMP, SOURCE_ZONE
    FROM {TARGET_CATALOG}.Incident_Workspace_Metrics_Snapshot_Daily
    UNION ALL
    SELECT 'User_Daily', SNAPSHOT_DATE, metric_name, metric_value, account_id, user_id, LOAD_TIMESTAMP, SOURCE_ZONE
    FROM {TARGET_CATALOG}.Incident_User_Metrics_Snapshot_Daily
    UNION ALL
    SELECT 'Account_Cumulative', SNAPSHOT_DATE, metric_name, metric_value, account_id, account_id, LOAD_TIMESTAMP, SOURCE_ZONE
    FROM {TARGET_CATALOG}.Incident_Account_Metrics_Snapshot_Cumulative
    UNION ALL
    SELECT 'Workspace_Cumulative', SNAPSHOT_DATE, metric_name, metric_value, account_id, workspace_id, LOAD_TIMESTAMP, SOURCE_ZONE
    FROM {TARGET_CATALOG}.Incident_Workspace_Metrics_Snapshot_Cumulative
    UNION ALL
    SELECT 'User_Cumulative', SNAPSHOT_DATE, metric_name, metric_value, account_id, user_id, LOAD_TIMESTAMP, SOURCE_ZONE
    FROM {TARGET_CATALOG}.Incident_User_Metrics_Snapshot_Cumulative
)
SELECT
    'row_quality' AS test
    ,tbl
    ,COUNT(*) FILTER (WHERE SNAPSHOT_DATE IS NULL OR k1 IS NULL OR k2 IS NULL OR metric_value IS NULL OR LOAD_TIMESTAMP IS NULL OR SOURCE_ZONE IS NULL) AS null_rows
    ,COUNT(*) FILTER (WHERE metric_name NOT IN ('total_incident_create_count', 'total_incident_resolve_count')) AS unknown_metric_rows
    ,COUNT(*) FILTER (WHERE metric_value <= 0) AS non_positive_rows
FROM all_rows
GROUP BY ALL
HAVING null_rows > 0
    OR unknown_metric_rows > 0
    OR non_positive_rows > 0
ORDER BY 2;

-- Test 6: Schema alignment. Column names and order match the DDL in Schema/.
WITH expected AS (
    SELECT * FROM (
        VALUES
            ('Account', 'SNAPSHOT_DATE,account_id,metric_name,metric_value,LOAD_TIMESTAMP,SOURCE_ZONE')
            ,('Workspace', 'SNAPSHOT_DATE,account_id,workspace_id,metric_name,metric_value,LOAD_TIMESTAMP,SOURCE_ZONE')
            ,('User', 'SNAPSHOT_DATE,account_id,user_id,metric_name,metric_value,LOAD_TIMESTAMP,SOURCE_ZONE')
    ) AS t (grain, columns_csv)
)
, cadences AS (
    SELECT * FROM (VALUES ('Daily'), ('Cumulative')) AS t (cadence)
)
, actual AS (
    SELECT
        table_name
        ,string_agg(column_name, ',' ORDER BY ordinal_position) AS columns_csv
    FROM information_schema.columns
    WHERE table_schema = '{TARGET_CATALOG}'
        AND table_name LIKE 'Incident_%'
    GROUP BY ALL
)
SELECT
    'schema_alignment' AS test
    ,'Incident_' || e.grain || '_Metrics_Snapshot_' || c.cadence AS table_name
    ,e.columns_csv AS expected_columns
    ,a.columns_csv AS actual_columns
FROM expected AS e
CROSS JOIN cadences AS c
LEFT JOIN actual AS a
    ON a.table_name = 'Incident_' || e.grain || '_Metrics_Snapshot_' || c.cadence
WHERE a.columns_csv IS DISTINCT FROM e.columns_csv
ORDER BY 2;
