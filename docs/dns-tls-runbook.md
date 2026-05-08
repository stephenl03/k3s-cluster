# DNS + TLS Runbook for the NUC k3s Cluster

_Last verified: 2026-05-08_

This documents the current working setup for automatic internal DNS and Let's Encrypt TLS on Stephen's NUC/k3s cluster. It is intentionally written so Sam/future operators can repeat the setup from scratch.

> Note: this workspace is named `talos-cluster`, but the currently active cluster referenced here is the phase-1 k3s cluster using kubeconfig `~/.kube/nuc-phase1.yaml`.

## Current working state

### Cluster access

Local workstation currently does not have system `kubectl`/`helm` in PATH, so temporary local binaries were downloaded into:

```bash
/home/stephen/.openclaw/workspace/.tmp/bin/kubectl
/home/stephen/.openclaw/workspace/.tmp/bin/helm
```

Use:

```bash
cd /home/stephen/.openclaw/workspace
export PATH="$PWD/.tmp/bin:$PATH"
export KUBECONFIG="$HOME/.kube/nuc-phase1.yaml"
```

Current nodes:

| Node | Role | IP |
| --- | --- | --- |
| `n1r.k8s.lazy.sh` | control-plane/master | `172.16.50.118` |
| `n4l.k8s.lazy.sh` | worker | `172.16.50.117` |
| `n4r.k8s.lazy.sh` | worker | `172.16.50.119` |

### Installed Helm releases

```bash
helm list -A
```

Expected relevant releases:

| Release | Namespace | Chart | Purpose |
| --- | --- | --- | --- |
| `traefik` | `kube-system` | bundled k3s Traefik | Ingress controller / TLS serving |
| `external-dns-unifi` | `external-dns` | `external-dns/external-dns` v1.21.1 | Writes Kubernetes ingress/service DNS to UDM local DNS |
| `cert-manager` | `cert-manager` | `jetstack/cert-manager` v1.19.1 | Issues Let's Encrypt certs via Cloudflare DNS-01 |

MetalLB is installed from its native upstream manifests, not Helm. Current controller/speaker image version is `quay.io/metallb/*:v0.15.3`.

### Important IPs/domains

| Thing | Value |
| --- | --- |
| UDM Pro SE / local DNS API | `https://192.168.9.1` |
| Kubernetes VLAN gateway/local DNS | `172.16.50.1` |
| Traefik LoadBalancer IP | `172.16.50.200` |
| Managed domain | `lazy.sh` |
| Cluster test host | `whoami.k8s.lazy.sh` |
| Docker host with Cloudflare env | `step9170@172.16.10.116` |

## Files in this workspace

| File | Purpose |
| --- | --- |
| `manifests/external-dns-unifi-values.yaml` | Helm values for external-dns using the UniFi webhook provider |
| `manifests/cert-manager-cloudflare-issuers.yaml` | `letsencrypt-staging` and `letsencrypt-production` ClusterIssuers |
| `manifests/cert-manager-udm-acme-mirror.yaml` | CronJob/RBAC that mirrors active cert-manager DNS-01 TXT challenges into UDM local DNS |
| `manifests/whoami-tls-smoke-patch.yaml` | TLS-enabled smoke ingress for `whoami.k8s.lazy.sh` |
| `manifests/ingress-lb-smoke.yaml` | Base whoami ingress smoke app |
| `manifests/metallb-l2-pool.yaml` | MetalLB pool `172.16.50.200-172.16.50.240` |

## Secret sources

Do **not** commit plaintext secrets.

### UDM API key

Stored in Bitwarden item:

- item name: `192.168.9.1`
- field name: `API Key`

Kubernetes secret created from it:

```bash
kubectl -n external-dns create secret generic external-dns-unifi-secret \
  --from-literal=api-key='<UDM API key>'
```

Secret name/key expected by manifests:

- namespace: `external-dns`
- secret: `external-dns-unifi-secret`
- key: `api-key`

### Cloudflare credential

Current Docker setup uses Cloudflare global API key variables from:

```bash
ssh step9170@172.16.10.116 'cat ~/docker/.env'
```

Relevant variables:

- `CF_API_EMAIL=stephenl@me.com`
- `CF_API_KEY=<Cloudflare global API key>`

Kubernetes secret created from `CF_API_KEY`:

```bash
kubectl -n cert-manager create secret generic cloudflare-api-key \
  --from-literal=api-key='<Cloudflare CF_API_KEY>'
```

Secret name/key expected by manifests:

- namespace: `cert-manager`
- secret: `cloudflare-api-key`
- key: `api-key`

Future improvement: replace global API key with a scoped Cloudflare API token for only `lazy.sh`:

- Zone / DNS / Edit
- Zone / Zone / Read
- Resource: `lazy.sh` only

If changed to a token, update `cert-manager-cloudflare-issuers.yaml` to use `apiTokenSecretRef` instead of `apiKeySecretRef` + email.

## MetalLB L2 LoadBalancer

### Why this exists

This is a bare-metal k3s cluster, so Kubernetes `Service` objects of type `LoadBalancer` need something to hand out LAN IPs. MetalLB provides that function in L2 mode.

Current pool:

```text
172.16.50.200-172.16.50.240
```

Current important assignment:

```text
kube-system/traefik LoadBalancer -> 172.16.50.200
```

That IP is what UDM local DNS points ingress hostnames at, and what Traefik serves HTTP/HTTPS from.

### Install/reinstall MetalLB

MetalLB was installed from the upstream native manifest, not Helm. To repeat:

```bash
cd /home/stephen/.openclaw/workspace
export PATH="$PWD/.tmp/bin:$PATH"
export KUBECONFIG="$HOME/.kube/nuc-phase1.yaml"

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml
kubectl -n metallb-system rollout status deploy/controller --timeout=180s
kubectl -n metallb-system rollout status daemonset/speaker --timeout=180s

kubectl apply -f projects/talos-cluster/manifests/metallb-l2-pool.yaml
```

`manifests/metallb-l2-pool.yaml` defines:

- `IPAddressPool` named `k8s-lb-pool`
- address range `172.16.50.200-172.16.50.240`
- `L2Advertisement` named `k8s-l2`

### Verify MetalLB

```bash
kubectl -n metallb-system get pods -o wide
kubectl -n metallb-system get ipaddresspool,l2advertisement
kubectl -n kube-system get svc traefik -o wide
kubectl get ingress -A
```

Expected highlights:

```text
metallb-system/controller   1/1 Running
metallb-system/speaker      3/3 Running, one per node
ipaddresspool/k8s-lb-pool   172.16.50.200-172.16.50.240
kube-system/traefik         EXTERNAL-IP 172.16.50.200
ingress-smoke/whoami        ADDRESS 172.16.50.200
```

If Traefik does not get `172.16.50.200`, check for another `LoadBalancer` service consuming the first pool IP:

```bash
kubectl get svc -A --field-selector spec.type=LoadBalancer
```

## external-dns + UDM local DNS

### Why this exists

The cluster uses internal/private service IPs such as `172.16.50.200`. Public Cloudflare DNS is not the right source of truth for LAN-only service routing. UDM local DNS is the practical target.

ExternalDNS uses the webhook provider:

```text
ghcr.io/kashalls/external-dns-unifi-webhook:v0.8.2
```

It talks to:

```text
https://192.168.9.1/proxy/network/v2/api/site/default/static-dns
X-API-KEY: <UDM API key>
```

### Install/reinstall external-dns

```bash
cd /home/stephen/.openclaw/workspace
export PATH="$PWD/.tmp/bin:$PATH"
export KUBECONFIG="$HOME/.kube/nuc-phase1.yaml"

kubectl create namespace external-dns --dry-run=client -o yaml | kubectl apply -f -

# Create secret first; value comes from Bitwarden item 192.168.9.1 field "API Key".
kubectl -n external-dns create secret generic external-dns-unifi-secret \
  --from-literal=api-key='<UDM API key>' \
  --dry-run=client -o yaml | kubectl apply -f -

helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/ || true
helm repo update external-dns

helm upgrade --install external-dns-unifi external-dns/external-dns \
  --namespace external-dns \
  --version 1.21.1 \
  -f projects/talos-cluster/manifests/external-dns-unifi-values.yaml

kubectl -n external-dns rollout status deploy/external-dns-unifi --timeout=180s
```

### Verify external-dns

```bash
kubectl -n external-dns get pods
kubectl -n external-dns logs deploy/external-dns-unifi -c external-dns --tail=120
kubectl -n external-dns logs deploy/external-dns-unifi -c webhook --tail=120

dig +short @172.16.50.1 whoami.k8s.lazy.sh
dig +short @192.168.9.1 whoami.k8s.lazy.sh
```

Expected for the smoke app:

```text
172.16.50.200
```

ExternalDNS should create:

- `whoami.k8s.lazy.sh` A → `172.16.50.200`
- `k8s.a-whoami.k8s.lazy.sh` TXT ownership record

## cert-manager + Let's Encrypt + Cloudflare DNS-01

### Why DNS-01, not HTTP-01

Services resolve to private RFC1918 addresses. Let's Encrypt cannot reach `172.16.50.200` from the public internet, so HTTP-01 is the wrong challenge type.

Cloudflare is authoritative for `lazy.sh`, so cert-manager uses Cloudflare DNS-01 for real ACME validation.

### Install/reinstall cert-manager

```bash
cd /home/stephen/.openclaw/workspace
export PATH="$PWD/.tmp/bin:$PATH"
export KUBECONFIG="$HOME/.kube/nuc-phase1.yaml"

helm repo add jetstack https://charts.jetstack.io || true
helm repo update jetstack

kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v1.19.1 \
  --set crds.enabled=true \
  --set 'extraArgs={--dns01-recursive-nameservers=1.1.1.1:53,--dns01-recursive-nameservers-only}' \
  --set podDnsPolicy=None \
  --set 'podDnsConfig.nameservers={1.1.1.1}'

kubectl -n cert-manager rollout status deploy/cert-manager --timeout=180s
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=180s
kubectl -n cert-manager rollout status deploy/cert-manager-cainjector --timeout=180s
```

The one-name-server config is intentional. When `9.9.9.9` was also configured, cert-manager hit intermittent `connection refused` on DNS/53 in this network.

### Create Cloudflare secret and issuers

```bash
# CF_API_KEY comes from step9170@172.16.10.116:~/docker/.env
kubectl -n cert-manager create secret generic cloudflare-api-key \
  --from-literal=api-key='<Cloudflare CF_API_KEY>' \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f projects/talos-cluster/manifests/cert-manager-cloudflare-issuers.yaml

kubectl wait --for=condition=Ready clusterissuer/letsencrypt-staging --timeout=120s
kubectl wait --for=condition=Ready clusterissuer/letsencrypt-production --timeout=120s
```

Verify:

```bash
kubectl get clusterissuer
```

Expected:

```text
letsencrypt-staging      True
letsencrypt-production   True
```

## UDM DNS-01 self-check mirror

### The goblin

During testing, cert-manager successfully created the TXT challenge in Cloudflare, but its local DNS self-check could not see it.

Evidence:

- Cloudflare API showed the TXT record exists.
- Public DNS-over-HTTPS from Cloudflare returned the TXT record.
- `dig @1.1.1.1 TXT _acme-challenge...` from the local network initially returned stale/UDM answers.
- Adding the same TXT record to UDM local DNS immediately let cert-manager continue.

Conclusion: the network/UDM appears to intercept or redirect outbound DNS/53 in a way that makes cert-manager's DNS-01 self-check see UDM local DNS instead of public Cloudflare authoritative DNS.

Let's Encrypt itself still validates against public Cloudflare. The UDM mirror exists only to satisfy cert-manager's local preflight/self-check.

### Install/reinstall the mirror

```bash
kubectl apply -f projects/talos-cluster/manifests/cert-manager-udm-acme-mirror.yaml
```

This creates:

- `external-dns` ServiceAccount: `acme-dns01-udm-mirror`
- ClusterRole/ClusterRoleBinding to list cert-manager `Challenge` resources
- CronJob: `external-dns/acme-dns01-udm-mirror`, every minute

It reads active `acme.cert-manager.io/v1` DNS-01 Challenge resources and writes matching TXT records to UDM local DNS using the same UDM API key secret as external-dns.

### Verify mirror

```bash
kubectl -n external-dns create job --from=cronjob/acme-dns01-udm-mirror acme-dns01-udm-mirror-smoke
kubectl -n external-dns wait --for=condition=complete job/acme-dns01-udm-mirror-smoke --timeout=120s
kubectl -n external-dns logs job/acme-dns01-udm-mirror-smoke --tail=80
```

If no cert is currently issuing, expected log:

```text
no active DNS-01 challenges
```

## Smoke test: whoami with TLS

### Base ingress app

The base app lives in:

```text
projects/talos-cluster/manifests/ingress-lb-smoke.yaml
```

Apply if needed:

```bash
kubectl apply -f projects/talos-cluster/manifests/ingress-lb-smoke.yaml
```

### Enable TLS

For staging first, set annotation in `whoami-tls-smoke-patch.yaml` to:

```yaml
cert-manager.io/cluster-issuer: letsencrypt-staging
```

For production, set:

```yaml
cert-manager.io/cluster-issuer: letsencrypt-production
```

Then apply:

```bash
kubectl apply -f projects/talos-cluster/manifests/whoami-tls-smoke-patch.yaml
```

Watch issuance:

```bash
kubectl -n ingress-smoke get certificate,certificaterequest,order,challenge -w
kubectl -n ingress-smoke describe certificate whoami-k8s-lazy-sh-tls
```

Expected final state:

```text
certificate.cert-manager.io/whoami-k8s-lazy-sh-tls   True
secret/whoami-k8s-lazy-sh-tls                        kubernetes.io/tls
```

### Verify served cert

```bash
echo | openssl s_client -connect whoami.k8s.lazy.sh:443 -servername whoami.k8s.lazy.sh 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates

curl -k -I https://whoami.k8s.lazy.sh
```

Current verified production cert:

```text
subject=CN=whoami.k8s.lazy.sh
issuer=C=US, O=Let's Encrypt, CN=R12
```

## Current successful validation snapshot

Commands run successfully on 2026-05-08:

```bash
kubectl -n external-dns get deploy,pod,secret,cronjob
kubectl -n cert-manager get deploy,pod,secret
kubectl get clusterissuer
kubectl -n ingress-smoke get ingress,certificate,secret
```

Expected highlights:

- `external-dns-unifi` deployment: `1/1 Available`
- `external-dns-unifi` pod: `2/2 Running`
- `acme-dns01-udm-mirror` CronJob: not suspended, runs every minute
- `cert-manager`, `cert-manager-webhook`, `cert-manager-cainjector`: all `1/1 Available`
- `letsencrypt-staging` and `letsencrypt-production`: `Ready=True`
- `ingress-smoke/whoami`: ports `80,443`, address `172.16.50.200`
- `whoami-k8s-lazy-sh-tls`: `Ready=True`, issuer `letsencrypt-production`

## Troubleshooting

### external-dns pod is running but DNS record is missing

Check logs:

```bash
kubectl -n external-dns logs deploy/external-dns-unifi -c external-dns --tail=120
kubectl -n external-dns logs deploy/external-dns-unifi -c webhook --tail=120
```

Check the ingress has a host under `lazy.sh` and an address:

```bash
kubectl get ingress -A
```

Check UDM DNS directly:

```bash
dig +short @192.168.9.1 <host>
dig +short @172.16.50.1 <host>
```

### cert-manager challenge stuck on DNS propagation

Check challenge:

```bash
kubectl -n <namespace> describe challenge
```

If reason says DNS record not propagated:

1. Confirm Cloudflare record exists through API or dashboard.
2. Confirm UDM mirror CronJob is running:

```bash
kubectl -n external-dns get cronjob acme-dns01-udm-mirror
kubectl -n external-dns logs job/<latest-mirror-job>
```

3. Query local DNS:

```bash
dig +short @172.16.50.1 TXT _acme-challenge.<host>
dig +short @192.168.9.1 TXT _acme-challenge.<host>
```

If the current challenge key is missing from UDM local DNS, run the mirror job manually:

```bash
kubectl -n external-dns create job --from=cronjob/acme-dns01-udm-mirror acme-dns01-udm-mirror-manual-$(date +%s)
```

### After changing staging to production

If a Certificate was already issued by staging and you switch to production, delete the TLS secret to force reissue:

```bash
kubectl -n ingress-smoke annotate ingress whoami cert-manager.io/cluster-issuer=letsencrypt-production --overwrite
kubectl -n ingress-smoke delete secret whoami-k8s-lazy-sh-tls
kubectl -n ingress-smoke wait --for=condition=Ready certificate/whoami-k8s-lazy-sh-tls --timeout=300s
```

### Clean stale UDM ACME TXT records

The mirror currently creates missing active challenge TXT records but does not aggressively clean old ones. Extra stale TXT values normally do not break DNS-01 as long as the current key is also present.

If cleanup is needed, inspect UDM static DNS records first and delete only stale `_acme-challenge.*` TXT records after confirming no active cert-manager Challenge needs them.

## Next GitOps step

Once GitHub access is available, commit these manifests and docs into the real cluster repo/GitOps layout. Do **not** commit plaintext secrets. Use SOPS/Age or an external secret manager for:

- `external-dns-unifi-secret`
- `cloudflare-api-key`

Suggested future layout:

```text
cluster/core/external-dns-unifi/
cluster/core/cert-manager/
cluster/core/acme-dns01-udm-mirror/
cluster/apps/ingress-smoke/
```
