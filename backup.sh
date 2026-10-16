#!/bin/bash

LOG_DIR="$1"
N="${2:-80}"
M="${3:-5}"
BACKUP_DIR="Backup"

if [ -z "$LOG_DIR" ]; then
    echo "Usage: $0 <path_to_log_directory>"
    exit 1
fi

if [ ! -d "$LOG_DIR" ]; then
    echo "Error: '$LOG_DIR' is not a directory"
    exit 1
fi

echo "Working with directoty: $LOG_DIR"

USED=$(df --output=pcent "$LOG_DIR" | tail -1 | tr -d ' %')
echo "Used: $USED%"

if [ "$USED" -gt "$N" ]; then
    echo "Usage $USED% is above threshold $N%, archiving $M oldest files"

    FILES=$(find "$LOG_DIR" -maxdepth 1 -type f -printf '%T@ %f\n' | sort -n | head -n "$M" | cut -d' ' -f2-)

    if [ -z "$FILES" ]; then
        echo "No files to archive"
        exit 0
    fi

    echo "Files selected for archiving:"
    echo "$FILES"

    mkdir -p "$BACKUP_DIR"
    ARCHIVE="$BACKUP_DIR/backup_$(date +%Y%m%d_%H%M%S).tar.gz"

    if echo "$FILES" | tar -czf "$ARCHIVE" -C "$LOG_DIR" -T -; then
        echo "Archive created: $ARCHIVE"

        while IFS= read -r f; do
          rm -- "$LOG_DIR/$f"
        done <<< "$FILES"

        echo "Original files removed from $LOG_DIR"
    else
        echo "Error: archiving failed"
        exit 1
    fi
else
    echo "Usage $USED% is within threshold $N%, nothing to do"
fi
