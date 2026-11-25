# helm-charts

Helm charts for the ShopHub platform, laid out exactly as required by **Requirement 5.3**.
Charts are published as OCI artifacts to GHCR and installed from the
[`kube-state`](https://github.com/nikola031ue/kube-state-spec) repository.

## Repository layout

```text
helm-charts
├── README.md
└── charts/
    ├── shop/
    │   ├── Chart.yaml
    │   ├── values.yaml
    │   └── templates/
    ├── shop-operator/
    │   ├── Chart.yaml
    │   ├── values.yaml
    │   └── templates/
    ├── shophub-discord/
    │   ├── Chart.yaml
    │   ├── values.yaml
    │   └── templates/
    └── shophub/
        ├── Chart.yaml
        ├── values.yaml
        ├── charts/
        └── templates/
            ├── NOTES.txt
            ├── _helpers.tpl
            ├── deployment.yaml
            ├── hpa.yaml
            ├── ingress.yaml
            ├── service.yaml
            └── serviceaccount.yaml
```

The layout is immutable (Constitution Principle I) and enforced by the `layout` CI check.
CI tooling lives under `.github/` only. A new chart is added as `charts/<name>/` with the same
shape **and** by extending `ALLOWED_CHARTS` in `.github/scripts/lib.sh` in the same PR.

## Charts

| Chart | Purpose | Status | OCI name |
|-------|---------|--------|----------|
| `shop` | One Shop application per ShopHub store. Not installed from kube-state — Shops are runtime state created via the operator. | placeholder (no resources) | `oci://ghcr.io/nikola031ue/charts/shop` |
| `shop-operator` | Shop operator and its CRDs (`Shop`, `DiscordChannel`, `Wallet`). | placeholder (no resources) | `oci://ghcr.io/nikola031ue/charts/shop-operator` |
| `shophub` | ShopHub panel (spec 004): app (2 replicas), CNPG database `shophub-db`, Ingress `shophub.localhost`, NetworkPolicy (Traefik only), Role in `shops` only. Needs the CNPG operator. Requirement 5.3 fixes its template files, so the Role and RoleBinding render from `serviceaccount.yaml`, the database from `deployment.yaml` and the NetworkPolicy from `ingress.yaml` | 0.2.0, ShopHub 0.1.0 | `oci://ghcr.io/nikola031ue/charts/shophub` |
| `shophub-discord` | One `DiscordChannel` for platform/cluster alerts (Requirement 4.1). | placeholder (no resources) | `oci://ghcr.io/nikola031ue/charts/shophub-discord` |

Pull any chart anonymously, e.g.:

```bash
helm show chart oci://ghcr.io/nikola031ue/charts/shophub --version 0.1.0
```

## Versioning and publishing

- Every chart has a SemVer 2.0 `version` in `Chart.yaml`. **Any change to a chart must bump it**;
  the `version` check blocks the PR otherwise.
- On merge to `main`, every chart version not yet in GHCR is packaged and pushed. Published
  versions are immutable and are **never overwritten** — a re-run skips them.
- No image may use the tag `latest` and no `appVersion` may be `latest` (Principle II).
- No secrets in any `values.yaml`; reference Kubernetes Secrets by name (Principle VI).
- After the **first** publish of a new chart, set its GHCR package to **Public** once
  (GitHub → Packages → `charts/<name>` → Package settings → Change visibility). The
  `verify-public` job fails until you do.

## CI checks

| Check | When | What |
|-------|------|------|
| `layout` | PR, push to `main` | 5.3 tree, chart allow-list, exact `shophub` templates |
| `lint` | PR, push to `main` | `helm lint --strict`; secrets scan of chart `values.yaml` |
| `template` | PR, push to `main` | `helm template` → kubeconform; no missing/`latest` image tags |
| `version` | PR | changed charts bump SemVer and are not yet published |
| `rbac-drift` | PR, push to `main` | the `shophub` chart's Role and RoleBinding equal the manifest the shophub k3s tests assert (`shophub-spec` main, `tests/ShopHub.Api.Tests/Integration/K3s/Manifests/shophub-rbac.yaml`); rules, subjects and namespaces compared after normalising, labels ignored; any difference fails. `publish` waits for it |
| `install` | PR | every chart installs on a kind cluster with default values (with the CNPG operator for `shophub`); ShopHub's rollout and its RBAC checked with `kubectl auth can-i` |
| `publish` | push to `main` | push unpublished chart versions to GHCR |
| `verify-public` | after `publish` | every chart version is pullable anonymously |

## Branch protection

`main` is protected (trunk-based, solo developer — Constitution deviation D-1: no required
approvals; self-review + required CI instead):

```bash
gh api -X PUT repos/nikola031ue/helm-charts-spec/branches/main/protection --input - <<'EOF'
{
  "required_status_checks": { "strict": true,
    "contexts": ["layout", "lint", "template", "version", "install"] },
  "enforce_admins": true,
  "required_pull_request_reviews": { "required_approving_review_count": 0 },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF
```

## Local validation

```bash
bash .github/scripts/check-layout.sh
for c in charts/*/; do helm lint --strict "$c"; done
bats .github/tests/
```
