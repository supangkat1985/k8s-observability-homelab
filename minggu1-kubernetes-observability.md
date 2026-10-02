# Minggu 1 — Kubernetes + Observability di Docker Desktop (MacBook)

Target 7 hari: cluster Kubernetes jalan di MacBook, aplikasi nyata berjalan di dalamnya,
lalu Prometheus + Grafana memantau aplikasi itu, dan Loki mengumpulkan lognya.
Semua dijalankan lokal — tidak perlu VPS, tidak perlu kartu kredit, aman untuk kantor.

Catatan versi (dicek 14 Sep 2026): chart `kube-prometheus-stack` versi 88.x,
appVersion prometheus-operator v0.93.x — Grafana 13.2, Prometheus, Alertmanager,
kube-state-metrics 2.20, node-exporter 1.12. Kubernetes bawaan Docker Desktop = 1 node.

---

## Hari 0 — Siapkan lingkungan (30–60 menit)

1. Docker Desktop → **Settings → Kubernetes → Enable Kubernetes** → Apply & Restart.
   Debian-based image jalan normal di Docker Desktop (pakai kernel VM Docker, bukan macOS).
2. Beri resource yang cukup: Settings → Resources → minimal **4 CPU, 6–8 GB RAM**
   (kube-prometheus-stack butuh ruang; kalau kurang, pod akan `Pending`/`OOMKilled`).
3. Pasang alat bantu (pilih lewat Homebrew):
   ```bash
   brew install kubectl helm
   brew install kubeconform   # validasi YAML manifest
   kubectl version --short && helm version
   kubectl get nodes          # harus muncul 1 node berstatus Ready
   ```
4. Set namespace kerja supaya rapi:
   ```bash
   kubectl create namespace belajar
   kubectl config set-context --current --namespace=belajar
   ```

**Lulus hari 0 kalau:** `kubectl get nodes` menampilkan 1 node Ready dan `helm version` jalan.

---

## Hari 1 — Dasar kubectl & Pod pertama (2 jam)

Tulis sendiri, jangan copy-paste buta. File: `01-pod-nginx.yaml`
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: web
  labels:
    app: web
spec:
  containers:
    - name: nginx
      image: nginx:1.27-alpine
      ports:
        - containerPort: 80
```
Latihan wajib (ketik, amati, tulis jawaban di catatan):
```bash
kubectl apply -f 01-pod-nginx.yaml
kubectl get pods -o wide
kubectl describe pod web          # baca bagian Events
kubectl logs web
kubectl exec -it web -- sh        # lihat isi container
kubectl port-forward pod/web 8080:80   # buka http://localhost:8080
kubectl delete pod web            # pod = sekali pakai, hilang lalu dibuat ulang
```
Pertanyaan yang harus bisa dijawab: apa bedanya `describe` dan `logs`? Kenapa Pod yang
dihapus tidak kembali sendiri? (Jawaban: karena belum ada controller seperti Deployment.)

---

## Hari 2 — Deployment, Service, Ingress (3 jam)

File: `02-deployment.yaml` (buat sendiri, minimal 2 replika, image `nginx:1.27-alpine`),
`03-service.yaml` (ClusterIP port 80 → targetPort 80), `04-ingress.yaml`.

```bash
kubectl apply -f 02-deployment.yaml
kubectl get deploy,rs,pods -o wide     # lihat rantai Deployment → ReplicaSet → Pod
kubectl scale deploy web --replicas=4
kubectl rollout status deploy/web
kubectl rollout undo deploy/web        # rollback
kubectl delete pod <salah-satu-pod>    # perhatikan: langsung diganti otomatis
```
Sambungkan dari MacBook: cara termudah di Docker Desktop = aktifkan ingress bawaan
(Docker Desktop → Settings → Kubernetes → enable Ingress) atau pakai `port-forward`
untuk belajar. Tulis di catatan: kenapa Service perlu ada padahal Pod sudah jalan?

---

## Hari 3 — Deploy PROMETHEUS + GRAFANA (3 jam)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana-community.github.io/helm-charts
helm repo update
kubectl create namespace monitoring
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.adminPassword='ganti-password-ini' \
  --set prometheus.prometheusSpec.retention=6h \
  --set prometheus.prometheusSpec.resources.requests.memory=512Mi \
  --set alertmanager.enabled=true
kubectl -n monitoring get pods -w      # tunggu semua Running (bisa 3–8 menit)
```
Akses Grafana:
```bash
kubectl -n monitoring port-forward svc/kps-grafana 3000:80
# buka http://localhost:3000  → user: admin, password: yang di-set di atas
```
Jelajahi dashboard bawaan: Kubernetes / Compute Resources / Cluster, Nodes, Pods,
Node Exporter / Nodes. Cari 3 metrik ini di Grafana Explore dan tulis artinya:
`node_cpu_seconds_total`, `kube_pod_container_status_restarts_total`,
`container_memory_working_set_bytes`.

**Catatan penting:** password di atas hanya untuk latihan lokal. Jangan pakai password
yang sama dengan akun lain, dan simpan hanya di MacBook — bukan di repo GitHub.

---

## Hari 4 — Kube-state-metrics & memahami PromQL (2–3 jam)

Target: bisa menulis query sendiri, bukan cuma melihat dashboard orang.
Latihan di Grafana Explore (tulis jawabannya di catatan):
```promql
# 1. Pemakaian CPU per pod (rate 5 menit)
sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="belajar"}[5m]))
# 2. Memori per pod
sum by (pod) (container_memory_working_set_bytes{namespace="belajar"})
# 3. Pod yang restart lebih dari 3 kali
kube_pod_container_status_restarts_total > 3
# 4. Node tidak siap (harus kosong = sehat)
kube_node_status_condition{condition="Ready",status="true"} == 0
```
Lalu uji tahan banting: hapus salah satu pod aplikasi dan lihat grafiknya bergerak.
Tulis di catatan: kenapa metrik `*_total` hampir selalu dipakai dengan `rate()`?

---

## Hari 5 — LOG dengan LOKI + promtail (3 jam)

```bash
helm upgrade --install loki grafana/loki-stack \
  --namespace monitoring \
  --set grafana.enabled=false \
  --set promtail.enabled=true \
  --set loki.resources.requests.memory=256Mi
```
Di Grafana: Connections → Data sources → Add → **Loki**, URL:
`http://loki:3100` → Save & Test. Lalu Explore → pilih Loki → query:
```logql
{namespace="belajar"} |= "error"
{app="web"} |~ "(?i)error|fail"
```
Latihan: sengaja buat error (misal `kubectl exec` lalu akses URL yang tidak ada),
temukan lognya di Loki, lalu tulis **runbook** kecil di catatan:
"gejala → di mana dilihat (metrik? log?) → tindakan".

---

## Hari 6 — ALERTING ke Telegram (2–3 jam)

Buat file `alert-rules.yaml` — aturan pertama yang benar-benar berguna:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: aturan-belajar
  namespace: monitoring
  labels:
    release: kps          # label harus cocok agar Prometheus memuatnya
spec:
  groups:
    - name: dasar
      rules:
        - alert: PodSeringRestart
          expr: increase(kube_pod_container_status_restarts_total[10m]) > 3
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Pod {{ $labels.pod }} restart >3x dalam 10 menit"
        - alert: MemoriPodTinggi
          expr: sum by (pod) (container_memory_working_set_bytes) > 500e6
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Pod {{ $labels.pod }} memakai >500MB"
```
```bash
kubectl apply -f alert-rules.yaml
kubectl -n monitoring port-forward svc/kps-alertmanager 9093:9093   # cek di UI
```
Kirim ke Telegram: buat bot lewat @BotFather, ambil **chat_id** (kirim pesan ke bot,
buka `https://api.telegram.org/bot<TOKEN>/getUpdates`), lalu di `values` chart tambahkan:
```yaml
alertmanager:
  config:
    route:
      receiver: telegram
      group_wait: 30s
      repeat_interval: 3h
    receivers:
      - name: telegram
        telegram_configs:
          - bot_token: "<TOKEN_BOT>"
            chat_id: <CHAT_ID>
            parse_mode: HTML
            send_resolved: true
```
Simpan `values-alertmanager.yaml` ini **di luar repo publik** (atau pakai
`kubectl create secret`), lalu `helm upgrade` ulang. Uji dengan mematikan salah satu
pod/push memori tinggi sampai alert benar-benar masuk ke Telegram Pak.

---

## Hari 7 — Rapikan jadi bukti portofolio (2 jam)

- Buat repo GitHub `k8s-observability-homelab` (boleh publik).
- Isi: semua YAML di atas + `values-*.yaml` **tanpa token** + `README.md` berisi:
  diagram alur (app → Service → Prometheus scrape → Grafana → Alertmanager → Telegram),
  daftar keputusan desain ("kenapa Loki bukan ELK untuk homelab", "kenapa retention 6h"),
  dan 2–3 runbook insiden.
- Screenshot: dashboard Grafana + alert yang masuk ke Telegram (sensor chat_id).
- Tulis di README **angka**: berapa waktu deteksi insiden sebelum vs sesudah ada alert.

**Lulus minggu 1 kalau:** repo berisi YAML yang valid, cluster jalan, Grafana menampilkan
metrik aplikasi Pak sendiri, log terkumpul di Loki, dan satu alert benar-benar sampai ke
Telegram. Itu sudah bisa ditulis di CV sebagai "membangun stack observability Prometheus/
Grafana/Loki di Kubernetes", dengan bukti yang bisa dilihat perekrut.

---

## Jebakan yang hampir pasti Pak temui

- **Pod `Pending`** setelah install kube-prometheus-stack → RAM Docker Desktop kurang;
  naikkan resource atau kecilkan request memori.
- **Alert tidak muncul di Prometheus** → label `release: kps` tidak cocok dengan nama
  rilis Helm yang dipakai (kalau rilisnya dinamai lain, sesuaikan labelnya).
- **Grafana Loki "Data source not found"** → Loki dipasang dengan `grafana.enabled=false`,
  jadi harus didaftarkan manual seperti Hari 5.
- **`kube-state-metrics` menumpuk banyak deret** → normal; pakai `sum by (pod)` agar tidak
  membanjiri grafik.
- **Ingress di Docker Desktop** yang sering bikin bingung → untuk belajar, `port-forward`
  sudah cukup; ingress bisa ditunda ke minggu berikutnya.