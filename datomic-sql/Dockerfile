FROM clojure:latest

ENV DATOMIC_VERSION="1.0.6733"
ENV DATOMIC_PATH="/opt/datomic-pro-${DATOMIC_VERSION}"

RUN apt-get update -y && \
    apt-get install unzip -y

RUN curl https://datomic-pro-downloads.s3.amazonaws.com/${DATOMIC_VERSION}/datomic-pro-${DATOMIC_VERSION}.zip -O \
    && unzip datomic-pro-${DATOMIC_VERSION}.zip -d /opt \
    && rm datomic-pro-${DATOMIC_VERSION}.zip

COPY ./sql-transactor-template.properties $DATOMIC_PATH/config

WORKDIR ${DATOMIC_PATH}

EXPOSE 4334 4335 4336

CMD ["./bin/transactor", "config/sql-transactor-template.properties"]