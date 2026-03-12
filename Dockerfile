FROM docker.io/library/alpine:3.21
RUN apk --no-cache add curl jq
ARG BROKER_URL="https://broker.io.nrs.gov.bc.ca"
ARG VAULT_ADDR="https://knox.io.nrs.gov.bc.ca"
ENV BROKER_URL=$BROKER_URL
ENV VAULT_ADDR=$VAULT_ADDR

RUN adduser -D broker && mkdir /broker && chown broker:broker /broker

COPY --chown=broker:broker ./src/get-vault-token.sh /broker
RUN chmod +x /broker/get-vault-token.sh
VOLUME /broker/config
VOLUME /broker/output
WORKDIR /broker
USER broker
ENTRYPOINT ["./get-vault-token.sh"]