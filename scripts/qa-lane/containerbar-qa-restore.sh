#!/bin/zsh
# ContainerBar QA lane restore (CB-105): the no-GUI part of the restore.
# Called by the pass at step 5, by the next pass's step 0 (--keep-marker) and by
# the hourly backstop. Needs no lock of its own: every caller already holds the
# shared desktop lock. Exit 0 restored, 1 failed (marker kept).
set -u
export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
exec "${CBQA_PYTHON:-/usr/bin/python3}" -B "${0:A:h}/cbqa_lane.py" restore "$@"
