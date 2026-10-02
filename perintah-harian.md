# Perintah yang sudah pasti dipakai — salin blok demi blok, jangan sekaligus.

## Hari 0 — siapkan
```bash
# Docker Desktop -> Settings -> Kubernetes -> Enable Kubernetes -> Apply & Restart
# Docker Desktop -> Settings -> Resources -> minimal 4 CPU, 6 GB RAM
brew install kubectl helm kubeconform
kubectl config use-context docker-desktop
kubectl get nodes                     # harus: 1 node, STATUS Ready
```

## Hari 0 — namespace kerja
```bash
kubectl apply -f 00-namespace.yaml
kubectl config set-context --current --namespace=belajar
```

## Hari 1 — Pod pertama (dan kenapa ia tidak kembali sendiri)
```bash
kubectl apply -f 01-pod-nginx.yaml
kubectl get pods -o wide
kubectl describe pod web -n belajar            # baca bagian Events
kubectl logs web -n belajar
kubectl exec -it web -n belajar -- sh
kubectl port-forward -n belajar pod/web 8080:80   # buka http://localhost:8080
kubectl delete pod web -n belajar && kubectl get pods -n belajar
```

## Hari 2 — Deployment, Service, rollback
```bash
kubectl apply -f 02-deployment.yaml
kubectl get deploy,rs,pods -n belajar -o wide
kubectl scale deploy/web -n belajar --replicas=4
kubectl rollout status deploy/web -n belajar
kubectl rollout undo deploy/web -n belajar
kubectl delete pod -n belajar -l app=web --wait=false && kubectl get pods -n belajar -w
kubectl apply -f 03-service.yaml
kubectl get endpoints web -n belajar       # kalau kosong: selector tidak cocok!
kubectl port-forward -n belajar svc/web 8081:80
```

## Hari 3 — Prometheus + Grafana
```bash
# 0. cek chart versi TERBARU dulu (dokumen kamu masih 88.x, ArtifactHub kini 91.x)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm search repo prometheus-community/kube-prometheus-stack --versions | head -5

# 1. pastikan namespace monitoring ada
kubectl apply -f 00-namespace.yaml
kubectl get ns belajar monitoring

# 2. password Grafana via variabel shell, JANGAN ditulis ke file YAML
read -rs -p "Password Grafana: " GRAFANA_PW && echo
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  --namespace monitoring -f 06-values-kps.yaml \
  --set grafana.adminPassword="$GRAFANA_PW"
unset GRAFANA_PW

# 3. tunggu semua pod Running (3-8 menit)
kubectl -n monitoring get pods -w

# 4. VERIFIKASI scrape target — bagian ini sering dilewatkan
kubectl -n monitoring port-forward svc/kps-grafana 3000:80   # http://localhost:3000
#    log in user: admin / password yang kamu ketik tadi
#    Grafana -> Status -> Prometheus (atau Explore) -> cek "up" = 1 per target
#    Command line:
kubectl -n monitoring exec deploy/kps-grafana -c grafana -- true 2>/dev/null || true
kubectl -n monitoring port-forward svc/kps-prometheus 9090:9090   # terminal lain
#    buka http://localhost:9090/targets -> cari baris "web" -> harusnya "UP"
```

### Hari 3b — daftarkan pod `web` supaya TERLIHAT di Grafana
Tanpa langkah ini, pod `web` di namespace `belajar` tidak akan muncul di mana pun.
```bash
kubectl apply -f 10-servicemonitor-web.yaml
kubectl -n belajar get servicemonitor web           # harus ada
# tunggu 30-60 detik, cek lagi di Prometheus UI -> http://localhost:9090/targets
```
> **Masalah yang akan kamu temui di langkah ini:** `nginx:1.27-alpine` TIDAK punya
> `/metrics` di port 80, jadi target `web` akan muncul dengan status
> `DOWN` / error `404` atau `connection refused`.
> ITU BUKAN SALAHMU — itu justru pelajaran terbaik Hari 3.
> Cara memperbaikinya ada di `LATIHAN-HARI-3.md` bagian "Perbaiki target web".

## Hari 4 — query PromQL (Grafana Explore)
```promql
sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="belajar"}[5m]))
sum by (pod) (container_memory_working_set_bytes{namespace="belajar"})
kube_pod_container_status_restarts_total{namespace="belajar"} > 3
kube_node_status_condition{condition="Ready",status="true"} == 0
```

## Hari 5 — Loki + Alloy (Promtail sudah EOL 2026-03-02, jangan pakai lagi)
```bash
# chart loki sekarang di repo grafana-community, Alloy di repo grafana (lama)
helm repo add grafana-community https://grafana-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
# Loki monolithic (1 pod, storage PVC lokal) -> file 08
helm upgrade --install loki grafana-community/loki -n monitoring -f 08-loki-values.yaml
# Alloy (DaemonSet) kumpulkan log semua pod -> kirim ke Loki -> file 09
helm upgrade --install alloy grafana/alloy -n monitoring -f 09-alloy-values.yaml
kubectl -n monitoring get pods -w     # tunggu loki + alloy Running
```
Lalu di Grafana: Connections → Data sources → Add → **Loki**, URL `http://loki:3100` → Save & Test.
```logql
{namespace="belajar"} |= "error"
{app="web"} |~ "(?i)error|fail"
```
> Catatan: `grafana/loki-stack` (loki-stack + promtail) SUDAH DEPRECATED. Pakai `grafana-community/loki`
> (monolithic) + `grafana/alloy` di folder ini. Alloy jalan sebagai DaemonSet dan push ke `http://loki:3100`.

## Hari 6 — alert rule + Alertmanager ke Telegram
```bash
kubectl apply -f 05-alert-rules.yaml
kubectl -n monitoring port-forward svc/kps-alertmanager 9093:9093   # cek status rule
cp 07-values-alertmanager.example.yaml values-alertmanager.local.yaml   # isi token di sini
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  -n monitoring -f 06-values-kps.yaml -f values-alertmanager.local.yaml \
  --set grafana.adminPassword="$GRAFANA_PW"
# uji alert: paksa pod crash
kubectl -n belajar scale deploy/web --replicas=1
kubectl -n belajar exec -it deploy/web -- sh -c 'kill 1'   # container restart -> alert
```

## Validasi manifest sebelum apply
```bash
kubeconform -strict -summary *.yaml
```