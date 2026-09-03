#!/usr/bin/env bash
set -euo pipefail

chart_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
rendered=$(mktemp)
lab_helm_rendered=$(mktemp)
trap 'rm -f "$rendered" "$lab_helm_rendered"' EXIT

helm_template() {
  helm template getting-started "$chart_dir" --namespace getting-started "$@"
}

require_resource() {
  local component=$1 kind_pattern=$2 name_pattern=$3
  if ! awk -v kind_pattern="$kind_pattern" -v name_pattern="$name_pattern" '
    /^kind:[[:space:]]*/ { kind = $2 }
    /^  name:[[:space:]]*/ && kind ~ kind_pattern && $2 ~ name_pattern { found = 1 }
    END { exit !found }
  ' "$rendered"; then
    printf 'missing %s resource\n' "$component" >&2
    exit 1
  fi
}

require_resources_in_namespace() {
  local component=$1 name_pattern=$2 expected_namespace=$3
  if ! awk -v name_pattern="$name_pattern" -v expected_namespace="$expected_namespace" '
    function check() {
      if (kind != "Namespace" && name ~ name_pattern) {
        found = 1
        if (namespace != expected_namespace) invalid = 1
      }
    }
    /^---[[:space:]]*$/ { check(); kind = name = namespace = ""; next }
    /^kind:[[:space:]]*/ { kind = $2 }
    /^  name:[[:space:]]*/ { name = $2 }
    /^  namespace:[[:space:]]*/ { namespace = $2 }
    END { check(); exit !(found && !invalid) }
  ' "$rendered"; then
    printf '%s resources missing namespace %s\n' "$component" "$expected_namespace" >&2
    exit 1
  fi
}

require_only_namespace_resources() {
  local lab_namespace=$1 lab_helm_namespace=$2
  if ! awk -v lab_namespace="$lab_namespace" -v lab_helm_namespace="$lab_helm_namespace" '
    /^kind:[[:space:]]*Namespace$/ { namespace_resource = 1; next }
    namespace_resource && /^  name:[[:space:]]*/ {
      namespaces[$2]++
      namespace_resource = 0
    }
    END {
      for (name in namespaces) count++
      exit !(count == 4 && namespaces["gitea"] == 1 && namespaces["datasphere"] == 1 && namespaces[lab_namespace] == 1 && namespaces[lab_helm_namespace] == 1)
    }
  ' "$rendered"; then
    printf 'chart must create only gitea, datasphere, %s, and %s Namespace resources\n' "$lab_namespace" "$lab_helm_namespace" >&2
    exit 1
  fi
}

if [[ ! -f "$chart_dir/Chart.yaml" ]]; then
  printf 'missing Chart.yaml: %s/Chart.yaml\n' "$chart_dir" >&2
  exit 1
fi

if helm_template >/dev/null 2>&1; then
  printf 'chart rendered without required credentials\n' >&2
  exit 1
fi

helm_template \
  --set-string gitea.admin.password=contract-gitea-password \
  --set-string postgresql.auth.password=contract-postgresql-password >"$rendered"

require_only_namespace_resources lab lab-helm

require_resources_in_namespace Gitea '^gitea($|-postgresql-credentials$)' gitea
require_resources_in_namespace PostgreSQL '^postgresql$' gitea
require_resources_in_namespace bootstrap '^gitea-admin-bootstrap$' gitea
require_resources_in_namespace seed '^repo-seeding$' gitea
require_resources_in_namespace DataSphere '^datasphere-' datasphere

require_resource Gitea '^(Deployment|StatefulSet)$' 'gitea'
require_resource PostgreSQL '^(Deployment|StatefulSet)$' 'postgres|postgresql'
require_resource 'DataSphere API' '^(Deployment|StatefulSet)$' 'datasphere-api'
require_resource 'DataSphere UI' '^(Deployment|StatefulSet)$' 'datasphere-ui'
require_resource 'DataSphere Redis' '^(Deployment|StatefulSet)$' 'datasphere-redis|redis'
require_resource 'repo-seeding Job' '^Job$' 'repo-seeding'

for repo in datasphere-api datasphere-ui datasphere-gitops; do
  if ! grep -Fq "\"name\": \"$repo\"" "$rendered"; then
    printf 'repo-seeding does not define %s\n' "$repo" >&2
    exit 1
  fi
done

if ! grep -Fq '"default_branch": "main"' "$rendered"; then
  printf 'repo-seeding does not set default branch to main\n' >&2
  exit 1
fi

helm_template \
  --set-string gitea.admin.password=contract-gitea-password \
  --set-string postgresql.auth.password=contract-postgresql-password \
  --set-string namespaces.lab=custom-lab \
  --set-string namespaces.labHelm=custom-lab-helm >"$lab_helm_rendered"
rendered=$lab_helm_rendered
require_only_namespace_resources custom-lab custom-lab-helm

if grep -Eqi '^[[:space:]]*apiVersion:[[:space:]]*.*argoproj\.io|^[[:space:]]*kind:[[:space:]]*(CustomResourceDefinition|Subscription|OperatorGroup)$|^[[:space:]]*name:[[:space:]]*.*(showroom|argocd|argo-cd|gitops)' "$rendered"; then
  printf 'rendered forbidden Showroom, Argo CD/GitOps, or operator resource\n' >&2
  exit 1
fi
