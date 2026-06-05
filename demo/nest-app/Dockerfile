# Use a base image with Node.js installed
FROM node:24 AS builder

# Set the working directory
WORKDIR /app

# Copy the rest of the application source code

COPY package*.json ./

RUN npm ci

COPY . ./

RUN npm run build

# Use a minimal base image for the production environment
FROM node:24

# Set the environment variable for Vault address
ARG VAULT_ADDR="https://knox.io.nrs.gov.bc.ca"
ENV VAULT_ADDR=$VAULT_ADDR
ARG VAULT_VERSION=1.18.5

RUN apt-get update && apt-get install -y --no-install-recommends jq curl unzip && \
    rm -rf /var/lib/apt/lists/*

# Install Vault CLI (used for vault agent auth and secret retrieval)
ADD https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip /tmp/vault.zip
RUN unzip /tmp/vault.zip && \
    rm /tmp/vault.zip && \
    mv vault /usr/local/bin/

# Set the working directory
WORKDIR /app


# Copy the built application from the builder stage
COPY --from=builder /app/package*.json ./
COPY --from=builder /app/dist ./dist
COPY ./docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# Install production dependencies
RUN npm ci --omit=dev

RUN chmod +x /usr/local/bin/docker-entrypoint.sh

VOLUME /config/vault-agent
VOLUME /vault/approle
VOLUME /vault/secrets

# Expose the desired port
EXPOSE 3600

# Run Vault Agent login, fetch secrets, and start the NestJS application
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]