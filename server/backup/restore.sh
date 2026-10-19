#!/bin/bash
# Restore a backup made by backup.sh into a database — for real, or as the
# monthly drill into a scratch one. Never point it at production unless that's
# what you mean: it replaces what's there.
#
#   restore.sh latest postgres://…scratch…
#   restore.sh cashstack/2026/10/2026-10-19T150000Z.dump.age postgres://…
#
# Needs BACKUP_BUCKET, BACKUP_AGE_IDENTITY (the path to the age identity file,
# kept offline) and AWS credentials that can read the bucket.
set -euo pipefail

which=${1:?usage: restore.sh latest|<key> <database-url>}
target=${2:?usage: restore.sh latest|<key> <database-url>}
: "${BACKUP_BUCKET:?}" "${BACKUP_AGE_IDENTITY:?}"
region=${AWS_REGION:-ap-southeast-2}
endpoint=()
[[ -n ${BACKUP_S3_ENDPOINT:-} ]] && endpoint=(--endpoint-url "$BACKUP_S3_ENDPOINT")

if [[ $which == latest ]]; then
  # Keys sort by time, so the last one listed is the newest.
  which=$(aws s3 ls "s3://$BACKUP_BUCKET/${BACKUP_PREFIX:-cashstack}/" --recursive --region "$region" ${endpoint[@]+"${endpoint[@]}"} \
    | awk '{ print $4 }' | grep '\.dump\.age$' | sort | tail -1)
  [[ -n $which ]] || { echo "No backups in s3://$BACKUP_BUCKET" >&2; exit 1; }
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
echo "Restoring s3://$BACKUP_BUCKET/$which"
aws s3 cp "s3://$BACKUP_BUCKET/$which" "$work/backup.dump.age" --region "$region" ${endpoint[@]+"${endpoint[@]}"} --only-show-errors
age --decrypt --identity "$BACKUP_AGE_IDENTITY" "$work/backup.dump.age" \
  | pg_restore --clean --if-exists --no-owner --no-privileges --dbname "$target"

# Enough to tell a real restore from an empty one.
psql "$target" --no-psqlrc --tuples-only --command \
  "select 'users ' || count(*) from users
   union all select 'sessions ' || count(*) from sessions
   union all select 'audit_log ' || count(*) from audit_log
   union all select 'migrations ' || string_agg(version, ', ' order by version) from schema_migrations"
