# k8s-observability-homelab — MULAI DARI SINI

Rencana 7 hari: Kubernetes pertama → Prometheus + Grafana → Loki → Alert ke Telegram.
Detail materi: `minggu1-kubernetes-observability.md` (dokumen terpisah).

## Isi folder
| File | Untuk | Hari |
|---|---|---|
| `00-namespace.yaml` | namespace `belajar` + `monitoring` | 0 |
| `01-pod-nginx.yaml` | Pod pertama (lihat ini hilang saat dihapus) | 1 |
| `02-deployment.yaml` | Deployment 2 replika + readiness probe | 2 |
| `03-service.yaml` | Service `web` (ClusterIP) | 2 |
| `04-ingress-opsional.yaml` | Ingress — hanya kalau ingress diaktifkan | 2 |
| `05-alert-rules.yaml` | PrometheusRule (restart, memori, pod tidak Ready) | 6 |
| `06-values-kps.yaml` | values kube-prometheus-stack (tanpa password) | 3 |
| `07-values-alertmanager.example.yaml` | contoh Alertmanager → Telegram (**contoh, jangan commit isian asli**) | 6 |
| `perintah-harian.md` | semua perintah siap salin per hari | 0–7 |
| `catatan/TEMPLATE-catatan-sesi.md` | catatan tiap sesi — bahan README Hari 7 | tiap sesi |

## Urutan Hari 0 (30–60 menit)
1. Docker Desktop → Settings → **Kubernetes → Enable Kubernetes** → Apply & Restart.
2. Settings → **Resources** → minimal **4 CPU / 6 GB RAM** (kurang dari ini → pod `Pending`/`OOMKilled`).
3. `brew install kubectl helm kubeconform`
4. `kubectl config use-context docker-desktop && kubectl get nodes` → 1 node **Ready**.
5. `kubectl apply -f 00-namespace.yaml`
6. `kubeconform -strict -summary *.yaml` → semua `valid`.

## Aturan aman
- **Jangan commit** token bot Telegram atau password Grafana. Isian asli masuk ke `values-alertmanager.local.yaml`, sudah masuk `.gitignore`.
- Password Grafana dikirim lewat `--set` dari variabel shell (`read -rs`), bukan ditulis di file YAML atau shell history.
- Pod `Pending` setelah install stack = RAM Docker Desktop kurang, bukan chart rusak.
- Alert tidak muncul di Prometheus = label `release: kps` tidak sama dengan nama rilis Helm.
- Loki "data source not found" di Grafana = harus didaftarkan manual (Hari 5).

## Setelah tiap sesi
Isi `catatan/hari-XX.md` dari template: yang dicoba, hasil, error persisnya, penyebab, yang masih bingung, durasi.
Kalau mentok >60 menit: berhenti, catat, kirim pesan error-nya ke Jessica.