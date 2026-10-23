# Equal Lottery ticket normalization

When Equal mode begins (or is restored), wait for pending ticket writes, refund
and remove undersized tickets using the existing policy, and reduce every
oversized ticket to the required value. The reduction does not credit the
forfeited excess to the player. Only `ticket_value` changes: ticket characters,
identity, display name and creation time are preserved, including offline
players' tickets. Exact-value tickets remain unchanged.

All three database changes share the existing refund transaction. Do not skip
the transaction when there are no undersized tickets: oversized tickets still
need normalization. The transaction is idempotent when restored after a reload.
The existing mutation/draw guard stays active until commit; pool requests now
also respect it. Successful completion reloads all connected ticket caches.
Ticket displays use the stored value rather than masking an unconverted stake
with the Equal value. The prize pool and draw already sum stored ticket values,
so they automatically reflect the reduction.

## Isolated regression probe

```sh
bash tools/tests/build_lottery_equal_probe.sh
```

Load the output once on MGE, check the `[LotteryEqualProbe]` summary, then
unload it. The probe extracts the actual production normalization and success
callbacks and runs their transaction against a dedicated SQLite database named
`lottery_equal_regression`. It never opens a configured database or accesses
real clients, balances, ticket characters, sounds, or chat.

Cases cover mixed undersized/exact/oversized tickets, oversized-only tickets,
exact-only tickets, an empty lottery, required values 100/340/680, a repeated
conversion, offline tickets, stale callbacks, character/metadata preservation,
no excess refunds, client cache reloads, pool totals, and other-lottery isolation.
After unloading, remove only the probe's `data/sqlite/lottery_equal_regression.sq3`
and any SQLite journal sidecars if present. The probe tests SQLite execution;
the MySQL branch retains its existing refund UPSERT, and the new value-only
UPDATE uses SQL common to both supported drivers.
