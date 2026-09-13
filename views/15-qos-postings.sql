-- Every document a listed publisher named, from its calldata: the topic, the CID and the bucket. The
-- calldata is hex of UTF-8 JSON, one `{topic, hash, timestamp}` object or an array of them, and
-- `timestamp` is the bucket's end. Calldata that does not decode names no document rather than failing
-- the view. One row per posting, so a few hundred a day whatever the documents hold.
CREATE VIEW qos_posting AS
WITH calls AS (
  SELECT CAST(c.block_number AS BIGINT) AS block_number,
         CAST(c.log_index AS BIGINT) AS log_index,
         CAST(c.block_timestamp AS BIGINT) AS block_timestamp,
         TRY(CAST(decode(unhex(substr(CAST(c._payload AS VARCHAR), 3))) AS VARCHAR)) AS payload
  FROM data_edge__call_submit_qo_s_payload c
  JOIN qos_publisher p ON p.address = lower(c.tx_from)
), named AS (
  SELECT block_number, log_index, block_timestamp,
         unnest(CASE WHEN json_type(payload) = 'ARRAY'
                     THEN TRY(from_json(payload, '[{"topic":"VARCHAR","hash":"VARCHAR","timestamp":"BIGINT"}]'))
                     ELSE [TRY(from_json(payload, '{"topic":"VARCHAR","hash":"VARCHAR","timestamp":"BIGINT"}'))] END) AS doc
  FROM calls
)
SELECT block_number, log_index, block_timestamp,
       CASE doc.topic
         WHEN 'gateway_indexer_attempt_qos_5_minutes_prod_v3' THEN 'indexer'
         WHEN 'gateway_query_result_qos_5_minutes_prod_v3' THEN 'query'
       END AS topic,
       doc.hash AS cid,
       doc.timestamp - 300 AS bucket_start,
       DATE '1970-01-01' + CAST((doc.timestamp - 300) // 86400 AS INTEGER) AS day
FROM named
WHERE doc IS NOT NULL AND doc.topic IN ('gateway_indexer_attempt_qos_5_minutes_prod_v3',
                                        'gateway_query_result_qos_5_minutes_prod_v3');

-- The documents nuthatch has stored, one row each. A document is keyed by its block and CID, the pair its
-- posting names: the document row's `log_index` is a storage slot, not the posting's.
CREATE VIEW qos_stored_document AS
SELECT 'indexer' AS topic, CAST(block_number AS BIGINT) AS block_number, cid
FROM qos_indexer_payload
WHERE CAST(verified AS VARCHAR) = 'true' OR NOT (SELECT require_verified FROM qos_settings)
UNION ALL
SELECT 'query', CAST(block_number AS BIGINT), cid
FROM qos_query_payload
WHERE CAST(verified AS VARCHAR) = 'true' OR NOT (SELECT require_verified FROM qos_settings);
