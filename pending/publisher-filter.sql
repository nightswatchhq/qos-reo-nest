-- NOT LOADED. Moves into views/ once top-level call rows carry the transaction sender (`from`), which
-- nuthatch does not record today (`CallContext`, src/calldata.rs). Until then this nest accepts every
-- `submitQoSPayload` sent to the DataEdge, whoever sent it.
--
-- The publisher list is data, not code: the reference subgraph hard-coded an allowlist that went stale
-- when the signer rotated, and rejected every message for a month while reporting itself healthy.
-- Rejected documents are counted, never silently dropped.
--
-- To enable: copy into views/ as 05-qos-publisher.sql, and in views/10-qos-documents.sql read
-- `qos_indexer_payload_published` / `qos_query_payload_published` instead of the raw payload tables.

CREATE VIEW qos_publisher AS
SELECT * FROM (VALUES
  ('0x8cbbe43f97f80efa6ba0a95f3d544e03f84db0ce', 'Edge & Node gateway QoS publisher, seen 2026-06 to 2026-09')
) AS t(address, note);

-- A document has no transaction of its own, so it is matched to the call that named it: same block, and
-- the call's JSON payload names this CID (an object, or any element of an array).
CREATE VIEW qos_document_sender AS
WITH calls AS (
  SELECT c.block_number, lower(c."from") AS sender,
         decode(unhex(substr(c._payload, 3))) AS payload
  FROM data_edge__call_submit_qo_s_payload c
)
SELECT DISTINCT c.block_number, c.sender, h.cid
FROM calls c,
     LATERAL (
       -- `$[*].hash` on an object is an empty list, not NULL, so the shape has to be asked for.
       SELECT unnest(CASE WHEN json_type(c.payload) = 'ARRAY'
                          THEN json_extract_string(c.payload, '$[*].hash')
                          ELSE [json_extract_string(c.payload, '$.hash')] END) AS cid
     ) h;

CREATE VIEW qos_indexer_payload_published AS
SELECT p.*
FROM qos_indexer_payload p
JOIN qos_document_sender s ON s.block_number = p.block_number AND s.cid = p.cid
JOIN qos_publisher k ON k.address = s.sender;

CREATE VIEW qos_query_payload_published AS
SELECT p.*
FROM qos_query_payload p
JOIN qos_document_sender s ON s.block_number = p.block_number AND s.cid = p.cid
JOIN qos_publisher k ON k.address = s.sender;

-- Rejected means no listed publisher named it. A stranger re-posting a published CID in the same block
-- does not make the real document rejected.
CREATE VIEW qos_rejected_documents AS
SELECT 'indexer' AS topic, p.block_number, p.cid
FROM qos_indexer_payload p
WHERE NOT EXISTS (SELECT 1 FROM qos_indexer_payload_published q WHERE q.block_number = p.block_number AND q.cid = p.cid)
UNION ALL
SELECT 'query', p.block_number, p.cid
FROM qos_query_payload p
WHERE NOT EXISTS (SELECT 1 FROM qos_query_payload_published q WHERE q.block_number = p.block_number AND q.cid = p.cid);
