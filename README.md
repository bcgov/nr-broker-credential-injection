# nr-broker-credential-injection

Inject credentials from [HashiCorp Vault](https://www.vaultproject.io/) into OpenShift pods using [NR Broker](https://github.com/bcgov/nr-broker).

The created token can be consumed by a tool like [envconsul](https://github.com/hashicorp/envconsul) to provide credentials to the pod.

## How It Works

```
Pod startup
├── initContainer (get-vault-token.sh)
│   ├── Opens an intention with NR Broker
│   ├── Provisions an AppRole secret-id via NR Broker
│   ├── Unwraps the returned secret-id with Vault
│   ├── Creates or updates an OpenShift secret with the AppRole credentials
│   └── Closes the intention
│
└── Application container (envconsul)
    ├── Reads and unwraps the token from the shared volume
    ├── Fetches secrets from the configured Vault path
    └── Injects secrets as environment variables into the application process
```

## initContainer Image

```
ghcr.io/bcgov/nr-broker-credential-injection/intention-provision:v2.0.0
```

The initContainer runs `get-vault-token.sh`, which handles the full token provisioning flow. It requires the following environment variables:

| Variable | Source | Description |
|---|---|---|
| `BROKER_JWT` | Kubernetes Secret | JWT for authenticating with NR Broker |
| `VAULT_ROLE_ID` | Kubernetes Secret | Vault AppRole Role ID |
| `INTENTION_EVENT_URL` | Pod spec | URL for audit trail (e.g. link to the pod) |
| `INTENTION_ENVIRONMENT` | Pod spec | Target environment (`development`, `test`, `production`) |
| `BROKER_URL` | Optional | NR Broker URL (default: `https://broker.io.nrs.gov.bc.ca`) |
| `VAULT_ADDR` | Optional | Vault address (default: `https://knox.io.nrs.gov.bc.ca`) |
| `OPENSHIFT_SECRET_NAME` | Optional | Secret to create or update with the AppRole credentials (default: `vault-secret`) |
| `OPENSHIFT_TOKEN_KEY` | Optional | Key used for the Broker JWT in the OpenShift secret (default: `token`) |
| `OPENSHIFT_ROLE_KEY` | Optional | Key used for the Vault Role ID in the OpenShift secret (default: `role`) |
| `OPENSHIFT_SECRET_ID_KEY` | Optional | Key used for the provisioned Vault secret ID in the OpenShift secret (default: `secret_id`) |

## Integration Guide

### Prerequisites

1. Register your project and service in the [Broker UI](https://broker.io.nrs.gov.bc.ca/)
2. Generate a Broker JWT and Vault Role ID for the service
3. Store both as a Kubernetes Secret in your namespace:
   ```bash
   oc create secret generic vault-secret \
     --from-literal=token=<BROKER_JWT> \
     --from-literal=role=<VAULT_ROLE_ID>
   ```

### Add to Your Deployment

Add the following to your Pod or Deployment spec:

**Volumes:**
```yaml
volumes:
  - name: intention-config
    configMap:
      name: my-app-intention-config
  - name: envconsul-config
    configMap:
      name: my-app-envconsul-config
  - name: vault-token
    emptyDir: {}
```

**initContainer:**
```yaml
initContainers:
  - name: vault-init
    image: ghcr.io/bcgov/nr-broker-credential-injection/intention-provision:v2.0.0
    volumeMounts:
      - name: intention-config
        mountPath: /broker/config
      - name: vault-token
        mountPath: /broker/output
    env:
      - name: VAULT_ROLE_ID
        valueFrom:
          secretKeyRef:
            name: vault-secret
            key: role
      - name: BROKER_JWT
        valueFrom:
          secretKeyRef:
            name: vault-secret
            key: token
      - name: INTENTION_EVENT_URL
        value: "https://console.apps.silver.devops.gov.bc.ca/k8s/ns/<namespace>/pods/<pod-name>"
      - name: INTENTION_ENVIRONMENT
        value: "development"
```

**Application container:**
```yaml
containers:
  - name: my-app
    image: my-app-image:latest
    volumeMounts:
      - name: vault-token
        mountPath: /config/token
      - name: envconsul-config
        mountPath: /config/envconsul
    command: ["/bin/bash"]
    args: ["-c", "envconsul -config /config/envconsul/env.hcl <your-app-command>"]
```

### Configure the Intention

Create a ConfigMap with your service's intention (see [sample-intention.json](demo/sample-intention.json)):

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-app-intention-config
data:
  intention.json: |-
    {
      "event": {
        "provider": "my-app",
        "reason": "Job triggered",
        "url": "JOB_URL"
      },
      "actions": [
        {
          "action": "package-provision",
          "id": "provision",
          "provision": ["approle/secret-id"],
          "service": {
            "name": "<your-service>",
            "project": "<your-project>",
            "environment": "development"
          }
        }
      ],
      "user": {
        "name": "<authorized-user>@azureidir"
      }
    }
```

### Configure envconsul

Create a ConfigMap for envconsul pointing to your Vault secret path:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-app-envconsul-config
data:
  env.hcl: |-
    vault {
      address = "https://knox.io.nrs.gov.bc.ca"
      renew_token = true
      vault_agent_token_file = "/config/token/.vault-token"
      unwrap_token = true
      retry {
        enabled = true
        attempts = 12
        backoff = "250ms"
        max_backoff = "1m"
      }
    }
    secret {
      no_prefix = true
      path = "apps/<env>/<project>/<service>/<secret-name>"
    }
    exec {
      splay = "0s"
      env { pristine = false }
      kill_timeout = "5s"
    }
```

## Demo

See [demo/README.md](demo/README.md) for a working example using a NestJS sample application deployed via Helm.