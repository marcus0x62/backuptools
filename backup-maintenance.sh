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
# This script performs a few different maintenance tasks on your backup
# repositories:
#
# 1) It marks old snapshots for deletion, keeping the most recent:
#    24 hourly snapshots
#    7 daily snapshots
#    4 weekly snapshots
#    12 monthly snapshots
#    1 yearly snapshot
# 2) Deleting old snapshots that have been marked for deletion.
# 3) Checking the integrity of your backup repos, identifying (but not
#    automatically repairing) potential errors.
# 4) Ensuring that each system has performed at least one backup in the last
#    n days, defaulting to 1 day.
#
# Any exceptions are written the stdout; the intent of this script is to run it
# from cron or a similar system where any output will trigger an email to the
# admin.
#
# PLEASE NOTE: THE KEYS THIS SCRIPT USES CAN BE USED TO DELETE OR CORRUPT YOUR
# BACKUPS.
#
# IF YOU CARE ABOUT APPEND-ONLY BACKUPS, YOU MUST ENSURE THAT THE UNRESTRICTED
# SSH KEYS THIS SCRIPT USES ARE NOT INSTALLED ON THE SYSTEMS YOU ARE BACKING UP,
# AND ARE NOT NORMALLY ACCESSIBLE FROM ANY DEVICE THAT AN ATTACKER COULD
# REASONABLY ACCESS.  IN PRACTICE, THAT MEANS USING A DETACHABLE HARDWARE KEY
# (SUCH AS A YUBIKEY OR SIMILAR DEVICE) OR A HARDENED, DEDICATED SERVER.
#
# READ MORE HERE: https://marcusb.org/hacks/backuptools.html#maintenancehost

export PATH=/bin:/sbin:/usr/bin:/usr/sbin

export IDX=0

declare -a HOSTS
declare -a BORG_REPOS
declare -a BORG_PASS
declare -a RESTIC_HOSTS
declare -a RESTIC_PATHS
declare -a RESTIC_PASS
declare -a DAYS

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

function add
{
    HOSTS[${IDX}]=$1
    BORG_REPOS[${IDX}]=$2
    BORG_PASS[${IDX}]=$3
    RESTIC_REPOS[${IDX}]=$4
    RESTIC_PASS[${IDX}]=$5

    if [ -z $6 ]; then
        DAYS[${IDX}]=1
    else
        DAYS[${IDX}]=$6
    fi

    IDX=$(expr ${IDX} + 1)
}

. backup-maintenance-settings

for i in $(seq 0 $(expr ${IDX} - 1)); do
    export LOG=$(mktemp)

    export BORG_REPO=${BORG_REPOS[${i}]}
    export BORG_PASSPHRASE=${BORG_PASS[${i}]}
    export RESTIC_PASSWORD=${RESTIC_PASS[${i}]}

    export restic_host=$(echo ${RESTIC_REPOS[${i}]}|cut -f 1 -d ':')
    export restic_path=$(echo ${RESTIC_REPOS[${i}]}|cut -f 2 -d ':')

    export current_days=${DAYS[${i}]}
    export current_host=${HOSTS[${i}]}

    # With Borg, we need to first prune (mark for deletion,) then compact (delete)
    # old snapshots
    borg prune -v --list -H 24 -d 7 -w 4 -m 12 -y 1 |& log_pipe
    borg_prune=$?

    borg compact -v |& log_pipe
    borg_compact=$?

    # Check the repo for consistency
    borg check -v |& log_pipe
    borg_check=$?

    # With Restic, we can forget (mark for deletion) and prune (delete) with a
    # single command
    restic -o rclone.program="ssh ${restic_host} rclone" \
           -o rclone.args="serve restic --stdio ${restic_path}" \
           -r rclone: forget -H 24 -d 7 -w 4 -m 12 -y 1 --prune=true -v \
           |& log_pipe
    restic_prune=$?

    # Check the repo for consistency
    restic -o rclone.program="ssh ${restic_host} rclone" \
           -o rclone.args="serve restic --stdio ${restic_path}" \
           -r rclone: check -v |& log_pipe
    restic_check=$?

    borg_backups=0
    restic_backups=0

    # In the output of the borg prune and restic forget actions, we get a list of
    # snapshots. We'll use that to make sure the host has created at least one
    # backup in the last n days (defaults to 1.)  From a practical standpoint,
    # "1 day" really means "today and yesterday". This could be extended to match
    # on the full timestamp, but this is much easier and is adequate for my
    # purposes.
    for j in $(seq 0 ${current_days}); do
        current_date=$(date -d "${j} days ago" +"%Y-%m-%d")

        n=$(grep " archive (" ${LOG}|grep "${current_date}"|wc -l)
        log_msg "Found $n borg backups for $j days ago"
        borg_backups=$(expr ${borg_backups} + ${n})

        m=$(grep " snapshot " ${LOG}|grep "${current_date}"|wc -l)
        log_msg "Found $m restic backups for $j days ago"
        restic_backups=$(expr ${restic_backups} + ${m})
    done

    state='NORMAL'

    if [ ${borg_prune} -ne 0 ] || [ ${borg_compact} -ne 0 ] || \
       [ ${restic_prune} -ne 0 ] || [ ${restic_check} -ne 0 ] || \
       [ ${borg_backups} -lt 1 ] || [ ${restic_backups} -lt 1 ]; then
        state='ERROR'
    fi

    log_msg "Overall status for ${current_host}: ${state}"
    log_msg "Borg exit codes: prune ${borg_prune} compact ${borg_compact} check ${borg_check}"
    log_msg "Restic exit codes: prune ${restic_prune} check: ${restic_check}"
    log_msg "Total snapshots found: Borg ${borg_backups} Restic ${restic_backups}"

    # Always show the log if there was an error.
    if test $state = 'ERROR'; then
        cat ${LOG}
    fi

    rm ${LOG}
done
