# NR Broker Kubernetes Tools-Sync Access

This chart creates the Kubernetes resources that [NR Broker](https://github.com/bcgov/nr-broker) needs to synchronize a service's **tools (CI/CD) secrets** from Knox (Vault) into an OpenShift project.

NR Broker syncs tools secrets — such as the Broker account token and other infrastructure credentials that CI/CD pipelines and build tooling need — into OpenShift project Secrets. It is **not** used for runtime application secrets; runtime service secrets are read directly from Vault by the service's own AppRole. See the [Pre-provisioning Secret Pattern](../provision-secret/README.md) and [Token Injection Pattern](../provision-token/README.md) for runtime access.

For Broker to write those Secrets into a project it must authenticate to the Kubernetes API as a service account that has permission to manage Secrets in that namespace. This chart provisions exactly that: a service account, a role granting the needed Secret permissions, a role binding, and a long-lived token that you feed into the Broker sync configuration.

## What the Chart Creates

| Resource | Description |
|---|---|
| `ServiceAccount` | The identity Broker authenticates as when writing secrets. Defaults to `nr-broker-sync`. |
| `Role` | Grants `get`, `create`, `update`, `patch` on `secrets` in the namespace. |
| `RoleBinding` | Binds the role to the service account. |
| `Secret` (token) | A long-lived service account token. After the API server mints it, copy its `token` value into the Broker sync configuration. |

## Prerequisites

- Access to the OpenShift project (namespace) where the synced secrets should appear
- Helm 3 installed
- NR Broker configured with a Cloud connected to this OpenShift project (see Step 2 of the internal setup doc)
- A `deploys` edge from the service to the OpenShift project (or its parent cloud) in the Broker graph. This is a restricted edge and may need to be enabled for viewing.

## Install

First, ensure you have the helm repo installed.

```bash
helm repo add broker https://bcgov.github.io/nr-broker-credential-injection
```

Install the chart into the target OpenShift project. Override the namespace-specific values as needed.

```bash
helm install knox-tools-sync broker/knox-tools-sync -n <project-name>
```

## After Installation

Install prints next steps via `NOTES.txt`. Retrieve the long-lived service account token and its CA certificate (the CA certificate is only needed for clusters with a self-signed cert, such as minikube).

```bash
# Long-lived token
kubectl get secret nr-broker-sync-token -n <project-name> \
     -o jsonpath='{.data.token}' | base64 --decode

# CA certificate (self-signed clusters only)
kubectl get secret nr-broker-sync-token -n <project-name> \
     -o jsonpath='{.data.ca\.crt}'
```

Then configure the sync in Vault at `clouds/<cloud-name>/<project-name>/nr-broker-sync`, setting `serviceAccountToken` to the value from above:

```bash
vault kv put clouds/<cloud-name>/<project-name>/nr-broker-sync \
     serviceAccountToken="<token>" \
     caData="<ca-data>" \
     secrets='[{"service": "<service-name>", "destinationSecretName": "<secret-name>"}]'
```

Broker polls the sync queue every 30 seconds. To trigger it immediately, hit the **Sync secrets** action on the OpenShift project page in the NR Broker UI. Each sync creates or fully replaces the target Kubernetes Secret and labels it `nr-broker.io/managed-by=nr-broker`.

See the NR Broker reference for the full configuration: <https://bcgov.github.io/nr-broker/#/operations_kubernetes_sync>.

## Customize

Override values in `values.yaml` to suit your environment.

### `serviceAccount`

- `create` — Whether to create the ServiceAccount. Defaults to `true`.
- `name` — Name of the service account that Broker authenticates as. Defaults to `nr-broker-sync`.
- `annotations` — Extra annotations to add to the ServiceAccount.

### `rbac`

- `create` — Whether to create the Role and RoleBinding. Defaults to `true`.
- `verbs` — Kubernetes Secret verbs the role is granted. Defaults to `get`, `create`, `update`, `patch`.

### `token`

- `create` — Whether to create the long-lived service account token Secret. Defaults to `true`.
- `name` — Name of the token Secret. Defaults to `nr-broker-sync-token`.

### `global`

- `name` — Common app label applied to all resources. Defaults to `knox-tools-sync`.

## Uninstall

```bash
helm uninstall knox-tools-sync -n <project-name>
```
