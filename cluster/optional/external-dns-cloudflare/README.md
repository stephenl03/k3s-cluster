# Optional/stale Cloudflare external-dns deployment

The active `nuc-phase1` recovery path uses UniFi webhook external-dns in `cluster/core/external-dns`.

These older Cloudflare-mode external-dns manifests are parked because they used namespace `networking`, `policy: sync`, Cloudflare-proxied records, and an older ownership model that does not match the live cluster.
