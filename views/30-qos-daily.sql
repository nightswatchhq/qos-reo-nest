-- The daily grain the charts and the quality score read. Every rate is a ratio of sums, never a mean of
-- rates: the old Lodestar card averaged daily figures, which put staked.cloud at 62.7% for a week it
-- served at 83.4%. Latency and blocks behind are weighted by queries because the oracle's average
-- behaves as if it includes failed responses (weighting by 200s moved 99 of 374 indexer-days by >20%).
--
-- A "bad bucket" has at least 50 queries and under 90% success. It is what a daily figure hides:
-- Ellipfra read 97.36% for 2026-09-06..12 while one bucket served 0 of 52,286.

CREATE VIEW qos_allocation_bucket AS
SELECT indexer, deployment, chain, gateway, day, bucket_start,
       sum(query_count) AS query_count,
       sum(num_200) AS num_200,
       sum(avg_latency_ms * query_count) AS latency_x_queries,
       sum(avg_blocks_behind * query_count) AS blocks_behind_x_queries,
       sum(total_query_fees) AS total_query_fees
FROM qos_indexer_attempt
GROUP BY ALL;

CREATE VIEW qos_allocation_daily AS
SELECT indexer, deployment, chain, gateway, day,
       sum(query_count) AS query_count,
       sum(num_200) AS num_200,
       sum(num_200) / nullif(sum(query_count), 0) AS success_rate,
       sum(latency_x_queries) / nullif(sum(query_count), 0) AS latency_ms,
       sum(blocks_behind_x_queries) / nullif(sum(query_count), 0) AS blocks_behind,
       sum(total_query_fees) AS total_query_fees,
       sum(total_query_fees) / nullif(sum(query_count), 0) AS avg_query_fee,
       count(*) AS buckets,
       count(*) FILTER (WHERE query_count >= 50 AND num_200 < 0.9 * query_count) AS bad_buckets,
       arg_min(bucket_start, [num_200 / query_count, bucket_start::DOUBLE])
         FILTER (WHERE query_count >= 50) AS worst_bucket_start,
       min(num_200 / query_count) FILTER (WHERE query_count >= 50) AS worst_bucket_success_rate,
       arg_min(query_count, [num_200 / query_count, bucket_start::DOUBLE])
         FILTER (WHERE query_count >= 50) AS worst_bucket_queries,
       -- Sums kept so a coarser grain can re-weight exactly instead of averaging these rows.
       sum(latency_x_queries) AS latency_x_queries,
       sum(blocks_behind_x_queries) AS blocks_behind_x_queries
FROM qos_allocation_bucket
GROUP BY ALL;

-- Each deployment's query total from the gateway's side: the served-share denominator. Indexer attempts
-- undercount it wherever the gateway retried a query on a second indexer.
CREATE VIEW qos_deployment_daily AS
SELECT deployment, chain, gateway, day,
       sum(query_count) AS query_count,
       count(DISTINCT bucket_start) AS buckets
FROM qos_query_result
GROUP BY ALL;

-- Indexer-day: additive figures are sums of `qos_allocation_daily`, rates are ratios of those sums.
-- Bucket counts cannot be summed from allocation rows (a bucket is one bucket however many allocations
-- it touched), so those come from the indexer's own buckets.
CREATE VIEW qos_indexer_bucket AS
SELECT indexer, day, bucket_start,
       sum(query_count) AS query_count,
       sum(num_200) AS num_200
FROM qos_allocation_bucket
GROUP BY ALL;

CREATE VIEW qos_indexer_daily AS
WITH sums AS (
  SELECT indexer, day,
         sum(query_count) AS query_count,
         sum(num_200) AS num_200,
         sum(latency_x_queries) AS latency_x_queries,
         sum(blocks_behind_x_queries) AS blocks_behind_x_queries,
         sum(total_query_fees) AS total_query_fees,
         count(*) AS allocations
  FROM qos_allocation_daily
  GROUP BY ALL
), buckets AS (
  SELECT indexer, day,
         count(*) AS buckets,
         count(*) FILTER (WHERE query_count >= 50 AND num_200 < 0.9 * query_count) AS bad_buckets,
         arg_min(bucket_start, [num_200 / query_count, bucket_start::DOUBLE])
           FILTER (WHERE query_count >= 50) AS worst_bucket_start,
         min(num_200 / query_count) FILTER (WHERE query_count >= 50) AS worst_bucket_success_rate,
         arg_min(query_count, [num_200 / query_count, bucket_start::DOUBLE])
           FILTER (WHERE query_count >= 50) AS worst_bucket_queries
  FROM qos_indexer_bucket
  GROUP BY ALL
)
SELECT s.indexer, s.day,
       s.query_count,
       s.num_200,
       s.num_200 / nullif(s.query_count, 0) AS success_rate,
       s.latency_x_queries / nullif(s.query_count, 0) AS latency_ms,
       s.blocks_behind_x_queries / nullif(s.query_count, 0) AS blocks_behind,
       s.total_query_fees,
       s.total_query_fees / nullif(s.query_count, 0) AS avg_query_fee,
       s.allocations,
       b.buckets, b.bad_buckets, b.worst_bucket_start, b.worst_bucket_success_rate, b.worst_bucket_queries
FROM sums s
JOIN buckets b USING (indexer, day);
