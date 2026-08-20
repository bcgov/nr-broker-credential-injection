# About

Provides patterns for service (application) deployments to access credentials by leveraging [NR Broker](https://github.com/bcgov/nr-broker) API to audit, authenticate and authorize access. The injected credentials are retrieved from [Knox](https://apps.nrs.gov.bc.ca/int/confluence/x/gib7B) which is an installation of [HashiCorp Vault](https://www.vaultproject.io/).

## How Service Login Works

In NR Broker, services are configured with per-environment access settings. These settings are used to create AppRoles or machine logins in Knox for the service. The per-environment machine logins lets us isolate access to credentials based on the service and the environment.

In order to use the machine login, a secret id needs to be provisioned for the service. This allows teams to control and understand credential usage. After provisioning, various patterns like [Vault Agent](https://developer.hashicorp.com/vault/docs/agent-and-proxy/agent), [envconsul](https://github.com/hashicorp/envconsul) or directly accessing the Vault API is used by the service to use credentials.

## OpenShift Usage

On pod startup, the machine login (AppRole) credentials need to be injected. The following patterns assist with provisioning those credentials.

### Pre-provisioning Secret Pattern

This pattern allows pods to be stopped and started as required with minimal setup. The service deployment needs to use a secret with the AppRole login values (role id and secret id) to access service credentials. The secret is pre-provisioned by an OpenShift cron job that is installed in the same namespace as the pods. The job is installed using a provided helm chart and rotates the secret automatically.

See: [Pre-provisioning Secret Pattern](./provision-secret/README.md)

### Token Injection Pattern

This pattern allows a pod to simply read a Vault token provisioned by an init container. The strength of this approach is that provisioning is tied to the startup of a pod. If there are no pods active, there are no active credentials. The main weakness is that, while the initialization container is provided, it requires the startup of the pod be modified to accomplish the pod initialization.

A technical issue with the way Kubernetes handles initialization (it does not initialize restarted pods) means this pattern is not recommended for long-lived pods like those in a deployment or stateful set. Basically, a restarted pod ends up with an invalid token that doesn't work. This pattern is thus only recommended for situations (example: CronJob) where you expect the pods to run to completion and exit.

See: [Token Injection Pattern](./provision-token/README.md)

### Demo

See [demo/README.md](demo/README.md) for a working example using a NestJS sample application deployed via Helm.

## Tools (CI/CD) Secret Sync

The runtime patterns above are for application pods that read service secrets at startup. CI/CD pipelines and build tooling instead need **tools secrets** — such as the Broker account token and other infrastructure credentials — placed into the OpenShift project itself. NR Broker can synchronize these tools secrets from Knox into Kubernetes Secrets.

To sync a service's tools secrets, Broker must authenticate to the project's Kubernetes API as a service account that can manage Secrets. The `knox-tools-sync` chart provisions that service account, its role and role binding, and a long-lived token that you feed into the Broker sync configuration.

See: [Tools-Sync Access](./knox-tools-sync/README.md)
