#!/bin/bash
# A nightly copy of the CashStack database: pg_dump, encrypted with age to a
# public key on the way out (the plain dump never touches disk), uploaded to
# an S3 bucket in Sydney. Whoever holds the bucket can't read the backups;
# only the age identity, kept offline, can. A failure alerts ALERT_WEBHOOK_URL.
#
# Needs: DATABASE_URL, BACKUP_AGE_RECIPIENT (age1…), BACKUP_BUCKET, and the
# AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY of a key that can only write to it.
# Optional: AWS_REGION (ap-southeast-2), BACKUP_PREFIX (cashstack),
# BACKUP_S3_ENDPOINT for an S3-compatible store other than AWS.
set -euo pipefail

fail() {
  local message="CashStack database backup failed: $1"
  echo "$message" >&2
  if [[ -n ${ALERT_WEBHOOK_URL:-} ]]; then
    curl -fsS -m 10 -H 'content-type: application/json' -d "{\"text\":\"$message\"}" "$ALERT_WEBHOOK_URL" >/dev/null || true
  fi
  exit 1
}

for name in DATABASE_URL BACKUP_AGE_RECIPIENT BACKUP_BUCKET; do
  [[ -n ${!name:-} ]] || fail "$name is not set"
done

region=${AWS_REGION:-ap-southeast-2}
key="${BACKUP_PREFIX:-cashstack}/$(date -u +%Y/%m)/$(date -u +%Y-%m-%dT%H%M%SZ).dump.age"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
endpoint=()
[[ -n ${BACKUP_S3_ENDPOINT:-} ]] && endpoint=(--endpoint-url "$BACKUP_S3_ENDPOINT")

pg_dump --format=custom --no-owner --no-privileges "$DATABASE_URL" \
  | age --encrypt --recipient "$BACKUP_AGE_RECIPIENT" --output "$work/backup.dump.age" \
  || fail "couldn't dump and encrypt the database"

# An encrypted empty dump is still a few hundred bytes; a real one is more.
size=$(wc -c < "$work/backup.dump.age" | tr -d ' ')
(( size > 1024 )) || fail "the dump came out at $size bytes"

aws s3 cp "$work/backup.dump.age" "s3://$BACKUP_BUCKET/$key" --region "$region" ${endpoint[@]+"${endpoint[@]}"} --only-show-errors \
  || fail "couldn't upload to s3://$BACKUP_BUCKET"

echo "Backed up $size bytes to s3://$BACKUP_BUCKET/$key"
