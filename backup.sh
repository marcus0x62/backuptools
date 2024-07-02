#!/usr/bin/env bash
#
# MIT License
#
# Copyright (c) 2023-2024 Marcus Butler
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export LOG=$(mktemp)

function log_msg
{
    msg=$(printf "\n%s %s\n" "$(date)" "$*")

    if test $SHOW_OUTPUT = "true"; then
        echo $msg |& tee -a ${LOG}
    else
        echo $msg >> ${LOG}
    fi
}

function log_pipe
{
    msg=$(printf "\n%s \n" "$(date)")

    if test $SHOW_OUTPUT = "true"; then
        echo ${msg} |& tee -a ${LOG}
        while IFS= read -r line; do
            echo ${line} |& tee -a ${LOG}
        done
    else
        echo ${msg} >> ${LOG}
        while IFS= read -r line; do
            echo ${line} >> ${LOG}
        done
    fi
}

trap 'echo $( date ) Backup interrupted >&2; exit 2' INT TERM

if [ ! -f '/etc/backup-settings' ]; then
    info "/etc/backup-settings does not exist; aborting backup"
    rm ${LOG}
    exit 1
fi

if [ ! -f '/etc/backup-exclusions' ]; then
    info "/etc/backup-exclusions does not exist; aborting backup"
    rm ${LOG}
    exit 1
fi

. /etc/backup-settings

# Perform Borg backup
log_msg "Starting Borg backup"

borg create --verbose --filter AME --list --stats --show-rc --compression lz4 \
     --exclude-caches --exclude-from /etc/backup-exclusions \
     \
     ::'{hostname}-{now}' \
     /etc /home /root /var |& log_pipe

borg_exit=$?

# Perform Restic backup
log_msg "Starting Restic backup"

# Unlock the repo; this shouldn't be necessary, but I've noticed Restic leaving dangling
# locks in place.
restic -o rclone.program='ssh restic-backup forced-command' -r rclone: unlock |& log_pipe

restic -o rclone.program='ssh restic-backup forced-command' -r rclone: backup --verbose \
    --exclude-file=/etc/backup-exclusions --exclude-caches=true /etc /home /root /var |& log_pipe

global_exit=$(( borg_exit > restic_exit ? borg_exit : restic_exit ))

if [ ${global_exit} -ne 0 ]; then
    log_msg "Backup finished with errors: Borg exit ${borg_exit}, Restic exit ${restic_exit}"
    cat ${LOG}
fi

rm ${LOG}

exit ${global_exit}
