# Demo: NestJS Application with Vault Secret Injection

A working example that deploys a NestJS application to OpenShift with secrets retrieved from Vault via NR Broker.

The demo uses the `nodejs-sample` service registered in NR Broker. After deployment, the NestJS app displays metadata about the injected secrets (which keys are present and their lengths) without exposing actual secret values.

## Images

**initContainer** — retrieves a wrapped Vault token:
```
ghcr.io/bcgov/nr-broker-credential-injection/init:v1.0.1
```

**Application** — NestJS sample app with envconsul:
```
ghcr.io/bcgov/nr-broker-credential-injection/demo-nest-app:v1.0.1
```

## Prerequisites

- Access to the OpenShift namespace
- Kubernetes Secret `vault-secret` with keys `role` (Vault Role ID) and `token` (Broker JWT)
- Helm 3 installed

## Deploy

```bash
helm install knox-retriever-demo ../webapp-deployment/
```

After deployment, the app is available at:
https://nestapp-test.apps.silver.devops.gov.bc.ca/

It displays secrets retrieved from Vault at path:
`apps/dev/nodejs-sample/nodejs-sample/proxy-account-ready-only`

## Uninstall

```bash
helm uninstall knox-retriever-demo
```

## What the Demo Deploys

| Resource | Description |
|---|---|
| Pod | Single pod with initContainer + NestJS container |
| ConfigMap (intention) | Intention JSON for NR Broker (`nodejs-sample` service) |
| ConfigMap (envconsul) | envconsul HCL config pointing to the Vault secret path |
| Service | ClusterIP service on port 3600 |
| Route | OpenShift route exposing the app externally |
| NetworkPolicy | Allows ingress from the OpenShift router |

## Configuration

See [../webapp-deployment/values.yaml](../webapp-deployment/values.yaml) for configurable values including namespace, image registry, route host, and app version.
