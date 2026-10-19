# The nightly backup job (backup.sh), run by a scheduled Fly Machine in
# Sydney. pg_dump must be the same major version as the database or newer.
FROM postgres:17-alpine
RUN apk add --no-cache bash age aws-cli curl
COPY backup.sh restore.sh /usr/local/bin/
USER postgres
CMD ["backup.sh"]
