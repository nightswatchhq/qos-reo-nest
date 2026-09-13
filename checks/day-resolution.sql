-- `qos_day_resolution` against the typed rows it stands in for. For every day and topic, the buckets it
-- counts as stored must be the distinct buckets the typed rows hold, and 2026-09-07 must be fully
-- resolved: 288 buckets posted and stored per topic, nothing unresolved. Expect zero rows.
WITH typed AS (
  SELECT day, 'indexer' AS topic, count(DISTINCT bucket_start) AS buckets FROM qos_indexer_attempt GROUP BY day
  UNION ALL
  SELECT day, 'query', count(DISTINCT bucket_start) FROM qos_query_result GROUP BY day
)
SELECT CAST(coalesce(r.day, t.day) AS VARCHAR) AS day, coalesce(r.topic, t.topic) AS topic,
       'stored buckets differ from the typed rows' AS differs
FROM qos_day_resolution r
FULL OUTER JOIN typed t ON t.day = r.day AND t.topic = r.topic
WHERE coalesce(r.buckets_stored, 0) <> coalesce(t.buckets, 0)
UNION ALL
SELECT '2026-09-07', topic, 'not fully resolved'
FROM qos_day_resolution
WHERE day = DATE '2026-09-07'
  AND (buckets_posted <> 288 OR buckets_stored <> 288 OR unresolved_documents <> 0)
ORDER BY 1, 2;
