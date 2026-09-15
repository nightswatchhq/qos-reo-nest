-- Seconds behind, net of the lag the whole deployment shares. Blocks behind in blocks means nothing
-- across chains whose block times differ 48-fold, and one dead deployment can dominate it: an
-- arbitrum-sepolia deployment 306M blocks behind put 0x0a015d9e at 1.59M for 2026-09-06..12.
--
-- Same rule as kittiwake's quality score (`aggregate_indexer_metrics`): a peer is credible at 100
-- measured queries, a floor needs three credible peers, and without a floor the raw figure stands.
-- The score applies it over its window; this applies it per day, for the chart.

CREATE VIEW qos_indexer_deployment_lag AS
SELECT a.indexer, a.deployment, a.chain, a.day,
       sum(a.query_count) AS query_count,
       sum(a.blocks_behind_x_queries) / nullif(sum(a.query_count), 0) AS blocks_behind,
       sum(a.blocks_behind_x_queries) / nullif(sum(a.query_count), 0) * t.block_time_sec AS seconds_behind
FROM qos_allocation_daily a
LEFT JOIN qos_chain_block_time t ON t.chain = a.chain
GROUP BY a.indexer, a.deployment, a.chain, a.day, t.block_time_sec;

CREATE VIEW qos_deployment_lag_floor AS
SELECT deployment, chain, day,
       min(seconds_behind) AS floor_seconds_behind,
       count(*) AS credible_peers
FROM qos_indexer_deployment_lag
WHERE query_count >= 100 AND seconds_behind IS NOT NULL
GROUP BY ALL
HAVING count(*) >= 3;

-- The floor is `qos_deployment_lag_floor`'s, taken with a window so a one-day statement reads the rows
-- once. A NULL deployment or chain gets no floor, as a join to that view would find none.
CREATE VIEW qos_seconds_behind AS
SELECT indexer, deployment, chain, day, query_count, blocks_behind, seconds_behind, floor_seconds_behind,
       CASE WHEN floor_seconds_behind IS NULL THEN seconds_behind
            ELSE greatest(seconds_behind - floor_seconds_behind, 0) END AS seconds_behind_peers
FROM (
  SELECT l.*,
         CASE WHEN deployment IS NOT NULL AND chain IS NOT NULL
               AND count(*) FILTER (WHERE query_count >= 100 AND seconds_behind IS NOT NULL) OVER w >= 3
              THEN min(seconds_behind) FILTER (WHERE query_count >= 100 AND seconds_behind IS NOT NULL) OVER w
         END AS floor_seconds_behind
  FROM qos_indexer_deployment_lag l
  WINDOW w AS (PARTITION BY deployment, chain, day)
);

-- The chart's figures: query-weighted over the indexer's deployments with a known block time, and the
-- share of its queries that had one, so a day measured on 40% of traffic does not read as the whole.
-- The mean is still owned by the worst deployment (on 2026-09-07 one indexer's reads 15.8M seconds), so
-- the share of queries answered more than five minutes behind its peers sits beside it.
CREATE VIEW qos_indexer_seconds_behind AS
SELECT indexer, day,
       sum(seconds_behind_peers * query_count) FILTER (WHERE seconds_behind_peers IS NOT NULL)
         / nullif(sum(query_count) FILTER (WHERE seconds_behind_peers IS NOT NULL), 0) AS seconds_behind_peers,
       sum(query_count) FILTER (WHERE seconds_behind_peers > 300)
         / nullif(sum(query_count) FILTER (WHERE seconds_behind_peers IS NOT NULL), 0) AS share_queries_over_5min_behind,
       sum(query_count) FILTER (WHERE seconds_behind_peers IS NOT NULL)
         / nullif(sum(query_count), 0) AS share_with_block_time
FROM qos_seconds_behind
GROUP BY ALL;
