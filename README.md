# About

Provides patterns for deployments to inject credentials by leveraging [NR Broker](https://github.com/bcgov/nr-broker) API to audit, authenticate and authorize access. The injected credentials are retreived from [Knox](https://apps.nrs.gov.bc.ca/int/confluence/x/gib7B) which is an installation of [HashiCorp Vault](https://www.vaultproject.io/).

## How Vault Login Works

In NR Broker, services are configured with per-environment access settings. These settings are used to create AppRoles or machine logins in Knox for the service. The per-environment machine logins lets us isolate access to credentials based on the service and the environment.

In order to use the machine login, a secret id needs to be provisioned for the service as part of the deployment. After provisioning, various patterns like Vault Agents, [envconsul](https://github.com/hashicorp/envconsul) or custom code can be used to retrieve credentials for the service.

## OpenShift Usage

On pod startup, the machine login (AppRole) credentials need to be injected. The following patterns assist with provisioning those credentials.

### Pre-provisioning Secret Pattern

This pattern allows pods to be stopped and started as required with minimal setup for the actual service deployment. The service just references a secret with the AppRole secrets that a cronjob keeps updated.

See: [Pre-provisioning Secret Pattern](./provision-secret/README.md)

### Token Injection Pattern

This pattern allows a pod to simply read the Vault token provisioned by an init contianer. The strength of this approach is  provisioning is tied to the startup of a pod. If there are no pods active, there are no active credentials. The main weakness is that it requires the service deployment to be modified to accomplish the pod intialization.

A technical issue with the how Kubernetes handles initialization (it does not initialize restarted pods) means this pattern is not recommended for long lived pods like those in a deployment or stateful set. Basically, a restarted pod ends up with an invalid token that doesn't work. This pattern is thus only recommended for situations (example: CronJob) where you expect the pods to run to completion and exit.

See: [Token Injection Pattern](./provision-token/README.md)

### Demo

See [demo/README.md](demo/README.md) for a working example using a NestJS sample application deployed via Helm.
