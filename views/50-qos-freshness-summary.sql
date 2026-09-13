-- How current the nest is, network-wide, as two separate questions: when the publisher last posted,
-- and the newest bucket this nest holds figures for. They differ, and conflating them is how a feed
-- that stopped resolving kept reporting itself fresh.
--
-- Read from postings and stored documents, one row per five-minute document, never from the typed rows
-- (thousands per document). A bucket is held when its document is stored, which is when its rows are:
-- nuthatch writes both in one transaction.
CREATE VIEW qos_freshness AS
WITH held AS (
  SELECT p.topic, max(p.bucket_start) AS newest_bucket_start, count(DISTINCT p.bucket_start) AS buckets
  FROM qos_posting p
  JOIN qos_stored_document s ON s.topic = p.topic AND s.block_number = p.block_number AND s.cid = p.cid
  GROUP BY p.topic
), posts AS (
  SELECT max(block_number) AS last_post_block, max(block_timestamp) AS last_post_time
  FROM qos_posting
)
SELECT t.topic,
       h.newest_bucket_start,
       h.newest_bucket_start + 300 AS newest_bucket_end,
       coalesce(h.buckets, 0) AS buckets,
       p.last_post_block,
       p.last_post_time,
       p.last_post_time - (h.newest_bucket_start + 300) AS post_ahead_of_newest_bucket_secs
FROM (VALUES ('indexer'), ('query')) AS t(topic)
LEFT JOIN held h USING (topic)
CROSS JOIN posts p;
