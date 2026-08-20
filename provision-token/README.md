# NR Broker Token Injection Pattern

This pattern allows a pod to simply read a Vault token provisioned by an init container. The strength of this approach is that provisioning is tied to the startup of a pod: if there are no pods active, there are no active credentials. The main weakness is that the pod's startup must be modified to accomplish the initialization.

A technical issue with the way Kubernetes handles initialization (it does not re-initialize restarted pods) means this pattern is not recommended for long-lived pods like those in a Deployment or StatefulSet. Basically, a restarted pod ends up with an invalid token that doesn't work. This pattern is thus only recommended for situations (for example a CronJob) where you expect the pods to run to completion and exit.

## How It Works

The `intention-provision-token` image is run as an **init container**. It provisions a Vault token on pod startup and writes it to a shared volume so the main container can consume it.

The init container performs the following steps:

1. **Open an intention** with NR Broker using the service `BROKER_JWT` and the `intention.json` definition.
2. **Provision a `secret_id`** for the environment's AppRole and unwrap it.
3. **Log in to Vault** with the `role_id` and `secret_id` to obtain a Vault token.
4. **Write a wrapped Vault token** to `/broker/output/.vault-token` in the shared volume.
5. **End the action and close the intention.**

The main container then reads the wrapped token from the shared volume, unwraps it, and uses it to access Vault secrets.

## Prerequisites

- Access to an OpenShift namespace
- A Kubernetes Secret containing the Broker JWT and the Vault AppRole role ID
- The `intention-provision-token` image (built from this `./provision-token` directory)

The default source secret is `vault-secret` with keys:

- `role`: Vault AppRole role ID
- `token`: Broker JWT

## AppRole Setup

The AppRole needs to be setup specifically for this pattern to work. The CIDR restriction is recommended.

### Wrapped Token TTL

The init container logs into Vault with a `5m` wrap TTL, so the token written to `/broker/output/.vault-token` expires after 5 minutes. The main container must start and unwrap the token quickly. If the pod takes longer than 5 minutes to start its main container, the token will be invalid.

### Secret ID Usage

Because the provisioned `secret_id` is used once (to log into Vault) for each pod startup, the default usage limit of `1` is acceptable for this pattern. Unlike the [Pre-provisioning Secret Pattern](../provision-secret/README.md), the `secret_id` does not need to support multiple logins.

### Login CIDR Restriction

The per-environment AppRole login can be configured to only allow logins from an IP range (CIDR). This ensures that, even though the provisioned login credentials can be used, the logins are limited to an expected range. This range can be updated anytime without needing to re-provision.

Ideally, the configured CIDR will be unique to the service and environment. You will want to ensure your hosting option can provide this. In any case, this restriction isn't foolproof and other methods like audit log monitoring should be used to identify and investigate unusual logins.

## Intention Definition

The init container reads an intention definition from `/broker/config/intention.json` (mounted from a ConfigMap or Secret). A minimal example:

```json
{
   "event": {
      "provider": "token-injection-demo",
      "reason": "Pod startup",
      "url": "JOB_URL"
   },
   "actions": [
      {
         "action": "package-provision",
         "id": "provision",
         "provision": ["approle/secret-id"],
         "service": {
            "name": "nodejs-sample",
            "project": "nodejs-sample",
            "environment": "development"
         }
      }
   ],
   "user": {
      "name": "mbystedt@azureidir"
   }
}
```

The script overrides several fields from environment variables, so a static template can be reused across environments:

- `event.url` is replaced with `INTENTION_EVENT_URL`
- `user.name` is replaced with `INTENTION_USER` (only when provided)
- `actions[0].service.environment` is replaced with `INTENTION_ENVIRONMENT`

## Using the Image

The image is used as an init container that shares a volume with the main container. It requires a ConfigMap (or Secret) providing `intention.json` at `/broker/config` and a shared `emptyDir` volume mounted at both `/broker/output` (init container) and the consuming location of the main container.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: token-injection
spec:
  initContainers:
   - name: provision-token
    image: "ghcr.io/bcgov/nr-broker-credential-injection/intention-provision-token:1.0.0"
    imagePullPolicy: IfNotPresent
    volumeMounts:
       - name: intention-config
        mountPath: /broker/config
       - name: vault-token
        mountPath: /broker/output
    env:
       - name: BROKER_JWT
        valueFrom:
          secretKeyRef:
            name: vault-secret
            key: token
       - name: VAULT_ROLE_ID
        valueFrom:
          secretKeyRef:
            name: vault-secret
            key: role
       - name: INTENTION_EVENT_URL
        value: "https://example.com/event"
       - name: INTENTION_ENVIRONMENT
        value: "development"
  containers:
   - name: app
    image: "my-app:1.0.0"
    volumeMounts:
       - name: vault-token
        mountPath: /vault
        readOnly: true
    env:
       - name: VAULT_ADDR
        value: "https://knox.io.nrs.gov.bc.ca"
  volumes:
     - name: intention-config
      configMap:
        name: intention-config
     - name: vault-token
      emptyDir: {}
```

The init container writes the wrapped token to `/broker/output/.vault-token`, which the main container reads from `/vault/.vault-token` (the same `vault-token` volume).

## Consuming the Token

In the main container, read the wrapped token and unwrap it to obtain a live Vault token:

```sh
WRAPPED_TOKEN="$(cat /vault/.vault-token)"
UNWRAPPED=$(curl -s -X POST "$VAULT_ADDR/v1/sys/wrapping/unwrap" \
    -H "X-Vault-Token: $WRAPPED_TOKEN")
VAULT_TOKEN=$(echo "$UNWRAPPED" | jq -r '.auth.client_token')
```

Then use `VAULT_TOKEN` to retrieve secrets, for example:

```sh
curl -s "$VAULT_ADDR/v1/secret/data/myapp/config" -H "X-Vault-Token: $VAULT_TOKEN"
```

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `BROKER_URL` | No | `https://broker.io.nrs.gov.bc.ca` | NR Broker API base URL. |
| `VAULT_ADDR` | No | `https://knox.io.nrs.gov.bc.ca` | Vault base URL. |
| `BROKER_JWT` | Yes | — | The service Broker JWT. |
| `INTENTION_EVENT_URL` | Yes | — | Value used for `event.url` in the intention. |
| `INTENTION_ENVIRONMENT` | Yes | — | Value used for `actions[0].service.environment`. |
| `VAULT_ROLE_ID` | Yes | — | The environment's AppRole role ID. |
| `INTENTION_USER` | No | — | Optional override for `user.name` in the intention. |

## Build

The image is built from the `./provision-token` context. The `BROKER_URL` and `VAULT_ADDR` can be set as build args.

```bash
docker build -t intention-provision-token:1.0.0 \
    --build-arg BROKER_URL="https://broker.io.nrs.gov.bc.ca" \
    --build-arg VAULT_ADDR="https://knox.io.nrs.gov.bc.ca" \
    ./provision-token
```

## Best Practices

- **Use for short-lived pods.** This pattern is only recommended for pods that run to completion and exit (for example CronJobs). Do not use it for long-lived workloads such as Deployments or StatefulSets.
- **Start the main container quickly.** The wrapped token has a 5-minute TTL; the consuming container must unwrap it promptly.
- **Never share the JWT or role ID.** The `BROKER_JWT` and role ID must never be shared or added to source control.
