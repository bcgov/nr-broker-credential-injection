# Demo: Daily Secret Refresh CronJob

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
helm install knox-retriever-cron ./demo/cronjob-deployment
```

The default schedule is once per day at 02:00:

```cron
0 2 * * *
```

## Customize

Override values to point at your service registration and namespace-specific secret names. The most common settings are in `values.yaml`:

- `schedule`
- `sourceSecret.*`
- `targetSecret.*`
- `intention.service.*`
- `intention.event.*`
- `global.environment`

## Uninstall

```bash
helm uninstall knox-retriever-cron
```