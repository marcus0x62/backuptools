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
export ROTATE_FILE=/mnt/backup/ROTATE
export DAYS=90

find_days=$(expr ${DAYS} - 1)

if [ ! -e ${ROTATE_FILE} ]; then
    echo "***ERROR*** Cannot determine rotation time: ${ROTATE_FILE} does not exist"
    exit 1
fi

find ${ROTATE_FILE} -daystart -mtime +${find_days} -exec false {} +
if [ $? -eq 1 ]; then
    echo "Time to rotate your backup drive!"
    echo "The current timestamp: $(stat -c '%y' ${ROTATE_FILE})"
fi
