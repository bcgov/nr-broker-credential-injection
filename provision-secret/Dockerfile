FROM docker.io/library/alpine:3.21
RUN apk --no-cache add bash curl jq kubectl
ARG BROKER_ADDR="https://broker.io.nrs.gov.bc.ca"
ARG VAULT_ADDR="https://knox.io.nrs.gov.bc.ca"
ENV BROKER_ADDR=$BROKER_ADDR
ENV VAULT_ADDR=$VAULT_ADDR

RUN adduser -D broker && mkdir /broker && chown broker:broker /broker

COPY --chown=broker:broker ./src/sync-approle-secrets.sh /broker
COPY --chown=broker:broker ./src/sync-vault-secrets.sh /broker
RUN chmod +x /broker/sync-approle-secrets.sh /broker/sync-vault-secrets.sh
VOLUME /broker/config
VOLUME /broker/output
WORKDIR /broker
USER broker
ENTRYPOINT ["./sync-approle-secrets.sh"]