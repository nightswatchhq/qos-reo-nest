-- How current the nest is, network-wide, as two separate questions: when the publisher last posted,
-- and the newest bucket this nest holds figures for. They differ, and conflating them is how a feed
-- that stopped resolving kept reporting itself fresh.
CREATE VIEW qos_freshness AS
WITH posts AS (
  SELECT max(CAST(c.block_number AS BIGINT)) AS last_post_block,
         max(CAST(c.block_timestamp AS BIGINT)) AS last_post_time
  FROM data_edge__call_submit_qo_s_payload c
  JOIN qos_publisher p ON p.address = lower(c.tx_from)
), buckets AS (
  SELECT 'indexer' AS topic, max(bucket_start) AS newest_bucket_start, count(DISTINCT bucket_start) AS buckets
  FROM qos_indexer_attempt
  UNION ALL
  SELECT 'query', max(bucket_start), count(DISTINCT bucket_start)
  FROM qos_query_result
)
SELECT b.topic,
       b.newest_bucket_start,
       b.newest_bucket_start + 300 AS newest_bucket_end,
       b.buckets,
       p.last_post_block,
       p.last_post_time,
       p.last_post_time - (b.newest_bucket_start + 300) AS post_ahead_of_newest_bucket_secs
FROM buckets b CROSS JOIN posts p;
