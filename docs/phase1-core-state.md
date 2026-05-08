# Phase 1 core state

_Last updated: 2026-05-08_

This repository has been updated to match the proven live `nuc-phase1` k3s core state as closely as possible without applying manifests to the cluster.

## Live-aligned core choices

- **MetalLB**: chart `0.15.3`, pool `k8s-lb-pool`, L2 advertisement `k8s-l2`, address range `172.16.50.200-172.16.50.240`.
- **cert-manager**: chart `v1.19.1`; DNS-01 self-check uses only `1.1.1.1:53` with pod DNS `1.1.1.1` because `9.9.9.9` failed in this network.
- **external-dns**: moved into core as UniFi webhook mode in namespace `external-dns`, chart `1.21.1`, webhook image `ghcr.io/kashalls/external-dns-unifi-webhook:v0.8.2`, `policy: upsert-only`, `txtOwnerId: nuc-phase1`, `txtPrefix: k8s.`, domain `lazy.sh`.
- **ACME UDM mirror**: CronJob/RBAC mirrors active cert-manager DNS-01 challenge TXT records into UDM local DNS so cert-manager self-checks see the same challenge value that Let's Encrypt sees in Cloudflare.
- **Traefik**: keep using k3s bundled Traefik in `kube-system` for recovery. The old Helm-managed Traefik manifests are parked under `cluster/optional/traefik-helm`.
- **kube-vip**: parked under `cluster/optional/kube-vip`; not active while the cluster has one control-plane node and MetalLB handles service LoadBalancers.

## Secrets still required before Flux bootstrap

Do not commit plaintext values. Ensure encrypted SOPS secrets exist for:

- `cert-manager/cloudflare-api-key` key `api-key`.
- `external-dns/external-dns-unifi-secret` key `api-key`.
- `flux-system/cluster-secrets` values used by post-build substitution, including `SECRET_DOMAIN=lazy.sh` and `SECRET_CLOUDFLARE_EMAIL=stephenl@me.com`.

Flux is not live on the current cluster yet. Bootstrap only after SOPS/age material and Flux auth are deliberately restored.
