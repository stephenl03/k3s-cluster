# Optional Traefik Helm deployment

The active `nuc-phase1` cluster currently uses the k3s bundled Traefik in `kube-system` with LoadBalancer IP `172.16.50.200` from MetalLB.

These older Helm-managed Traefik manifests are parked to avoid replacing the working bundled controller during core recovery. Review and migrate deliberately if/when Traefik should be managed by Flux.
