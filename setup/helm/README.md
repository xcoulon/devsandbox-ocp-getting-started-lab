# OpenShift Getting Started Module 1

Direct Helm payload for one existing OpenShift cluster. No Argo CD, Showroom, OLM resources, or `CustomResourceDefinition` resources.

## Prerequisites

- Helm release namespace exists or caller uses `--create-namespace`
- OpenShift routes API is available
- cluster can pull images in `values.yaml`
- dynamic storage class exists, or set both `*.persistence.storageClass` values

## Install

Create a private values file. Do not pass passwords with `--set` because shell history exposes them.

```yaml
# values-private.yaml
gitea:
  admin:
    password: replace-with-long-random-password
postgresql:
  auth:
    password: replace-with-different-long-random-password
```

```bash
helm upgrade --install getting-started . \
  --namespace getting-started \
  --create-namespace \
  --values values-private.yaml
```

`--namespace getting-started` stores Helm release state only. Chart creates `gitea`, `datasphere`, `lab`, and `lab-helm`; workloads explicitly target only `gitea` and `datasphere`, so `lab` stays empty. Override them with `namespaces.gitea`, `namespaces.datasphere`, `namespaces.lab`, and `namespaces.labHelm`.

Set `gitea.route.host` and `datasphere.ui.route.host` in `values-private.yaml` for fixed hostnames. Empty values let OpenShift assign route hosts.

## Payload

- Gitea + PostgreSQL, each with 5 GiB persistent storage
- admin bootstrap Job
- idempotent repository seed Job for `datasphere-api`, `datasphere-ui`, and `datasphere-gitops`, from pinned source commit `7c4a971b02fab9a91c621a44b1afacb9dd552ffa`
- DataSphere API, UI, Redis, services, UI Route, and API HPA

Existing Gitea repositories are left untouched on Helm upgrades. Source seed is intentionally not reconciled.

## Verify

```bash
./test-helm-contract.sh
helm lint . \
  --set-string gitea.admin.password=test-gitea-password \
  --set-string postgresql.auth.password=test-postgresql-password
```

`Route` is an existing OpenShift API kind. Chart creates no CRD definitions or operator-specific custom resources.
