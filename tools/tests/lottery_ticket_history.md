# Durable lottery ticket journal

`points_store_lottery_ticket_history` is append-only history, independent of
`sm_points_store_event_logging`. It starts when the additive schema/triggers are
installed; it does not fabricate purchases for pre-existing tickets.

Database AFTER INSERT/UPDATE/DELETE triggers record actual ticket mutations in
the same transaction. Rollbacks roll back the history too. A journal-write error
rejects the ticket mutation; existing purchase/replacement failure paths remain
responsible for their existing refund/error handling. There is no new SourcePawn
callback, timer, SQL round trip, or frame hook per purchase.

Records include:

- Date and Unix timestamp, SteamID64, lottery ID, and ticket ID.
- Operation: `purchase`, `replace`, `equal_conversion`, `adjust`, or `remove`.
- Original/new stake, signed `stake_delta` (new minus old), and ticket timestamps.
- Equal-lottery flag/required value and the wallet's observed `balance_snapshot`.

`stake_delta` is **not** a wallet credit/debit: a ticket update may occur before
its wallet adjustment, and a removal may precede its refund. `balance_snapshot`
is the balance visible at trigger execution, not a promised final balance.
Equal conversion refunds have separate atomic receipts in
`points_store_idempotent_awards`. Together these preserve the facts needed to
investigate future conversions without relying on chat/debug logs.

No-op and name-only updates are ignored. History survives live ticket deletion,
disconnects and map changes. Lookup indexes cover client/time, date/time and
lottery/order. No automatic deletion or retention purge is installed.

Schema initialization is additive: existing triggers are not dropped/replaced.
On a fresh deployment, the schema can be installed without reloading plugins,
and already loaded purchase code is covered immediately. The plugin also ensures
the schema at startup before finishing store initialization; failures log and
retry after 30 seconds instead of accepting unaudited purchases. MySQL/MariaDB
requires a database account with TRIGGER permission and transactional InnoDB
tables. Both production monetary tables were verified as InnoDB before rollout.

## Validation

```sh
bash tools/tests/build_lottery_ticket_history_probe.sh
```

The SourcePawn probe executes the actual schema builders/bootstrap on its own
`lottery_ticket_history_regression` SQLite database. No configured connection,
real player or balance is used. It exports MySQL DDL to
`data/lottery_ticket_history_mysql.sql` for the second fixture:

```sh
python tools/tests/test_lottery_ticket_history_sql.py --mysql-export /path/to/export.sql
```

The latter requires local root socket authentication and creates/drops a uniquely
named disposable MariaDB test database, never a production database. Tests cover
purchases, replacements, equal conversions, removals, wallet observations, rollback,
journal failure rejecting a ticket, no-op updates and idempotent schema setup.
Compile the production plugin, unload the fixture, and remove its generated
SMX/SQLite/export artifacts after use.
