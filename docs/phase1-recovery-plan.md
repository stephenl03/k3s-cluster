# Phase 1 k3s GitOps Recovery Plan

_Last updated: 2026-05-08_

Goal: bring this repository back to a functional source-of-truth state for the current `nuc-phase1` k3s cluster.

## Current live cluster snapshot

Kubeconfig used during recovery:

```bash
export KUBECONFIG="$HOME/.kube/nuc-phase1.yaml"
```

Live nodes:

| Node | Role | IP | OS | Kubernetes |
| --- | --- | --- | --- | --- |
| `n1r.k8s.lazy.sh` | control-plane/master | `172.16.50.118` | Fedora 41 | `v1.31.12+k3s1` |
| `n4l.k8s.lazy.sh` | worker | `172.16.50.117` | Fedora 41 | `v1.31.12+k3s1` |
| `n4r.k8s.lazy.sh` | worker | `172.16.50.119` | Fedora 41 | `v1.31.12+k3s1` |

Live fundamentals currently working:

| Component | Namespace | Live state |
| --- | --- | --- |
| k3s bundled Traefik | `kube-system` | Service `traefik` is `LoadBalancer` at `172.16.50.200` |
| MetalLB | `metallb-system` | `controller` + 3 `speaker` pods, image `v0.15.3` |
| MetalLB pool | `metallb-system` | `k8s-lb-pool`: `172.16.50.200-172.16.50.240` |
| cert-manager | `cert-manager` | Helm install, version `v1.19.1`, ClusterIssuers Ready |
| external-dns UniFi | `external-dns` | Helm install, `external-dns` + UniFi webhook pod Ready |
| ACME UDM mirror | `external-dns` | CronJob `acme-dns01-udm-mirror` every minute |
| Smoke ingress | `ingress-smoke` | `whoami.k8s.lazy.sh` serves production Let's Encrypt cert |

Flux is **not currently installed** in the live cluster. There is no `flux-system` namespace and no `sops-age` Secret.

## Important findings from repo audit

The repo structure is useful and should be kept, but it has old/stale assumptions:

1. **SOPS exists in repo but local tooling is missing**
   - `.sops.yaml` is present.
   - Encrypted files exist, including `cluster/base/cluster-secrets.sops.yaml` and `cluster/core/cert-manager/secret.sops.yaml`.
   - Current workstation does not have `sops`, `age`, or `flux` binaries in PATH.
   - The live cluster does not yet have `flux-system/sops-age`.

2. **Flux manifests exist but are not live**
   - `cluster/base/flux-system/gotk-components.yaml` and `gotk-sync.yaml` exist.
   - `gotk-sync.yaml` points at `https://github.com/stephenl03/k3s-cluster`, branch `main`.
   - Flux Kustomizations use SOPS decryption via Secret `sops-age`.

3. **MetalLB repo config is stale**
   - Repo settings currently use `172.16.50.100-172.16.50.150` and Traefik `172.16.50.100`.
   - Live cluster uses `172.16.50.200-172.16.50.240` and Traefik `172.16.50.200`.
   - Repo HelmRelease is `metallb` chart `0.13.5`; live is MetalLB `v0.15.3`.

4. **cert-manager repo config is stale**
   - Repo HelmRelease is `v1.9.1`; live is `v1.19.1`.
   - Repo includes `9.9.9.9` as a DNS01 recursive nameserver. This caused propagation/self-check failures in this network.
   - Live working config uses only `1.1.1.1:53` and `podDnsConfig.nameservers={1.1.1.1}`.

5. **external-dns repo config is the wrong mode for this cluster**
   - Repo external-dns is in namespace `networking`, provider `cloudflare`, `policy: sync`, and Cloudflare-proxied.
   - Live working setup is namespace `external-dns`, provider `webhook`, UniFi/UDM local DNS, `policy: upsert-only`, and `txtOwnerId: nuc-phase1`.

6. **kube-vip is not live and is probably not needed right now**
   - No kube-vip pods/resources are present in the live cluster.
   - Current cluster has one control-plane node. kube-vip is mainly useful here for a highly available Kubernetes API endpoint across multiple control-plane nodes.
   - Service `LoadBalancer` needs are already handled by MetalLB.

## Recommendation: repo scope

Use `stephenl03/k3s-cluster` as the source of truth for live manifests and recovery docs.

Use `stephenl03/homelab` only as a high-level index/overview repo, if desired.

## Recommended recovery order

### Phase A — tooling and secrets foundation

1. Install/verify local tools:

```bash
flux --version
sops --version
age --version
kubectl version --client
```

2. Locate or create the Age private key corresponding to repo `.sops.yaml` recipient:

```text
age16vs9crdp7cxwjtlqu5l83a3pgdah9eau3afrhx7qyzkhag7avq0spf6rxp
```

3. If the private key is not available, rotate SOPS to a new Age key and re-encrypt secrets.

4. Create Flux SOPS secret in cluster before applying encrypted manifests:

```bash
kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -
kubectl -n flux-system create secret generic sops-age \
  --from-file=age.agekey="$SOPS_AGE_KEY_FILE" \
  --dry-run=client -o yaml | kubectl apply -f -
```

5. Rebuild/verify encrypted secrets needed for minimal core:

- `cluster/base/cluster-secrets.sops.yaml`
  - `SECRET_DOMAIN=lazy.sh`
  - `SECRET_CLOUDFLARE_EMAIL=stephenl@me.com`
- `cluster/core/cert-manager/secret.sops.yaml`
  - Secret `cert-manager/cloudflare-api-key`, key `api-key`
- new external-dns UniFi secret, likely `cluster/core/external-dns-unifi/secret.sops.yaml` or equivalent
  - Secret `external-dns/external-dns-unifi-secret`, key `api-key`

Do not commit plaintext secret values.

### Phase B — make repo match live core before enabling Flux

Update the repo to match working live state:

1. `cluster/base/cluster-settings.yaml`
   - `METALLB_LB_RANGE=172.16.50.200-172.16.50.240`
   - `METALLB_TRAEFIK_ADDR=172.16.50.200`
   - `METALLB_LB_GTWY=172.16.50.1`

2. MetalLB
   - Upgrade chart/manifests to `v0.15.3` equivalent.
   - Keep pool name/range consistent with live: `k8s-lb-pool`, `k8s-l2`.

3. cert-manager
   - Upgrade chart to `v1.19.1`.
   - Use working DNS01 self-check settings:
     - `--dns01-recursive-nameservers=1.1.1.1:53`
     - `--dns01-recursive-nameservers-only`
     - pod DNS nameserver `1.1.1.1`
   - Keep staging + production ClusterIssuers.

4. external-dns UniFi
   - Replace/retire the old Cloudflare external-dns app for this cluster.
   - Add UniFi webhook external-dns matching live values:
     - namespace `external-dns`
     - provider webhook image `ghcr.io/kashalls/external-dns-unifi-webhook:v0.8.2`
     - policy `upsert-only`
     - sources `ingress`, `service`
     - `domainFilters: [lazy.sh]`
     - `txtOwnerId: nuc-phase1`

5. ACME UDM mirror
   - Add the `acme-dns01-udm-mirror` CronJob/RBAC.
   - Keep comments explaining why it exists: local DNS interception breaks cert-manager self-checks unless UDM also has active `_acme-challenge` TXT records.

6. Traefik
   - Decide whether to keep k3s bundled Traefik or move Traefik into Flux.
   - Current live cluster uses bundled k3s Traefik in `kube-system` and it works.
   - Safer recovery path: document/adopt bundled Traefik first, then optionally migrate later.

### Phase C — kube-vip decision

Recommendation for current phase: **disable/remove kube-vip from Flux core**.

Reasoning:

- Current cluster has one control-plane node, so a Kubernetes API VIP does not add HA.
- MetalLB already handles service `LoadBalancer` IPs.
- Live cluster is working without kube-vip.
- Applying stale kube-vip manifests risks introducing a misleading or conflicting control-plane VIP.

When kube-vip becomes useful:

- If the cluster gains multiple control-plane nodes and needs one stable API endpoint, e.g. `172.16.50.x:6443`.
- At that point, define the control-plane VIP deliberately and make kubeconfig/server URLs point to it.

Until then:

- Remove `cluster/core/kube-system/kube-vip` from active kustomization, or move it under `cluster/optional/kube-vip` with docs.

### Phase D — bootstrap Flux carefully

Only after the repo renders cleanly and secrets are sorted:

1. Validate kustomize output locally:

```bash
kubectl kustomize cluster/crds >/tmp/k3s-crds.yaml
kubectl kustomize cluster/core >/tmp/k3s-core.yaml
kubectl kustomize cluster/apps >/tmp/k3s-apps.yaml
```

2. Apply Flux components and sync, or use `flux bootstrap github` once GitHub write access/token mode is chosen.

For this repo, SSH works for git, but Flux in-cluster needs its own deploy key or HTTPS/token auth. Decide before bootstrap:

- GitHub deploy key for `stephenl03/k3s-cluster`, read-only is enough for Flux sync.
- Or GitHub token Secret for HTTPS auth.

3. Start with CRDs and core only. Keep apps pruned/disabled until core is stable.

4. Reconcile and verify:

```bash
flux get sources git -A
flux get kustomizations -A
flux get helmreleases -A
kubectl get pods -A
```

## Near-term branch plan

Suggested branch:

```text
sam/recover-phase1-core
```

First PR should include:

- this recovery plan
- DNS/TLS/MetalLB runbook
- current live-state core manifests for MetalLB, cert-manager, external-dns UniFi, ACME UDM mirror
- removal/parking of kube-vip from active core
- no plaintext secrets

Do not enable full Flux pruning of apps until the old app manifests are reviewed. Some old apps reference stale domains, PVCs, secrets, chart versions, and namespaces.
