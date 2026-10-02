# Mail delivery bans

`sm_mailban <target>` silently suppresses new mail to and from the target.
`sm_mailunban <target>` restores future delivery. Neither notifies the target
or interrupts their composition, mailbox, or redemption commands.

The shared insert path checks both Steam IDs against `mail_bans` in SQL.
This covers offline players, other servers, native API sends, and stimulus
checks without relying on a connected client's ban cache.

Suppressed requests retain their sender-visible sent-mail record and ordinary
confirmation. Normal gift costs and cooldowns still apply. The persistent
`delivery_suppressed` flag excludes them from recipient lists, notifications,
unread reminders, and attachment/currency redemption. Unbanning does not
release previously suppressed mail. Existing delivered mail remains available.

API results still describe successful storage, not delivery: suppressed
requests retain real IDs and idempotency keys, preventing duplicate charges
and stimulus retries.

Run `python3 tools/tests/test_mail_delivery.py` for SQLite regressions. Add
`--mysql` on the VPS to check MariaDB using temporary tables only.
