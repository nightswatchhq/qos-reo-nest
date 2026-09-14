-- The publisher list is data, not code: the reference subgraph hard-coded an allowlist that went stale
-- when the signer rotated, and rejected every message for a month while reporting itself healthy.
-- Rejected documents are counted, never silently dropped.
CREATE VIEW qos_publisher AS
SELECT * FROM (VALUES
  ('0x8cbbe43f97f80efa6ba0a95f3d544e03f84db0ce', 'Edge & Node gateway QoS publisher, seen 2026-06 to 2026-09')
) AS t(address, note);

-- The calls a listed publisher sent, by the sender nuthatch records on every call row (`tx_from`).
CREATE VIEW qos_published_call AS
SELECT CAST(c.block_number AS BIGINT) AS block_number,
       CAST(c.log_index AS BIGINT) AS log_index
FROM data_edge__call_submit_qo_s_payload c
JOIN qos_publisher p ON p.address = lower(c.tx_from);

-- A typed row names the call that named its document (`source_log_index`). nuthatch plans a CID once per
-- block from the first row naming it, so a stranger re-posting a published CID ahead of the publisher in
-- the same block would take the document; it would show here rather than vanish.
CREATE VIEW qos_rejected_documents AS
SELECT 'indexer' AS topic, CAST(r.block_number AS BIGINT) AS block_number, r.cid, count(*) AS rows
FROM qos_indexer_attempt_rows r
LEFT JOIN qos_published_call c
  ON c.block_number = CAST(r.block_number AS BIGINT) AND c.log_index = CAST(r.source_log_index AS BIGINT)
WHERE c.block_number IS NULL
GROUP BY ALL
UNION ALL
SELECT 'query', CAST(r.block_number AS BIGINT), r.cid, count(*)
FROM qos_query_result_rows r
LEFT JOIN qos_published_call c
  ON c.block_number = CAST(r.block_number AS BIGINT) AND c.log_index = CAST(r.source_log_index AS BIGINT)
WHERE c.block_number IS NULL
GROUP BY ALL;
