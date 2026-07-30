#!/bin/zsh
# Point-in-time recovery needs Blaze billing on pismenka-app.
# After enabling billing at:
#   https://console.developers.google.com/billing/enable?project=pismenka-app
# run:
set -euo pipefail
gcloud firestore databases update \
  --database='(default)' \
  --project=pismenka-app \
  --enable-pitr
gcloud firestore databases describe \
  --database='(default)' \
  --project=pismenka-app \
  --format='yaml(pointInTimeRecoveryEnablement,versionRetentionPeriod)'
