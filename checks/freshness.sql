-- `qos_freshness` against the aggregate over every typed row it replaced: the newest bucket and the
-- bucket count per topic must agree. Expect zero rows.
WITH typed AS (
  SELECT 'indexer' AS topic, max(bucket_start) AS newest_bucket_start, count(DISTINCT bucket_start) AS buckets
  FROM qos_indexer_attempt
  UNION ALL
  SELECT 'query', max(bucket_start), count(DISTINCT bucket_start) FROM qos_query_result
)
SELECT f.topic, 'freshness differs from the typed rows' AS differs
FROM qos_freshness f
JOIN typed t USING (topic)
WHERE f.newest_bucket_start IS DISTINCT FROM t.newest_bucket_start
   OR f.buckets <> t.buckets
ORDER BY 1;
