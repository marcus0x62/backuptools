Backuptools

These are my personal backup scripts. I use them to manage append-only backups using Borg and Restic.  Append-only backups
-- theoretically at least -- only allow uploading new snapshots from the systems being backed up.  When implemented
properly, it should not be possible to delete (or alter) old snapshots from the systems being backed up.  This should allow
for some resistance against my backups being deleted by, say, a ransomware infection.  Like most of infosec, the devil is
in the details, and there are a bunch of things you have to get right for this to work out in practice. I've written more
about that [here](https://marcusb.org/hacks/backuptools.html).
