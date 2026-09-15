-- `require_verified`: nuthatch stores only documents proven against their CID (RFC-0037 slice 7), so
-- every row this build writes is verified. The switch stays as the guard against a row an older build
-- stored unverified.
CREATE VIEW qos_settings AS
SELECT TRUE AS require_verified;

-- Each UTC day with its bucket starts as the decimal text the typed rows store. Rows match on the day
-- computed from them; the text range is redundant to that, but DuckDB pushes it into the Parquet scan so
-- `day = ...` reads one day's segments. Text orders like the number only at one length: ten digits here.
CREATE VIEW qos_day_bounds AS
SELECT DATE '1970-01-01' + CAST(d AS INTEGER) AS day,
       CAST(d * 86400 AS VARCHAR) AS first_start_epoch,
       CAST(d * 86400 + 86399 AS VARCHAR) AS last_start_epoch
FROM range(11575, 115740) AS t(d);

-- The typed rows nuthatch exploded from each proven document when it resolved (RFC-0037 slice 8), from
-- a listed publisher only. Nothing here parses JSON. Stored columns are cast once, here: numbers arrive
-- as their decimal text, and an absent one is empty text, which reads as NULL.
CREATE VIEW qos_indexer_attempt_raw AS
SELECT r.cid,
       CAST(d.verified AS VARCHAR) = 'true' AS verified,
       CAST(r.block_number AS BIGINT) AS block_number,
       CAST(r.document_log_index AS BIGINT) AS log_index,
       CAST(r.element AS BIGINT) AS element,
       r.indexer_wallet, r.indexer_url, r.subgraph_deployment_ipfs_hash, r.chain, r.gateway_id,
       CAST(r.start_epoch AS BIGINT) AS start_epoch,
       CAST(r.end_epoch AS BIGINT) AS end_epoch,
       CAST(nullif(r.query_count, '') AS DOUBLE) AS query_count,
       CAST(nullif(r.num_indexer_200_responses, '') AS DOUBLE) AS num_indexer_200_responses,
       CAST(nullif(r.proportion_indexer_200_responses, '') AS DOUBLE) AS proportion_indexer_200_responses,
       CAST(nullif(r.avg_indexer_latency_ms, '') AS DOUBLE) AS avg_indexer_latency_ms,
       CAST(nullif(r.max_indexer_latency_ms, '') AS DOUBLE) AS max_indexer_latency_ms,
       CAST(nullif(r.stdev_indexer_latency_ms, '') AS DOUBLE) AS stdev_indexer_latency_ms,
       CAST(nullif(r.avg_indexer_blocks_behind, '') AS DOUBLE) AS avg_indexer_blocks_behind,
       CAST(nullif(r.max_indexer_blocks_behind, '') AS DOUBLE) AS max_indexer_blocks_behind,
       CAST(nullif(r.avg_query_fee, '') AS DOUBLE) AS avg_query_fee,
       CAST(nullif(r.max_query_fee, '') AS DOUBLE) AS max_query_fee,
       CAST(nullif(r.total_query_fees, '') AS DOUBLE) AS total_query_fees,
       k.day
FROM qos_indexer_attempt_rows r
JOIN qos_day_bounds k
  ON k.day = DATE '1970-01-01' + CAST(CAST(r.start_epoch AS BIGINT) // 86400 AS INTEGER)
 AND r.start_epoch BETWEEN k.first_start_epoch AND k.last_start_epoch
JOIN qos_indexer_payload d
  ON CAST(d.block_number AS BIGINT) = CAST(r.block_number AS BIGINT)
 AND CAST(d.log_index AS BIGINT) = CAST(r.document_log_index AS BIGINT)
JOIN qos_published_call c
  ON c.block_number = CAST(r.block_number AS BIGINT) AND c.log_index = CAST(r.source_log_index AS BIGINT)
WHERE CAST(d.verified AS VARCHAR) = 'true'
   OR NOT (SELECT require_verified FROM qos_settings);

CREATE VIEW qos_query_result_raw AS
SELECT r.cid,
       CAST(d.verified AS VARCHAR) = 'true' AS verified,
       CAST(r.block_number AS BIGINT) AS block_number,
       CAST(r.document_log_index AS BIGINT) AS log_index,
       CAST(r.element AS BIGINT) AS element,
       r.subgraph_deployment_ipfs_hash, r.chain, r.gateway_id,
       CAST(r.start_epoch AS BIGINT) AS start_epoch,
       CAST(r.end_epoch AS BIGINT) AS end_epoch,
       CAST(nullif(r.query_count, '') AS DOUBLE) AS query_count,
       CAST(nullif(r.gateway_query_success_rate, '') AS DOUBLE) AS gateway_query_success_rate,
       CAST(nullif(r.user_attributed_error_rate, '') AS DOUBLE) AS user_attributed_error_rate,
       CAST(nullif(r.avg_gateway_latency_ms, '') AS DOUBLE) AS avg_gateway_latency_ms,
       CAST(nullif(r.max_gateway_latency_ms, '') AS DOUBLE) AS max_gateway_latency_ms,
       CAST(nullif(r.stdev_gateway_latency_ms, '') AS DOUBLE) AS stdev_gateway_latency_ms,
       CAST(nullif(r.avg_query_fee, '') AS DOUBLE) AS avg_query_fee,
       CAST(nullif(r.max_query_fee, '') AS DOUBLE) AS max_query_fee,
       CAST(nullif(r.total_query_fees, '') AS DOUBLE) AS total_query_fees,
       CAST(CAST(nullif(r.most_recent_query_ts, '') AS DOUBLE) AS BIGINT) AS most_recent_query_ts,
       k.day
FROM qos_query_result_rows r
JOIN qos_day_bounds k
  ON k.day = DATE '1970-01-01' + CAST(CAST(r.start_epoch AS BIGINT) // 86400 AS INTEGER)
 AND r.start_epoch BETWEEN k.first_start_epoch AND k.last_start_epoch
JOIN qos_query_payload d
  ON CAST(d.block_number AS BIGINT) = CAST(r.block_number AS BIGINT)
 AND CAST(d.log_index AS BIGINT) = CAST(r.document_log_index AS BIGINT)
JOIN qos_published_call c
  ON c.block_number = CAST(r.block_number AS BIGINT) AND c.log_index = CAST(r.source_log_index AS BIGINT)
WHERE CAST(d.verified AS VARCHAR) = 'true'
   OR NOT (SELECT require_verified FROM qos_settings);
