-- The two switches the rest of the views read, kept in one place so turning either on is a one-line
-- change rather than an edit to every view.
--
-- `require_verified`: every document this oracle publishes is 0.5 to 1.9 MB, over nuthatch's 256 KiB
-- single-block verification limit, so today each one is stored `verified = false`. Flip this to TRUE
-- once multi-block verification lands and nothing unverified will reach a figure.
CREATE VIEW qos_settings AS
SELECT FALSE AS require_verified;

-- One JSON array per five-minute bucket. `from_json` with an explicit shape rather than `json_extract`
-- per field: the document is parsed once, and a field the publisher renames reads as NULL instead of
-- failing the view.
CREATE VIEW qos_indexer_attempt_raw AS
SELECT p.cid,
       CAST(p.verified AS VARCHAR) = 'true' AS verified,
       p.block_number,
       p.log_index,
       unnest(from_json(p.content, '[{
         "indexer_wallet": "VARCHAR", "indexer_url": "VARCHAR",
         "subgraph_deployment_ipfs_hash": "VARCHAR", "chain": "VARCHAR", "gateway_id": "VARCHAR",
         "start_epoch": "BIGINT", "end_epoch": "BIGINT",
         "query_count": "DOUBLE", "num_indexer_200_responses": "DOUBLE",
         "proportion_indexer_200_responses": "DOUBLE",
         "avg_indexer_latency_ms": "DOUBLE", "max_indexer_latency_ms": "DOUBLE",
         "stdev_indexer_latency_ms": "DOUBLE",
         "avg_indexer_blocks_behind": "DOUBLE", "max_indexer_blocks_behind": "DOUBLE",
         "avg_query_fee": "DOUBLE", "max_query_fee": "DOUBLE", "total_query_fees": "DOUBLE"
       }]')) AS r
FROM qos_indexer_payload p
WHERE CAST(p.verified AS VARCHAR) = 'true'
   OR NOT (SELECT require_verified FROM qos_settings);

CREATE VIEW qos_query_result_raw AS
SELECT p.cid,
       CAST(p.verified AS VARCHAR) = 'true' AS verified,
       p.block_number,
       p.log_index,
       unnest(from_json(p.content, '[{
         "subgraph_deployment_ipfs_hash": "VARCHAR", "chain": "VARCHAR", "gateway_id": "VARCHAR",
         "start_epoch": "BIGINT", "end_epoch": "BIGINT",
         "query_count": "DOUBLE", "gateway_query_success_rate": "DOUBLE",
         "user_attributed_error_rate": "DOUBLE",
         "avg_gateway_latency_ms": "DOUBLE", "max_gateway_latency_ms": "DOUBLE",
         "stdev_gateway_latency_ms": "DOUBLE",
         "avg_query_fee": "DOUBLE", "max_query_fee": "DOUBLE", "total_query_fees": "DOUBLE",
         "most_recent_query_ts": "BIGINT"
       }]')) AS r
FROM qos_query_payload p
WHERE CAST(p.verified AS VARCHAR) = 'true'
   OR NOT (SELECT require_verified FROM qos_settings);
