-- Typed rows, one per bucket. A day is the UTC day of the bucket's START: the publisher's own
-- `timestamp` is the bucket's end, so dating by it files the 23:55 bucket under the next day.
--
-- If a bucket is ever published twice (a retried post with a new CID), only the first document for it
-- counts. Summing both would double every figure for those five minutes and nothing downstream could
-- tell. In 2026-09-06..12 no bucket was published twice.

CREATE VIEW qos_indexer_attempt AS
WITH ranked AS (
  SELECT *,
         dense_rank() OVER (PARTITION BY r.start_epoch ORDER BY block_number, log_index) AS doc_rank
  FROM qos_indexer_attempt_raw
)
SELECT r.start_epoch AS bucket_start,
       r.end_epoch AS bucket_end,
       DATE '1970-01-01' + CAST(r.start_epoch // 86400 AS INTEGER) AS day,
       lower(r.indexer_wallet) AS indexer,
       r.indexer_url,
       r.subgraph_deployment_ipfs_hash AS deployment,
       lower(r.chain) AS chain,
       lower(r.gateway_id) AS gateway,
       r.query_count,
       -- The published count, not proportion times count: the count is what the gateway observed.
       coalesce(r.num_indexer_200_responses, r.proportion_indexer_200_responses * r.query_count) AS num_200,
       r.avg_indexer_latency_ms AS avg_latency_ms,
       r.max_indexer_latency_ms AS max_latency_ms,
       r.stdev_indexer_latency_ms AS stdev_latency_ms,
       r.avg_indexer_blocks_behind AS avg_blocks_behind,
       r.max_indexer_blocks_behind AS max_blocks_behind,
       r.avg_query_fee,
       r.max_query_fee,
       r.total_query_fees,
       cid,
       verified,
       block_number
FROM ranked
WHERE doc_rank = 1;

CREATE VIEW qos_query_result AS
WITH ranked AS (
  SELECT *,
         dense_rank() OVER (PARTITION BY r.start_epoch ORDER BY block_number, log_index) AS doc_rank
  FROM qos_query_result_raw
)
SELECT r.start_epoch AS bucket_start,
       r.end_epoch AS bucket_end,
       DATE '1970-01-01' + CAST(r.start_epoch // 86400 AS INTEGER) AS day,
       r.subgraph_deployment_ipfs_hash AS deployment,
       lower(r.chain) AS chain,
       lower(r.gateway_id) AS gateway,
       r.query_count,
       r.gateway_query_success_rate,
       r.user_attributed_error_rate,
       r.avg_gateway_latency_ms,
       r.max_gateway_latency_ms,
       r.stdev_gateway_latency_ms,
       r.avg_query_fee,
       r.max_query_fee,
       r.total_query_fees,
       r.most_recent_query_ts,
       cid,
       verified,
       block_number
FROM ranked
WHERE doc_rank = 1;

-- Block times by the oracle's chain name, identical to kittiwake's `block_time_sec`. A chain not listed
-- has no seconds-behind figure at all: an unknown block time is not evidence of lag.
CREATE VIEW qos_chain_block_time AS
SELECT * FROM (VALUES
  ('mainnet', 12.0), ('sepolia', 12.0), ('moonbeam', 12.0),
  ('arbitrum-one', 0.25), ('arbitrum', 0.25), ('arbitrum-sepolia', 0.25),
  ('base', 2.0), ('base-sepolia', 2.0), ('optimism', 2.0), ('optimism-sepolia', 2.0),
  ('matic', 2.0), ('polygon', 2.0), ('polygon-zkevm', 2.0), ('avalanche', 2.0), ('linea', 2.0),
  ('blast-mainnet', 2.0), ('boba', 2.0),
  ('bsc', 3.0), ('chapel', 3.0), ('scroll', 3.0), ('xlayer-mainnet', 3.0), ('chiliz', 3.0),
  ('chiliz-testnet', 3.0),
  ('gnosis', 5.0), ('xdai', 5.0), ('celo', 5.0), ('fuse', 5.0),
  ('fantom', 1.0), ('unichain', 1.0), ('zksync-era', 1.0), ('monad', 1.0),
  ('sonic', 0.5)
) AS t(chain, block_time_sec);
