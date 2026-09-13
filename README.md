# QoS oracle nest

A Nuthatch nest for **Edge & Node's gateway QoS oracle**, read from its own postings on Gnosis rather
than from its subgraph. It serves the per indexer, deployment and day figures behind Lodestar's Query
Performance chart and QoS Quality score, with no Graph API key.

```sh
nuthatch dev --dir qos-reo-nest --ipfs https://ipfs.thegraph.com/ipfs/
nuthatch sql --dir qos-reo-nest "SELECT * FROM qos_indexer_daily WHERE day = DATE '2026-09-07' ORDER BY query_count DESC"
```

Needs a nuthatch build with `[[ipfs]] cid_json_path` and `json_match` (nightswatchhq/nuthatch#1367).

## What the oracle publishes

Every five minutes the publisher calls `submitQoSPayload(bytes)` on the DataEdge
`0x5b4293b4c0f36cb5d4448950830bc777759b6c4f` twice, once per topic. The DataEdge emits no events; the
payload is UTF-8 JSON, `{"topic": ..., "hash": <CID>, "timestamp": <bucket end>}`, and the CID names a
JSON array of five-minute aggregates:

| Topic | One element per | Used for |
|---|---|---|
| `gateway_indexer_attempt_qos_5_minutes_prod_v3` | indexer, deployment, chain, gateway | the charts and the quality score |
| `gateway_query_result_qos_5_minutes_prod_v3` | deployment, chain, gateway | each deployment's query total (served share) |

The publisher seen from 2026-06 to 2026-09 is `0x8cbbe43f97f80efa6ba0a95f3d544e03f84db0ce`. Indexer-attempt
documents run 1.5 to 1.9 MB and 2,500 to 2,900 elements; query-result documents about 0.6 MB.

`start_block` is 46,700,000 (2026-06-14 23:15 UTC), a 90-day window from 2026-09-13. The reference
subgraph starts at 24,747,400 if more history is wanted.

## Query surface

- **`qos_indexer_daily`** - per indexer per UTC day: queries, 200s, success rate, latency, blocks behind,
  fees, buckets seen, bad buckets and the worst bucket. The Query Performance chart.
- **`qos_allocation_daily`** - the same per indexer, deployment, chain and gateway. The grain the QoS
  Quality score reads.
- **`qos_deployment_daily`** - each deployment's query total from the gateway's side.
- **`qos_indexer_seconds_behind`** / **`qos_seconds_behind`** - seconds behind the freshest credible
  peer on the same deployment, per indexer and per deployment.
- **`qos_indexer_attempt`** / **`qos_query_result`** - the typed five-minute rows everything above is
  built from.

What each view computes is in `semantic.toml`. The arithmetic, which is where the old Lodestar card went
wrong:

- Every rate is a ratio of sums, never a mean of rates.
- Latency and blocks behind are weighted by queries. The oracle's average behaves as if it includes
  failed responses; weighting by 200s moved 99 of 374 indexer-days by more than 20%.
- A day is the UTC day of the bucket's **start**. The publisher's `timestamp` is the bucket's end, and
  dating by it files the 23:55 bucket under the next day.
- A bad bucket has at least 50 queries and under 90% success, counted per indexer across its
  allocations. A daily rate hides these: Ellipfra read 97.36% for 2026-09-06..12 while one bucket
  served 0 of 52,286.
- A bucket published twice counts once, from its first document.
- Seconds behind uses kittiwake's block-time table and its cohort rule (credible at 100 queries, a
  floor needs three credible peers). A chain with no known block time has no seconds figure.

## Gaps in the source

These are gaps in Edge & Node's data, not in this nest, and they read as gaps rather than zeros:

- From 2026-07-29, about 38 hours with no postings.
- From 2026-08-04, 37 hours or more with no postings.
- In 2026-09-06..12, two indexer-attempt buckets and five query-result buckets were never posted.

The publisher resumed from the tip each time without backfilling.

## What is not finished

- **Verification.** Every document is over nuthatch's 256 KiB single-block limit, so every row is
  stored `verified = false`: the bytes came from the gateway and have not been proven against the CID.
  `qos_settings.require_verified` is the switch to require verification once nuthatch can verify
  multi-block documents.
- **Publisher filter.** Top-level call rows do not carry the sender yet, so the nest accepts every
  `submitQoSPayload`, whoever sent it. The filter is written and waiting in `pending/publisher-filter.sql`.
- **Completeness.** The resolver fetches at most 64 documents per window and never retries one that
  fails. `[extract] blocks = true` caps the window at 800 blocks, about 27 documents, which keeps a run
  inside the budget at today's cadence (0 budget hits over 17,500 blocks, measured). A transient gateway
  error still loses a document for good: on 2026-09-13 the 00:10 bucket of 2026-09-07
  (`QmYTFznQSTJAXMJ9zJi2dHQyDs9oGAUESfhwvUUdcvrTgk`) failed with "reading response body", was never
  asked for again, and that one missing bucket changes the day's figures for 49 of 56 indexers. The
  out-of-band resolver with retries fixes both.
- **`--seal-direct`** does not decode top-level calls or resolve documents. Do not backfill this nest
  with it.
- **Query memory.** Views recompute over the stored JSON on every query, and one day of it does not fit
  nuthatch's default 512 MB analytics budget: `qos_indexer_daily` for one day is refused at the default
  and takes 0.97 s and 3.86 GB peak resident memory with `NUTHATCH_ANALYTICS_MEMORY_LIMIT=8GB` (measured
  on about 1.1 days of documents). Serving 90 days this way will not work; the daily rollups need to be
  kept rather than recomputed.

## Checks

`checks/parity-2026-09-07.sql` compares `qos_indexer_daily` for 2026-09-07 with figures computed straight
from that day's 288 raw documents by `scripts/parity-reference.py`, which shares no code with the views.
Counts, buckets and the worst bucket must match exactly; rates and fees to 1e-9 relative. Expect zero
rows. The check needs every document for the day resolved and a raised analytics memory limit (see above).

Run on 2026-09-13 over blocks 48,119,000 to 48,136,546 (544 s, 596 calls, 260 MB hot store plus 53 MB
sealed): 575 of 576 documents for the day resolved, and 287 of them byte-identical to independently
fetched copies. Against a reference built from the same 287 documents, all 56 indexers matched: counts,
buckets, bad buckets and the worst bucket exactly, rates and fees within 1.1e-14 relative. The committed
check still fails on that run, correctly, because of the missing bucket.

`pending/` holds SQL that is written but not loaded, each file saying what it waits for.
