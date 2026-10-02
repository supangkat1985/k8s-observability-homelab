# Hari 3 — Prometheus + Grafana (paket eksekusi)

**Tanggal:** ____________________  **Durasi:** ________ menit
**RAM Docker Desktop saat mulai:** ____ GB  **CPU:** ____ core
**Cluster:** kind `desktop-control-plane` v1.35.0, 1 node Ready
**Syarat lulus:** grafana terbuka di :3000, dan `http://localhost:9090/targets` menampilkan target `web` = **UP**

> Jalankan saat RAM Docker Desktop **minimal 6 GB**. Kalau pod nyangkut `Pending` dan
> tidak juga Running dalam 5 menit, stop — bukan chart rusak, itu RAM. Catat error-nya
> di bawah lalu cek `docker stats`.

---

##pra-syarat — cek dulu, jangan langsung helm install

```bash
kubectl get nodes
kubectl get ns belajar monitoring
docker stats --no-stream          # pastikan RAM Docker Desktop tidak mentok
```

Kalau `namespace monitoring` belum ada:
```bash
kubectl apply -f 00-namespace.yaml
```

---

## LANGKAH 1 — cari versi chart terbaru

Dokumen kamu menyebut chart 88.x. ArtifactHub perchecked saya menunjukkan **91.6.0**
— itu 3 major version di depan, jadi values-nya bisa berbeda.

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm search repo prometheus-community/kube-prometheus-stack --versions | head -5
```

**Tulis di sini versi yang kamu lihat:**
```
NAME                                    CHART VERSION
kube-prometheus-stack                   ______
```

Pentingkan dengan benar — `helm search repo` urut dari versi **terbaru**.

---

## LANGKAH 2 — install

Password Grafana **tidak** ditulis ke file YAML. Diminta interaktif supaya tidak masuk
shell history dan tidak ikut ter-commit.

```bash
read -rs -p "Password Grafana: " GRAFANA_PW && echo
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  --namespace monitoring -f 06-values-kps.yaml \
  --set grafana.adminPassword="$GRAFANA_PW"
unset GRAFANA_PW
```

- Username Grafana: `admin`
- Password: yang baru saja kamu ketik (tidak ada di file mana pun)

---

## LANGKAH 3 — tunggu pod Running

```bash
kubectl -n monitoring get pods -w
```

**Isi yang kamu lihat:**

```
NAME                                  READY   STATUS    RESTARTS   AGE
kps-kube-prometheus-stack-xxxxx-xxxxx  1/1     Running   0          2m
kps-grafana-xxxxx                     1/1     Running   0          1m
kps-alertmanager-xxxxx                2/2     Running   0          1m
...
```

`Ctrl-C` setelah semua `Running`. LaMu sekali pod `1/1 Running`.

Waktu install: ____ menit

---

## LANGKAH 4 — buka Grafana

```bash
kubectl -n monitoring port-forward svc/kps-grafana 3000:80
```

Buka **http://localhost:3000** → login `admin` / password tadi.

Yang harus kamu temukan di UI:
- Home → ada dashboard bawaan ("Kubernetes / Compute Resources / Cluster" dll)
- Buka satu → **tidak boleh kosong**. Kalau kosong, grafana.py-nya masih bisa
  dashboard-nya belum sync — tunggu 1 menit, refresh.
- **Status → Prometheus** → lihat daftar target

Biarkan terminal ini tetap jalan.

---

## LANGKAH 5 — daftarJawab app `web` ke Prometheus

Ini bagian yang paling sering dilewatkan, dan sebagian besar alasan orang czy
"Grafana-nya kosong".

Tanpa ServiceMonitor, Prometheus **hanya** meng-scrape komponen Kubernetes.
Pod `web` milikmu di namespace `belajar` tidak akan pernah muncul.

```bash
# terminal baru
kubectl apply -f 10-servicemonitor-web.yaml
kubectl -n belajar get servicemonitor web
```

Output harus:
```
NAME    AGE
web     3s
```

Sekarang cek di terminal port-forward Prometheus (terminal ketiga):

```bash
kubectl -n monitoring port-forward svc/kps-prometheus 9090:9090
```

Buka **http://localhost:9090/targets** → cari baris `web`.

### ⛔ Kamu akan menemukan ini (dan itu memang disengaja)

Status `web` akan **DOWN**, dengan error seperti:
```
connection refused
```
atau
```
server returned HTTP status 404 Not Found
```

**Ini bukan salah konfigurasi Prometheus. Ini benar.**

`nginx:1.27-alpine` **tidak punya** endpoint `/metrics` di port 80. Port 80 itu untuk
HTML, bukan untuk metrik. Prometheus benar-benar mencoba mengetuk pintu yang memang
tidak ada — dan UI-nya memperlihatkan itu dengan jujur.

Yang sebenarnya dilakukan stack ini:
- `node-exporter` → metrik node (CPU, RAM, disk, network)
- `kube-state-metrics` → metrik status objek K8s (jumlah pod, restart, dsb)
- **cAdvisor/kubelet** → metrik **container & pod** dari semua pod, termasuk `web`

Jadi kamu **tidak perlu** nginx-exporter untuk melihat CPU/memori Pod. Pod `web` sudah
tercover: load eventnya apa yang lain.

---

## LANGKAH 6 — bukti kalau benar jalan

```bash
# di terminal baru
kubectl -n monitoring port-forward svc/kps-prometheus 9090:9090
# buka http://localhost:9090  →  menu Status → Targets
```

Query di **http://localhost:9090/graph** (atau Grafana Explore) — ketik satu per satu,
`Graph` di bawahnya harus **tidak kosong**:

```
up{job=~".*node.*"}
```
→ grafik: jumlah target `kube-node-exporter` yang hidup (harus 1)

```
sum(rate(container_cpu_usage_seconds_total{namespace="belajar",pod=~"web.*"}[5m]))
```
→ grafik: pemakaian CPU pod `web`, dalam **core**

```
container_memory_working_set_bytes{namespace="belajar",pod=~"web.*"}
```
→ grafik: memori pod `web`, dalam **byte**

```
kube_pod_container_status_restarts_total{namespace="belajar",pod=~"web.*"} > 0
```
→ hasil: **kosong** = pod `web` belum pernah restart. Kalau tidak kosong = ada yang restart.

```
kube_node_status_condition{node="desktop-control-plane",condition="Ready",status="true"} == 0
```
→ kosong = node Ready (nilai 1). Kalau hasilnya `1` = node bermasalah.

> **Penting:** metrik pod `web` sudah muncul **tanpa** ServiceMonitor, karena
> kubelet+cAdvisor men-scrape semua pod otomatis. ServiceMonitor hanya perlu kalau
> aplikasimu sendiri yang expose `/metrics` (Go app dengan `/metrics`, exporter).
> Jangan sampai ServiceMonitor `DOWN` membuat kamu mengira install-nya gagal.

> **Siapa yang bisa gagal:**'慎重'. Eh — ringkas saja: **Prometheus dan Grafana** adalah
> dua thing yang *harus* `UP`. ServiceMonitor `web` boleh `DOWN` untuk alasan di atas.

---

## LANGKAH 7 — buktikan monitoring benar-benar bereaksi

Sampai sini Prometheus cuma "terpasang", belum terbukti bahwa ia bereaksi.

```bash
# bikin pod yang boros CPU supaya ada yang terlihat bergerak di grafik
kubectl -n belajar run stress --image=polinux/stress \
  --restart=Never --rm -i --quiet -- \
  --cpu 2 --timeout 180s
```

Buka Graph → `up{job=~".*node.*"}` atau query CPU pod `web`, klik **refresh** tiap
5 detik, klik **⏱ Range** di bagian atas untuk set range 15 menit, lalu klik refresh
lagi. Kamu harus melihat CPU meledak ke ~2 core.

**Lalu buktikan restart counter naik:**
```bash
kubectl -n belajar delete pod -n belajar -l app=web     # paksa pod mati
kubectl -n belajar get pods                              # pod baru, nama berbeda
```
→ di Graph: `kube_pod_container_status_restarts_total{namespace="belajar",pod=~"web.*"}`
TIDAK naik (restart bukan naik karena pod-nya memang baru dibuat).
Yang lebih jelas: `changes(kube_pod_container_status_restarts_total{...}[15m]) > 0`
— kalau ada pod yang restart, ini yang muncul.

---

## LANGKAH 8 — catat (jangan skip, ini yang jadi README Hari 7)

Copy blok ini ke `catatan/hari-03.md` atau isi manual. Isi yang **wajib** kosongkan
kalau tidak ada: error persisnya, screenshot.

```bash
# generate isi catatan
cat > catatan/hari-03.md <<'EOF'
# Hari 3 — Prometheus + Grafana

- **Tanggal / durasi:**
- **Chart version:**
- **RAM Docker Desktop:**
- **Namespace:** monitoring (release kps)
- **Grafana:** http://localhost:3000 (user admin)

## Yang dicoba
(helm install, port-forward Grafana, apply ServiceMonitor, query PromQL)

## Hasil
- Pod monitoring yang Running: 
- Target node-exporter: 
- Target ServiceMonitor web: DOWN, error: 
- Query yang berhasil dijawab: 
- Dashboard yang berhasil dibuka: 

## Yang gagal + pesan error persisnya
(kpaste paste di sini apa adanya)

## Penyebab yang ditemukan
(ngarang sendiri — ini yang dinilai saat interview)

## Yang masih bingung
## Waktu yang dihabiskan (menit)
EOF
```

---

## Kalau mentok

| Gejala | Penyebab | Obatnya |
|---|---|---|
| Pod `Pending` | RAM Docker Desktop kurang | Settings → Resources → 6–8 GB, restart Docker Desktop |
| Pod `CrashLoopBackOff` di `kps-kube-prometheus-stack` | image salah / chart vs k8s mismatch | `kubectl -n monitoring logs deploy/kps-kube-prometheus-stack` |
| `helm` error `unknown flag: --values` | pakai helm v2 | `helm version` → harus v3 |
| Grafana 404 atau white screen | pod grafana belum siap | tunggu 30 detik, `kubectl -n monitoring get pods` |
| Target `web` DOWN `connection refused` | **expected** nginx tidak punya /metrics | abaikan, sudah dijelaskan LANGKAH 5 |
| Target `web` DOWN `404 Not Found` | **expected** nginx balas 404 ke /metrics | abaikan, sudah dijelaskan LANGKAH 5 |
| Port 3000 sudah dipakai | ada proses lain | `lsof -i :3000` → `kill <pid>` |
| `no matches for kind "ServiceMonitor"` | CRD belum ada | install stack dulu (LANGKAH 2), baru apply ServiceMonitor |

**Aturan keras:** mentok > 60 menit di satu langkah → berhenti, catat error persisnya,
lalu tanya. Janganobu mencoba chart lain.

---

## Setelah selesai

1. `catatan/hari-03.md` terisi
2. Screenshot: dashboard Grafana yang tidak kosong + halaman `http://localhost:9090/targets`
3. Dua file baru ada di repo: `10-servicemonitor-web.yaml`, `LATIHAN-HARI-3.md`
4. Kalau Hari 3 selesai → lanjut Hari 4 (query PromQL, sudah ada di `perintah-harian.md`)

**Catatan versi yang perlu kamu tahu:**
- Repo `k8s-observability-homelab` **belum** git repo (`git log` = bukan repository).
  Kalau mau masuk ke portofolio/CV, `git init` dulu — sekarang semua historinya
  hilang, file cuma ada di disk ini.
- `catatan/hari-01.md` masih template kosong. 5 menit untuk mengisinya dari
  pengalaman Hari 1 kamu — itu yang bikin portofoliomu terlihat konsisten.
- Catatan Hari 2 baris 111 menulis `36-values-kps.yaml` — itu typo, file aslinya
  `06-values-kps.yaml`. Sudah saya koreksi di memory supaya tidak terulang.