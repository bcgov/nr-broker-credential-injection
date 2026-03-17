# Use a base image with Node.js installed
FROM node:22 AS builder

RUN npm i -g @nestjs/cli

# Set the working directory
WORKDIR /app

# Copy the rest of the application source code

COPY package*.json ./

RUN npm install

COPY . ./

RUN npm run build

# Use a minimal base image for the production environment
FROM node:22

# Set the environment variable for Vault address
ARG VAULT_ADDR="https://vault-iit.apps.silver.devops.gov.bc.ca"
ENV VAULT_ADDR=$VAULT_ADDR
ARG ENVCONSUL_VERSION=0.13.1

# Install envconsul to unwrap the token and fetch secrets from Vault during runtime
ADD https://releases.hashicorp.com/envconsul/${ENVCONSUL_VERSION}/envconsul_${ENVCONSUL_VERSION}_linux_amd64.zip /tmp/envconsul.zip
RUN unzip /tmp/envconsul.zip && \
    rm /tmp/envconsul.zip && \
    mv envconsul /usr/local/bin/

RUN apt-get update && apt-get install -y jq curl

# Set the working directory
WORKDIR /app


# Copy the built application from the builder stage
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package*.json ./
COPY --from=builder /app/env.hcl /config/envconsul/env.hcl

# Install production dependencies
RUN npm install --only=prod

VOLUME /config/envconsul
VOLUME /config/token

# Expose the desired port
EXPOSE 3600

# Set the entrypoint command to use envconsul and start the NestJS application
ENTRYPOINT ["envconsul", "-f", "/config/envconsul/env.hcl", "node", "dist/main"]