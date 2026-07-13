# Appends our auth + TLS overrides to the image's default /etc/scylla/scylla.yaml
# (preserving its ~620 lines of defaults). The keys we set exist only as
# comments in the default, so appending them introduces no duplicate keys.
# Baking it into the image means the entrypoint's runtime edits happen on the
# container's own copy and never touch the host repo file.
ARG SCYLLA_VERSION=2026.2
FROM scylladb/scylla:${SCYLLA_VERSION}
COPY scylla.yaml /tmp/scylla-overrides.yaml
RUN printf '\n' >> /etc/scylla/scylla.yaml \
    && cat /tmp/scylla-overrides.yaml >> /etc/scylla/scylla.yaml \
    && rm /tmp/scylla-overrides.yaml
