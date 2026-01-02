#!/bin/bash
# Restore original project.yml after CI (disable tests again)

set -e

PROJECT_YML="project.yml"
BACKUP_YML="project.yml.ci_backup"

if [ -f "$BACKUP_YML" ]; then
    echo "🔄 Restoring original project.yml..."
    mv "$BACKUP_YML" "$PROJECT_YML"
    echo "✅ Restored"
else
    echo "⚠️  No backup found, skipping restore"
fi

