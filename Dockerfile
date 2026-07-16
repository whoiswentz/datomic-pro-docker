FROM eclipse-temurin:17-jre-jammy

ARG DATOMIC_VERSION=1.0.7705
ENV DATOMIC_VERSION=${DATOMIC_VERSION}
ENV DATOMIC_HOME=/opt/datomic-pro-${DATOMIC_VERSION}

RUN apt-get update && apt-get install -y --no-install-recommends \
      unzip curl gettext-base ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fSL "https://datomic-pro-downloads.s3.amazonaws.com/${DATOMIC_VERSION}/datomic-pro-${DATOMIC_VERSION}.zip" \
      -o /tmp/datomic.zip \
    && unzip -q /tmp/datomic.zip -d /opt \
    && rm /tmp/datomic.zip

COPY config/cass3-transactor.properties.tmpl /opt/templates/transactor.properties.tmpl
COPY scripts/entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

# Run as a non-root user. It owns DATOMIC_HOME so the entrypoint can render the
# properties file and the transactor can write logs there.
# USER must be numeric: Kubernetes' runAsNonRoot check reads the image's user
# field and cannot resolve a name to a UID, so `USER datomic` would be rejected.
RUN groupadd -r -g 1001 datomic \
    && useradd -r -u 1001 -g 1001 -m -d /home/datomic datomic \
    && chown -R datomic:datomic ${DATOMIC_HOME}
USER 1001:1001

WORKDIR ${DATOMIC_HOME}
EXPOSE 4334 4335 4336
ENTRYPOINT ["/opt/entrypoint.sh"]
