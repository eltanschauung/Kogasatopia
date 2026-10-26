# Equal Lottery ticket normalization

When Equal mode begins (or is restored), wait for pending ticket writes, refund
and remove undersized tickets using the existing policy, and reduce every
oversized ticket to the required value, refunding the difference to its owner.
Only `ticket_value` changes: ticket characters,
identity, display name and creation time are preserved, including offline
players' tickets. Exact-value tickets remain unchanged.

All four database changes share the existing refund transaction: record durable
refund receipts in `points_store_idempotent_awards`, credit balances, remove
undersized tickets, then normalize oversized tickets. Receipt keys identify the
lottery, ticket ID, creation time, old value and required value. Duplicate receipts
roll back the entire conversion, not just its credit. Do not skip
the transaction when there are no undersized tickets: oversized tickets still
need normalization. The transaction is idempotent when restored after a reload.
The existing mutation/draw guard stays active until commit; pool requests now
also respect it. Successful completion reloads all connected ticket caches.
Connected balances are reloaded from the committed database rather than blindly
adding amounts selected before another server may have normalized the same rows.
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
excess refunds, durable receipts, client cache reloads, pool totals, and other-lottery isolation.
After unloading, remove only the probe's `data/sqlite/lottery_equal_refund_regression.sq3`
and any SQLite journal sidecars if present. The probe tests SQLite execution;
the MySQL branch uses the same conditional refund calculation with its native
UPSERT and CONCAT syntax. SQL-format fixtures should validate that branch too.
