# Demo cleanup

Install as root:

```sh
install -o root -g root -m 0755 tools/cleanup_demos.py /usr/local/sbin/kogasatopia-cleanup-demos
install -o root -g root -m 0755 tools/publish_demos.py /usr/local/sbin/kogasatopia-publish-demos
install -d -o root -g root -m 0700 /var/lib/kogasatopia-demo-cleanup
install -o root -g root -m 0644 tools/cron/kogasatopia-demos /etc/cron.d/kogasatopia-demos
```

The hourly cron checks a persistent timestamp and runs cleanup once daily.
Only closed `.dem` and `.dem.bz2` recordings at least 14 days old are deleted
from the TF2 server and FastDL demos directory. Age is measured from last write,
so a recently completed recording gets two full weeks of retention.
Open recordings are preserved until a later cleanup. Root execution lets `lsof`
inspect all processes and permits deleting recordings regardless of file owner.
If the open-file check fails, no recordings are deleted and the timestamp stays
unchanged. Map files, assets and database records are not modified.

Remove the obsolete user-crontab deletion and daily FastDL copy jobs.
The minute publisher moves completed recordings from the TF2 directory to
FastDL; it never copies their contents or changes match-log rows. It requires
both directories to share a filesystem (as on this VPS), checks open files
with root lsof, requires finalized Source demo-header playback totals and
30 seconds without writes, and shares the retention job's lock. Invalid,
unfinished, open and recent recordings remain on the server.

Publication uses hard-link + unlink: the complete download appears atomically,
existing filenames are never overwritten, and the server copy is removed.
An interrupted move is resumed safely on the next run. Original mtime is
preserved for retention and files are made mode 0644 for HTTP downloads.
Errors go to /var/log/kogasatopia-demo-publish.log.
Use `sudo /usr/local/sbin/kogasatopia-publish-demos --dry-run` to preview.
Use `sudo /usr/local/sbin/kogasatopia-cleanup-demos --force --dry-run` to preview,
or omit `--dry-run` to run immediately. Normal cron output goes to
`/var/log/kogasatopia-demo-cleanup.log`.

Run regression tests with `python3 tools/test_cleanup_demos.py`.
Also run `python3 tools/test_publish_demos.py`.
