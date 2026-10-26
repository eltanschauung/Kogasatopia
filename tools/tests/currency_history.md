# Cached currency leaderboard history

`sm_gl` still serves its existing cached top 50 and retains the existing map/population
refresh policy. Only successful, current-generation refreshes enqueue an archive;
opening the leaderboard does not query or write SQL. The archive contains the exact
cached SteamID64/balance pairs, not a later re-read of all accounts.

One indexed table, `points_store_balance_history`, retains every nonempty refresh:

- `snapshot_id`: unique grouping key, also making retries idempotent.
- `snapshot_date`: `YYYY-MM-DD` in the server's local timezone.
- `captured_at`: Unix seconds, permitting timezone-independent analysis.
- `host_port`: distinguishes servers sharing the database.
- `steamid64`, `balance`: the cached result for that player.

Primary key is `(snapshot_id, steamid64)`; indexes support date/time and client/time
lookups. Earlier snapshots are never overwritten. There is no automatic retention
deletion. This is top-50 snapshot history, not a complete monetary transaction ledger.
The first archive is created after the updated plugin loads and refreshes its cache;
the feature cannot reconstruct missing past balances or silently backdate them.

The writer lazily initializes schema once, sends one asynchronous bulk INSERT per
refresh, and retries failed jobs after 30 seconds, across map changes. Up to 64 frozen
snapshots queue in memory; overflow and unload with pending jobs are logged rather
than silently claiming success. A process crash/restart can lose uncommitted jobs.

## Tests

`bash tools/tests/build_currency_history_probe.sh` compiles the actual writer into a
probe using only `currency_history_regression` SQLite, never a configured database.
It exercises schema/index creation, exact cache values, multiple dated snapshots,
duplicate payloads, failed-write preservation, retry, and empty results. Load only
on a test server, then unload and remove its dedicated fixture/artifact.

Also compile the production plugin and existing leaderboard probes. No production
reload is required to build or deploy; activation can wait for the owner's next reload.
