# Hari 3 — Prometheus + Grafana Observability Stack

- **Namespace:** monitoring (Helm release: kps)
- **Grafana URL:** http://localhost:3000 (admin / admin123)
- **Prometheus URL:** http://localhost:9090

## Komponen yang Berhasil Berjalan
- `kps-grafana` (3/3 Running)
- `prometheus-kps-kube-prometheus-stack` (2/2 Running)
- `alertmanager-kps-kube-prometheus-stack` (2/2 Running)
- `kps-kube-state-metrics` (1/1 Running)
- `kps-prometheus-node-exporter` (1/1 Running - patched Docker Desktop mountPropagation)
- `ServiceMonitor/web` terdaftar di namespace belajar

## Temuan & Troubleshooting Nyata (DevSecOps Case)
- **Problem:** `node-exporter` crash dengan pesan `path / is mounted on / but it is not a shared or slave mount` (Exit code 128).
- **Root Cause:** VM Docker Desktop macOS me-mount root filesystem secara private, menolak HostToContainer mountPropagation.
- **Solution:** Patch JSON pada DaemonSet `kps-prometheus-node-exporter` untuk menghapus `mountPropagation` dari rootfs volume mount.

## Verifikasi PromQL & Stress Test
- Membaca metrik container memory: `container_memory_working_set_bytes{namespace="belajar",pod=~"web.*"}`.
- Uji beban CPU via stress pod dan verifikasi lonjakan metrik: `sum(rate(container_cpu_usage_seconds_total{namespace="belajar"}[1m]))`.
