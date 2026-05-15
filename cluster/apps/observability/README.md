# Observability

This stack is the Kubernetes-first observability migration target.

## Included now

- `kube-prometheus-stack`: Prometheus, Alertmanager, kube-state-metrics, node-exporter, and bundled Grafana.
- `loki`: single-binary Loki with filesystem-backed persistence for short-retention cluster logs.
- `promtail`: DaemonSet for Kubernetes/containerd pod logs from `/var/log/pods` and `/var/log/containers`.
- `unpoller`: existing UniFi metrics exporter, scraped by Prometheus through an additional ServiceMonitor rendered by `kube-prometheus-stack`.

## Intentionally deferred

- Docker host log scraping. Some apps still run on the Docker host, but the *arr/Plex/etc workloads are expected to move into Kubernetes later. Start with Kubernetes-native logs and add host log collection only if it is still needed after that migration.
- Gatus/blackbox probes for uptime checks.
- SMART/disk telemetry via smartctl-exporter.
- Grafana Operator/dashboard CRDs. The bundled Grafana is simpler for the first migration pass.
- VictoriaLogs/Fluent Bit. chr1sd's stack uses this pattern well; consider it later if Loki/Promtail becomes too heavy or Promtail deprecation becomes painful.
