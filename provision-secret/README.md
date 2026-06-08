# NR Broker AppRole Refresh CronJob

This chart runs the `intention-provision` container once per day as a Kubernetes `CronJob` and stores the provisioned Vault AppRole `secret_id` in an OpenShift secret.

## Prerequisites

- Access to an OpenShift namespace
- Helm 3 installed
- A source secret containing the Broker JWT and Vault role ID
- Permission for the chart's service account to create and update secrets in the namespace

The default source and target secret is `vault-secret` with keys:

- `token`: Broker JWT
- `role`: Vault AppRole role ID
- `secret_id`: provisioned Vault AppRole secret ID

## Install

```bash
helm install knox-provision ./cronjob-deployment
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

## Uninstall

```bash
helm uninstall nr-broker-provision-secret-cron
```