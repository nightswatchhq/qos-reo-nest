-- Per UTC day and topic: the buckets posted, the buckets whose document is stored, the postings whose
-- document is not, and the highest block holding a posting. A document the resolver gave up on is never
-- stored, so it stays unresolved here for ever: a reader deciding a day is final must see it.
CREATE VIEW qos_day_resolution AS
SELECT p.day, p.topic,
       count(DISTINCT p.bucket_start) AS buckets_posted,
       count(DISTINCT p.bucket_start) FILTER (WHERE s.cid IS NOT NULL) AS buckets_stored,
       count(*) FILTER (WHERE s.cid IS NULL) AS unresolved_documents,
       max(p.block_number) AS closing_block
FROM qos_posting p
LEFT JOIN qos_stored_document s
  ON s.topic = p.topic AND s.block_number = p.block_number AND s.cid = p.cid
GROUP BY p.day, p.topic;
