# kube-vip optional control-plane VIP

kube-vip is intentionally parked outside active Flux core for the current `nuc-phase1` state.

The live cluster has one control-plane node, and service `LoadBalancer` traffic is handled by MetalLB. A kube-vip API VIP should only be re-enabled after the cluster has multiple control-plane nodes and a deliberate stable API endpoint has been chosen.

The manifests in this directory are retained as a starting point, but must be reviewed before use; the old VIP/interface values may not match the current hosts.
