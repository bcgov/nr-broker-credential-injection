# NR Broker Pre-provisioning OpenShift Secret Pattern

Install this Helm chart when your OpenShift service needs credentials from [Knox Vault](https://apps.nrs.gov.bc.ca/int/confluence/x/gib7B) and should be able to restart, scale, or recover without manual secret renewal. It automates the credential setup needed for your pods to access Vault.

## Prerequisites

- Access to an OpenShift namespace
- Helm 3 installed
- AppRole configured for this pattern
- A source secret containing the Broker JWT and Vault role ID

## AppRole Setup

Vault AppRole is an authentication method designed for applications and automation. It uses a stable `role_id` to identify the application and a renewable or expiring `secret_id` to prove that the application is allowed to log in. This chart runs an OpenShift CronJob that uses [NR Broker](https://apps.nrs.gov.bc.ca/int/confluence/x/pS3FBw) to provision the `secret_id`, then stores it with the `role_id` so pods can authenticate to [Knox Vault](https://apps.nrs.gov.bc.ca/int/confluence/x/gib7B) without a developer managing credentials manually. The scheduled refresh keeps the credentials available over time.

Confirm that the AppRole's Secret ID TTL and usage limit support the number of pods and CronJob schedule you intend to use. The CIDR login restriction is recommended as an additional security control. If you do not have access to change this configuration, contact the team that manages Knox Vault.

### Secret ID TTL

The Secret ID TTL (time to live) needs to be longer than the CronJob period. If you plan to run the CronJob daily (the default), request a TTL longer than 24 hours. To prevent outages, consider requesting a TTL of a couple of days so that a failed CronJob does not immediately prevent pods from starting.

### Secret ID Usage

The Secret ID usage limit needs to be set to 0 (unlimited) or another reasonable number. The default usage limit is 1, which prevents more than one pod from starting per provisioning.

### Login CIDR Restriction

The per-environment AppRole login can be configured to allow logins only from an IP range (CIDR). This ensures that, even though the provisioned login credentials can be used multiple times, logins are limited to an expected range. This range can be updated at any time without needing to provision a new Secret ID.

Ideally, the configured CIDR should be unique to the service and environment. Ensure that your hosting platform can provide this. In any case, this restriction is not foolproof; use other methods, such as audit log monitoring, to identify and investigate unusual logins.

## Source Secret Setup

Before installation, manually add a secret (default: `knox-secret`) with the keys `token` (the service Broker token) and `role_id` (the environment's AppRole role ID). Never share the token or role ID or add them to source control.

Summary of the `knox-secret` keys:

- `token`: Broker JWT
- `role_id`: Vault AppRole role ID

Users in Broker with service sudo access (lead developer) can access this data.

NR Broker also offers a method to synchronize tool secrets, including the Broker JWT, Vault role ID, and other tool secrets stored in Knox Vault. See the [NR Broker tool secret synchronization documentation](https://bcgov.github.io/nr-broker/#/operations_kubernetes_sync) for more information.

## Configure

Next, create a configuration for the Helm deployment. We recommend using the NR Composer generator `ocp-knox-provision`, which walks you through the process with prompts and outputs documentation to assist with operational tasks.

See: https://bcgov.github.io/nr-repository-composer/#/using/generators/ocp-knox-provision

If you want to set up the values file manually or need more details about configuring the CronJob, continue to 'Configuration Details' and then return to the installation instructions.

# Install

This repository uses GitHub Pages to distribute the Helm chart. First, ensure that you have the Helm repository configured.

```bash
helm repo add broker https://bcgov.github.io/nr-broker-credential-injection
```

Finally, install the CronJob.

```bash
helm install knox-provision broker/cronjob-deployment -f dev.yaml
```

## Uninstall

```bash
helm uninstall knox-provision
```

## Configuration Details

The values file defines your service and other environment-specific settings. The configured user must have the change role for the service's environment in NR Broker. If this user leaves your team or their access changes, update the value to a new user with the change role.

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

## Customize

Override values in `cronjob-deployment/values.yaml` to suit your environment. The chart is organized into the following sections:

### `global`

- `name` — Release name. Defaults to `knox-provision`.
- `vaultAddress` — Knox Vault address. Defaults to `https://knox.io.nrs.gov.bc.ca`.
- `brokerAddress` — NR Broker address. Defaults to `https://broker.io.nrs.gov.bc.ca`.

### `cron`

- `schedule` — Cron expression for the job schedule. Defaults to `0 2 * * *` (02:00 daily). Set to `* * * * *` for a random time each day, or use a lookup to avoid rescheduling an existing job.
- `concurrencyPolicy` — How to handle concurrent runs (`Allow`, `Forbid`, `Replace`). Defaults to `Forbid`.
- `successfulJobsHistoryLimit` — Number of successful jobs to keep. Defaults to `3`.
- `failedJobsHistoryLimit` — Number of failed jobs to keep. Defaults to `1`.
- `backoffLimit` — Backoff limit for the job. Defaults to `1`.
- `restartPolicy` — Pod restart policy. Defaults to `OnFailure`.
- `podAnnotations` — Annotations to add to the CronJob pod. Defaults to `{}`.
- `podLabels` — Labels to add to the CronJob pod. Defaults to `{}`.
- `resources` — Resource requests and limits for the container. Defaults to `{}`.

### `image`

- `registry` — Container image registry. Defaults to `artifacts.developer.gov.bc.ca/github-docker-remote/`.
- `repository` — Container image repository. Defaults to `bcgov/nr-broker-credential-injection/intention-provision-secret`.
- `tag` — Container image tag. Defaults to `v3.0.2`.
- `pullPolicy` — Image pull policy. Defaults to `IfNotPresent`.
- `pullSecrets` — Image pull secrets for private registries. Defaults to `[]`.

### `sourceSecret`

- `name` — Name of the secret containing the Broker JWT and Vault role ID. Defaults to `knox-secret`.
- `brokerTokenKey` — Key for the Broker JWT. Defaults to `token`.
- `vaultRoleIdKey` — Key for the Vault AppRole role ID. Defaults to `role_id`.

### `targetSecret`

- `name` — Name of the secret to store the provisioned Vault AppRole `secret_id`. Defaults to `knox-secret`. **This must not match the source name if using [NR Broker's secret synchronization](https://bcgov.github.io/nr-broker/#/operations_kubernetes_sync)**
- `brokerTokenKey` — Key for the Broker JWT in the target secret. Defaults to `token`.
- `vaultRoleIdKey` — Key for the Vault AppRole role ID in the target secret. Defaults to `role_id`.
- `vaultSecretIdKey` — Key for the provisioned Vault AppRole secret ID. Defaults to `secret_id`.

### `intention`

- `event.provider` — Event provider name. Defaults to `provision-secret-cronjob`.
- `event.reason` — Event reason description. Defaults to `Scheduled secret refresh`.
- `event.url` — Event URL. Defaults to `https://console.apps.silver.devops.gov.bc.ca/`.
- `event.transient` — Whether the event is transient. Defaults to `true`.
- `action.name` — Action name. Defaults to `package-provision`.
- `action.id` — Action ID. Defaults to `provision`.
- `action.provision` — List of provision actions. Defaults to a single `approle/secret-id` action.
- `service.name` — Service name. Defaults to `nodejs-sample`.
- `service.project` — Service project. Defaults to `nodejs-sample`.
- `service.environment` — Service environment. Defaults to `development`.
- `user.name` — User name. Defaults to an empty value and must be configured for the target service.

### `serviceAccount`

- `create` — Whether to create the ServiceAccount. Defaults to `true`.
- `name` — Custom service account name. Defaults to an empty value, which uses `<release>-secret-patch`.

### `rbac`

- `create` — Whether to create the Role and RoleBinding. Defaults to `true`.

### `networkPolicy`

- `create` — Whether to create the egress NetworkPolicy. Defaults to `false`.
- `egress` — Egress rules for the CronJob pod. Defaults to `[]`.

### `sync`

Enable optional secret synchronization after the pre-provision CronJob runs. This feature copies selected Vault secrets into OpenShift Secrets for applications that cannot be modified to log in with an AppRole and retrieve secrets through the Vault API, including COTS applications. It is also useful as an onboarding accelerator when a team needs to get a service running with a simpler deployment before adding direct Vault integration.

Treat this as a compatibility or transitional option rather than the preferred long-term integration. When practical, update the application to use Vault directly through a Vault CLI sidecar or an internal Vault client library, and then disable secret synchronization so secrets are not copied into OpenShift.

- `enabled` — Enable or disable the sync job. Defaults to `false`.
- `schedule` — Cron expression for the sync job. Defaults to an empty value, which creates a one-time Job instead of a CronJob.
- `vaultPaths` — Comma-separated list of Vault secret paths to read (e.g., `"secret/data/app-config,secret/data/db-credentials"`). Defaults to an empty value.
- `secretNames` — Comma-separated list of OpenShift secret names to create/update (must match the count of `vaultPaths`). Defaults to an empty value.
- `sourceSecret.name` — Name of the secret containing AppRole credentials for Vault login. Defaults to `knox-secret`.
- `sourceSecret.vaultRoleIdKey` — Key in the source secret for the Vault AppRole role ID. Defaults to `role_id`.
- `sourceSecret.vaultSecretIdKey` — Key in the source secret for the Vault AppRole secret ID. Defaults to `secret_id`.
- `job.concurrencyPolicy` — How to handle concurrent sync runs. Defaults to `Forbid`.
- `job.successfulJobsHistoryLimit` — Number of successful sync jobs to keep. Defaults to `3`.
- `job.failedJobsHistoryLimit` — Number of failed sync jobs to keep. Defaults to `1`.
- `job.backoffLimit` — Backoff limit for the sync job. Defaults to `4`.
- `job.restartPolicy` — Pod restart policy. Defaults to `OnFailure`.
- `job.podAnnotations` — Annotations to add to the sync job pod. Defaults to `{}`.
- `job.podLabels` — Labels to add to the sync job pod. Defaults to `{}`.
- `job.resources` — Resource requests and limits for the sync container. Defaults to `{}`.

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
