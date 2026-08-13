# NR Broker Pre-provisioning Secret Pattern

This pattern allows pods to be stopped and started as required with minimal setup. The service deployment needs to use a secret with the AppRole login values (role id and secret id) to access service credentials. The secret is pre-provisioned by an OpenShift cron job that is installed in the same namespace as the pods. The job is installed using a provided helm chart and rotates the secret automatically.

## Prerequisites

- Access to an OpenShift namespace
- Helm 3 installed
- A source secret containing the Broker JWT and Vault role ID

The default source and target secret is `knox-secret` with keys:

- `token`: Broker JWT
- `role_id`: Vault AppRole role ID
- `secret_id`: provisioned Vault AppRole secret ID

## AppRole Setup

The AppRole needs to be setup specifically for this pattern to work. The first two are required. The CIDR restriction is recommended.

### Secret ID TTL

The secret id ttl (time to live) needs to be longer than the CronJob period. If you plan on running the CronJob daily (the default) then you should request the ttl to be longer than 24 hours. To prevent outages, you may want to request that the TTL be even a couple days so that the CronJob failing doesn't immediately impact the ability for pods to start.

### Secret ID Usage

The secret id usages needs to be set to 0 (infinite) or some other reasonable number. The default number of usages is 1 which will prevent more than 1 pod starting per provisioning.

### Login CIDR Restriction

The per-environment AppRole login can be configured to only allow logins from an IP range (CIDR). This ensures that, even though the provisioned login credentials can be used multiple times, the logins are limited to an expected range. This range can be updated anytime without needing to re-provision a new secret id.

Ideally, the configured CIDR will be unique to the service and environment. You will want to ensure your hosting option can provide this. In any case, this restriction isn't foolproof and other methods like audit log monitoring should be used to identify and investigate unusual logins.

## Install

This repository uses GitHub Pages to distribute the helm chart. First, ensure you have the helm repo installed.

```bash
helm repo add broker https://bcgov.github.io/nr-broker-credential-injection
```

Next, create a values file with service and other environment specific settings. The configured user must have the change role for the environment for the service in NR Broker. If this user leaves your team or their access changes, you must update the value to a new user with the change role.

```yaml
intention:
  service:
    name: "nodejs-sample"
    project: "oscar-example"
    environment: "development"
  user:
    name: "mbystedt@azureidir"
```

If you are running in an environment that requires egress network policies, you can add values like this to configure it. Please reach out to discuss the CIDR.

```yaml
cron:
  podLabels:
    DataClass: Medium

networkPolicy:
  create: true
  egress:
    - cidr: x.x.x.x/32
      ports:
        - protocol: TCP
          port: 443
    - podSelector:
        matchLabels:
          app: vault
```

Before installation, manually add a secret (default: knox-secret) with the keys 'token' (the service broker token) and 'role_id' (the environment's AppRole role id). The token and role id must never be shared or added to source control. Users in Broker with service sudo access (lead developer) can access this data.

Finally, install the cronjob.

```bash
helm install knox-provision broker/cronjob-deployment -f dev.yaml
```

## Customize

Override values in `cronjob-deployment/values.yaml` to suit your environment. The chart is organized into the following sections:

### `cron`

- `schedule` — Cron expression for the job schedule. Defaults to `0 2 * * *` (02:00 daily). Set to `* * * * *` for a random time each day, or use a lookup to avoid rescheduling an existing job.
- `concurrencyPolicy` — How to handle concurrent runs (`Allow`, `Forbid`, `Replace`). Defaults to `Forbid`.
- `successfulJobsHistoryLimit` — Number of successful jobs to keep. Defaults to `3`.
- `failedJobsHistoryLimit` — Number of failed jobs to keep. Defaults to `1`.
- `backoffLimit` — Backoff limit for the job. Defaults to `1`.
- `restartPolicy` — Pod restart policy. Defaults to `OnFailure`.
- `podAnnotations` — Annotations to add to the CronJob pod.
- `podLabels` — Labels to add to the CronJob pod.
- `resources` — Resource requests and limits for the container.

### `image`

- `registry` — Container image registry.
- `repository` — Container image repository.
- `tag` — Container image tag.
- `pullPolicy` — Image pull policy. Defaults to `IfNotPresent`.
- `pullSecrets` — Image pull secrets for private registries.

### `sourceSecret`

- `name` — Name of the secret containing the Broker JWT and Vault role ID.
- `brokerTokenKey` — Key for the Broker JWT.
- `vaultRoleIdKey` — Key for the Vault AppRole role ID.

### `targetSecret`

- `name` — Name of the secret to store the provisioned Vault AppRole `secret_id`.
- `brokerTokenKey` — Key for the Broker JWT in the target secret.
- `vaultRoleIdKey` — Key for the Vault AppRole role ID in the target secret.
- `vaultSecretIdKey` — Key for the provisioned Vault AppRole secret ID.

### `intention`

- `event.provider` — Event provider name.
- `event.reason` — Event reason description.
- `event.url` — Event URL.
- `action.name` — Action name.
- `action.id` — Action ID.
- `action.provision` — List of provision actions.
- `service.name` — Service name.
- `service.project` — Service project.
- `service.environment` — Service environment.
- `user.name` — User name.

### `serviceAccount`

- `create` — Whether to create the ServiceAccount. Defaults to `true`.
- `name` — Custom service account name. If empty, defaults to `<release>-secret-patch`.

### `rbac`

- `create` — Whether to create the Role and RoleBinding. Defaults to `true`.

### `sync`

Enable optional secret synchronization after the pre-provision cron job runs. This allows you to sync Vault secrets to OpenShift secrets without modifying your deployment or application.

- `enabled` — Enable or disable the sync job. Defaults to `false`.
- `schedule` — Cron expression for the sync job. Set to empty string (`""`) to run as a one-time Job instead of a CronJob.
- `vaultPaths` — Comma-separated list of Vault secret paths to read (e.g., `"secret/data/app-config,secret/data/db-credentials"`).
- `secretNames` — Comma-separated list of OpenShift secret names to create/update (must match the count of `vaultPaths`).
- `sourceSecret.name` — Name of the secret containing AppRole credentials for Vault login. Defaults to `knox-secret`.
- `sourceSecret.vaultRoleIdKey` — Key in the source secret for the Vault AppRole role ID. Defaults to `role_id`.
- `sourceSecret.vaultSecretIdKey` — Key in the source secret for the Vault AppRole secret ID. Defaults to `secret_id`.
- `job.concurrencyPolicy` — How to handle concurrent sync runs. Defaults to `Forbid`.
- `job.successfulJobsHistoryLimit` — Number of successful sync jobs to keep. Defaults to `3`.
- `job.failedJobsHistoryLimit` — Number of failed sync jobs to keep. Defaults to `1`.
- `job.backoffLimit` — Backoff limit for the sync job. Defaults to `4`.
- `job.restartPolicy` — Pod restart policy. Defaults to `OnFailure`.
- `job.podAnnotations` — Annotations to add to the sync job pod.
- `job.podLabels` — Labels to add to the sync job pod.
- `job.resources` — Resource requests and limits for the sync container.

#### Example: Enable sync with a scheduled CronJob

```yaml
sync:
  enabled: true
  schedule: "0 3 * * *"  # Run daily at 03:00, after the provision cron at 02:00
  vaultPaths: "secret/data/myapp/config,secret/data/myapp/db"
  secretNames: "myapp-config-secret,myapp-db-secret"
  sourceSecret:
    name: "knox-secret"
    vaultRoleIdKey: "role_id"
    vaultSecretIdKey: "secret_id"
```

#### Example: Enable sync as a one-time Job

```yaml
sync:
  enabled: true
  schedule: ""  # Empty string creates a one-time Job instead of CronJob
  vaultPaths: "secret/data/myapp/config"
  secretNames: "myapp-config-secret"
```

> **NOTICE:** This job must be run before changes are reflected in OpenShift. For applications requiring dynamic secrets, Vault should be connected to during runtime. Consider using the Vault Agent Sidecar Injector for dynamic secret rotation.

## Uninstall

```bash
helm uninstall knox-provision
```