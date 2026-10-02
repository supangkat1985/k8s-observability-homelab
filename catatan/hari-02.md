# Hari 2 — Deployment, ReplicaSet, Service (SELESAI)

- **Tanggal:** 28 Sep 2026
- **Kluster:** kind `desktop-control-plane`, v1.35.0, 1 node, `Ready`
- **Namespace:** `belajar` (dibuat dari nol: `delete namespace` → `create namespace`)
- **Manifest:** `web.yaml` — Deployment `web` (3 replika, `nginx:1.27-alpine`, requests 50m/64Mi, limits 200m/128Mi, readinessProbe `/` port http delay=2s period=5s) + Service `web` ClusterIP 80
- **Catatan versi folder:** `02-deployment.yaml` (2 replika, tanpa Service) = versi lama, TIDAK dipakai.

## 1. Pod kembali sendiri setelah dihapus

```bash
kubectl apply -f web.yaml
kubectl get all -n belajar
kubectl delete pods -n belajar -l app=web
kubectl get pods -n belajar -o wide
kubectl describe rs -n belajar
kubectl get events -n belajar --sort-by=.lastTimestamp | tail -15
```

Bukti:
- `replicaset.apps/web-688747b6f8   DESIRED 3 / CURRENT 3 / READY 3`
- Enam baris `SuccessfulCreate` dari `replicaset-controller` (dua kali penghapusan penuh).
- Nama Pod berganti tiap kali: `8n67f/dwgwp/mshc7` → `9qsp5/c5rwf/nnj49` → `fjcsl/wvcpz/zn8pw` → `dnngg/kr8kc/wjbrt`.
- IP Pod berganti: `10.244.0.5–.7` → `.8–.10` → `.11–.13`. Nama ReplicaSet tetap.

**Kesimpulan:** Pod hilang karena hanya objek sekali pakai; ReplicaSet terus menyamakan "diminta 3" dengan "yang ada".

## 2. Service & EndpointSlice

```bash
kubectl get endpointslices -n belajar -l kubernetes.io/service-name=web -o wide
kubectl port-forward -n belajar svc/web 8080:80
```

- `web-gmcxg   IPv4   80   10.244.0.12,10.244.0.11,10.244.0.13` → IP Pod yang melayani Service.
- `http://localhost:8080` → halaman nginx; port `:8081` → error.

**Kesimpulan:** Service punya alamat tetap karena daftar endpoint-nya mengikuti Pod yang berganti-ganti.

## 3. Rolling update tanpa downtime

```bash
kubectl get pods -n belajar -w          # terminal 1
kubectl set image deploy/web nginx=nginx:1.29-alpine -n belajar   # terminal 2
```

Hasil di watcher:
- Pod baru `web-86c89b8ffb-jwfkm` muncul `Pending` → `ContainerCreating` → `Running` **sementara tiga Pod lama masih Running** (jumlah sempat 4).
- Setelah Pod baru `1/1`, Pod lama `web-688747b6f8-*` baru `Terminating`. Pola berulang satu-satu.
- Hash ReplicaSet berganti: `web-688747b6f8` → `web-86c89b8ffb`.

**Kesimpulan:** `maxSurge: 1, maxUnavailable: 0` — Pod pengganti naik dulu, Pod lama turun belakangan; tidak ada momen jumlah Pod siap nol.

## 4. Rollback

```bash
kubectl rollout history deploy/web -n belajar     # REVISION 1, 2 (CHANGE-CAUSE <none>)
kubectl rollout undo deploy/web -n belajar
kubectl get deploy web -n belajar -o jsonpath='{.spec.template.spec.containers[0].image}{"  rev="}{.metadata.annotations.deployment\.kubernetes\.io/revision}{"\n"}'
kubectl get rs -n belajar -o 'custom-columns=NAME:.metadata.name,REV:.metadata.annotations.deployment\.kubernetes\.io/revision,DESIRED:.spec.replicas,READY:.status.readyReplicas,IMAGE:.spec.template.spec.containers[0].image'
```

Hasil:

```
nginx:1.27-alpine  rev=3

NAME             REV   DESIRED   READY    IMAGE
web-688747b6f8   3     3         3        nginx:1.27-alpine
web-86c89b8ffb   2     0         <none>   nginx:1.29-alpine
```

**Kesimpulan kunci:** nama ReplicaSet ≠ nomor revisi. `undo` menulis kembali template lama, Deployment menemukan ReplicaSet lama yang pod-template-hash-nya cocok, menaikkannya dari 0 → 3, lalu memberi nomor revisi baru (3) pada objek itu. Karena itu revisi 1 tidak hilang—hanya nomornya dipakai ulang.

## Jebakan yang muncul hari ini

- **Salah ketik `deply`** → `error: the server doesn't have a resource type "deply"`.
- **Warning `previously managed with 'kubectl apply'` saat `undo`** → bukan error; `undo` mem-patch objek sehingga anotasi `last-applied-configuration` tidak ikut diperbarui. Obatnya: `kubectl apply -f web.yaml` sekali lagi setelah rollback.
- **`kubectl get all` di v1.35 tidak menampilkan ReplicaSet** → pakai `kubectl get rs -n belajar` eksplisit.
- **`0/1` beberapa detik pertama** → readinessProbe belum lewat (`delay=2s, period=5s`), bukan kegagalan.
- **Pod lama tampil `0/1 Completed`** → sisa objek yang belum di-GC kubelet; hilang sendiri.
- **zsh glob** pada `custom-columns=` → kutip seluruh ekspresi `-o 'custom-columns=...'`.
- **`CHANGE-CAUSE <none>`** → hanya terisi bila anotasi `kubernetes.io/change-cause` diisi manual (mis. `kubectl annotate`).

## Perintah yang berhasil dipakai

```bash
kubectl get nodes
kubectl create namespace belajar
kubectl apply -f web.yaml
kubectl get all -n belajar
kubectl get rs -n belajar
kubectl get pods -n belajar -o wide
kubectl delete pods -n belajar -l app=web
kubectl describe rs -n belajar
kubectl get events -n belajar --sort-by=.lastTimestamp | tail -15
kubectl get endpointslices -n belajar -l kubernetes.io/service-name=web -o wide
kubectl port-forward -n belajar svc/web 8080:80
kubectl set image deploy/web nginx=nginx:1.29-alpine -n belajar
kubectl rollout history deploy/web -n belajar
kubectl rollout undo deploy/web -n belajar
```

## Yang masih bingung / belum dicoba

- Ingress di kind belum dicoba (`14-ingress-opsional.yaml` masih menunggu).
- Belum mengisi `kubernetes.io/change-cause` supaya `rollout history` terbaca manusiawi.

## Rencana berikutnya

Hari 3 — Prometheus + Grafana (`kube-prometheus-stack`, `36-values-kps.yaml`). Butuh RAM lega di Docker Desktop (minimal 6–8 GB); jalankan di sesi terpisah.
