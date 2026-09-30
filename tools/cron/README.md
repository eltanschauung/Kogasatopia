# Demo cleanup

Install as root:

```sh
install -o root -g root -m 0755 tools/cleanup_demos.py /usr/local/sbin/kogasatopia-cleanup-demos
install -d -o root -g root -m 0700 /var/lib/kogasatopia-demo-cleanup
install -o root -g root -m 0644 tools/cron/kogasatopia-demos /etc/cron.d/kogasatopia-demos
```

The hourly cron checks a persistent timestamp and deletes closed `.dem` and
`.dem.bz2` recordings every 72 hours from the TF2 server and FastDL demos directory.
Open recordings are preserved until a later cleanup. Root execution lets `lsof`
inspect all processes and permits deleting recordings regardless of file owner.
If the open-file check fails, no recordings are deleted and the timestamp stays
unchanged. Map files, assets and database records are not modified.

Remove the obsolete user-crontab job that deletes demos after 14 days. The daily
FastDL copy job can remain: its exported copies are covered by this cleanup.
Use `sudo /usr/local/sbin/kogasatopia-cleanup-demos --force --dry-run` to preview,
or omit `--dry-run` to run immediately. Normal cron output goes to
`/var/log/kogasatopia-demo-cleanup.log`.

Run regression tests with `python3 tools/test_cleanup_demos.py`.
