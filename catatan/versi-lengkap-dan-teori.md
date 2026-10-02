# Hari 2 — Deployment, Service, Rollout

Sesi Hari 1 sudah selesai dan berhasil: Pod `web` Running, `describe`, `logs`, `exec`, `port-forward`, lalu `delete pod` → `No resources found`. Semua artefak minggu ini masuk repo `k8s-observability-homelab`.

Target hari ini: **satu Pod yang kamu hapus sendiri tidak kembali. Sekarang bikin yang kembali sendiri.**

---

## 1. QoS: kenapa `web` tadi `Burstable`

`kubectl describe pod web` menampilkan `QoS Class: Burstable`. Itu bukan cosmetik — QoS menentukan **siapa yang diusir lebih dulu** saat node kehabisan resource.

Kriteria resmi (docs Kubernetes):

- **Guaranteed** — setiap container punya request & limit CPU dan memory, keduanya > 0, dan **nilai request = limit** (untuk memory dan CPU).
- **Burstable** — tidak memenuhi Guaranteed, tapi minimal satu container punya request atau limit CPU/memory.
- **BestEffort** — tidak ada container yang punya request **maupun** limit sama sekali.

Kasus Pod `web` kamu: `requests cpu 50m / memory 64Mi`, `limits cpu 200m / memory 128Mi` → request ≠ limit → **Burstable**. Kalau diubah jadi `limits == requests` untuk CPU dan memory, QoS naik ke Guaranteed.

Urutan pengusiran saat node tertekan: `BestEffort` dulu, baru `Burstable`, `Guaranteed` terakhir. Jadi jangan taruh beban penting sebagai BestEffort.

Sumber: https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/

---

## 2. Kenapa Pod tidak kembali sendiri (jawaban pertanyaan Hari 1)

Pod adalah **objek top-level** di Kubernetes — tidak ada yang mengawasinya. `kubectl apply -f pod.yaml` = kamu sendiri yang jadi "controller". Hapus pod-nya, selesai perkara.

Deployment menutup celah itu dengan **kontroler** yang terus-menerus membandingkan *keadaan yang diinginkan* (desired state) dengan *keadaan sebenarnya* (observed state):

Jenjang objeknya:

```text
Deployment (mau 3 replika, versi image X)
  └── ReplicaSet (penjaga jumlah replika untuk satu versi)
        └── Pod, Pod, Pod
```

- Deployment tidak pernah bikin Pod langsung. Ia bikin ReplicaSet; ReplicaSet yang bikin Pod.
- Kamu hapus satu Pod → ReplicaSet lihat "3 minta, 2 ada" → bikin satu lagi. Kamu tidak perlu ikut campur.
- Ganti image → Deployment bikin **ReplicaSet baru**, ReplicaSet lama dikurangi replikanya pelan-pelan. Itu isi `revisionHistoryLimit: 5` — 5 ReplicaSet lama disimpan supaya bisa di-`rollout undo`.
- `kubectl get rs` akan menampilkan hash image di nama ReplicaSet (mis. `web-7d9f8c6b54`). Hash itu = versi template Pod.

Sumber: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/

---

## 3. Kenapa butuh Service

Pod punya IP, tapi IP itu **tidak stabil**: setiap Pod dibuat ulang dapat IP baru (mudah dibuktikan — lihat Langkah 3). Kalau aplikasi lain menembak IP Pod langsung, alamatnya berubah tiap kali Pod lahir.

Service memberi **alamat + DNS name yang stabil**, dan menyeleksi Pod berdasarkan **label** (`selector`), bukan berdasarkan IP:

```text
DNS di dalam cluster:
  web.belajar.svc.cluster.local   →   Service (IP stabil)
                                        →  pilih Pod dengan label app=web
                                        →  Pod (IP berubah-ubah)
```

Karena seleksinya lewat label, Service otomatis ikut Pod baru tanpa diedit. `port-forward` yang kamu pakai Hari 1 hanya jembatan dari laptop ke satu Pod — bukan cara aplikasi bicara satu sama lain di dalam cluster.

Sumber: https://kubernetes.io/docs/concepts/services-networking/service/

---

## 4. Dua file yang kamu butuhkan

Sama seperti Hari 1: kerjakan dari dalam folder `k8s-observability-homelab`, satu folder per topik.

**`02-deployment/web-deployment.yaml`**

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: belajar
  labels:
    app: web
spec:
  replicas: 3
  revisionHistoryLimit: 5
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: nginx
          image: nginx:1.27-alpine
          ports:
            - name: http
              containerPort: 80
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 128Mi
          readinessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 2
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 10
            periodSeconds: 10
```

**`02-deployment/web-service.yaml`**

```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: belajar
  labels:
    app: web
spec:
  type: ClusterIP
  selector:
    app: web
  ports:
    - name: http
      port: 80
      targetPort: http
```

Keputusan desain di kedua file itu, supaya bisa kamu pertahankan kalau ditanya saat interview:

- **`selector.matchLabels` Deployment itu immutable setelah dibuat.** Dokumennya menyebutkan eksplisit: field ini tidak bisa diubah via `kubectl patch`, `kubectl edit`, `kubectl apply`, maupun `helm upgrade` — `apply` akan langsung **error**, bukan diam-diam diabaikan. Kalau salah, harus hapus lalu buat ulang Deployment-nya (dan itu berarti downtime Pod-nya). Rencanakan selector di depan.
- **`maxUnavailable: 0` + `maxSurge: 1`** = saat rollout, Pod lama hanya dimatikan setelah Pod baru siap. Konsekuensinya rollout butuh node dengan ruang ekstra 1 Pod — di laptop single-node ini tidak masalah.
- **readinessProbe beda tugas dengan livenessProbe.** Readiness gagal → Pod dikeluarkan dari endpoint Service (berhenti dikirimi trafik), tapi **tidak** di-restart. Liveness gagal → container di-restart. Salah pasang readiness = downtime sendiri.
- **`targetPort: http`** menunjuk ke **nama** port di Pod, bukan angka. Ganti `containerPort` cukup di satu tempat.
- **Label `app: web` harus sama di tiga tempat** (selector Deployment, template Pod, selector Service). Ini penyebab bug paling umum bagi pemula.

---

## 5. Langkah praktik (urut)

```bash
# 0. pastikan namespace sudah ada
kubectl get ns belajar

# 1. apply
kubectl apply -f 02-deployment/web-deployment.yaml
kubectl apply -f 02-deployment/web-service.yaml

# 2. lihat jenjangnya: Deployment -> ReplicaSet -> Pod
kubectl get deploy,rs,pods -n belajar -o wide

# 3. BUKTIKAN Pod punya IP baru + nama baru tiap kali lahir
kubectl get pods -n belajar -o wide            # catat 3 IP-nya
kubectl delete pod -n belajar <salah-satu-nama-pod>
kubectl get pods -n belajar -o wide            # Pod baru, IP baru, jumlah tetap 3

# 4. Service: alamat stabil, seleksi lewat label
kubectl get endpoints web -n belajar           # harus berisi 3 IP Pod
kubectl describe svc web -n belajar

# 5. Tes dari dalam cluster (pakai Pod yang sudah ada, tidak perlu image baru)
kubectl exec -n belajar deploy/web -- sh -c 'wget -qO- http://web.belajar.svc.cluster.local | head -5'
#   kalau nginx:alpine tidak punya wget, pakai: curl -sI http://web:80  (atau nyalakan image debug sementara)
kubectl exec -it -n belajar deploy/web -- sh   # dari dalam: cat /etc/resolv.conf, nslookup web.belajar

# 6. Naikkan/turunkan jumlah
kubectl scale deploy/web -n belajar --replicas=5
kubectl get pods -n belajar -w                 # hentikan dengan Ctrl-C
kubectl scale deploy/web -n belajar --replicas=3

# 7. Rollout versi baru
#    (pakai 1.29-alpine, JANGAN 1.28-alpine: itu tag di bawah versi yang sedang jalan,
#     Deployment tidak melarang downgrade dan kamu jadi menguji hal yang salah)
kubectl set image deploy/web nginx=nginx:1.29-alpine -n belajar
kubectl rollout status deploy/web -n belajar
kubectl get rs -n belajar                      # RS baru muncul, RS lama 0 replika
kubectl rollout history deploy/web -n belajar  # <- di sini baru ada >= 2 revisi

# 8. Rollback
#    (tulis di terminologi REVISI, bukan "undo": keduanya merujuk nomor revisi; bedanya
#     undo = revisi terbesar SEBELUM revisi yang sedang aktif, --to-revision = nomor pasti)
kubectl rollout undo deploy/web -n belajar
kubectl rollout status deploy/web -n belajar
#    opsional: --to-revision=N untuk kembali ke nomor tertentu
#    opsional: kubectl annotate deploy/web kubernetes.io/change-cause="..." -n belajar
#              supaya kolom CHANGE-CAUSE tidak kosong saat 2 pagi

# 9. port-forward ke SERVICE sekarang, bukan ke Pod
kubectl port-forward -n belajar svc/web 8080:80
#   buka http://localhost:8080 , lalu Ctrl-C

# 10. Naikkan QoS ke Guaranteed (lihat bagian 1)
kubectl set resources deploy/web -n belajar --limits=cpu=100m,memory=128Mi --requests=cpu=100m,memory=128Mi
kubectl get pod -n belajar -l app=web -o jsonpath='{.items[0].status.qosClass}{"\n"}'
```

Poin ngobrol yang harus kamu bisa jawab sendiri setelah langkah ini:

- Kenapa di langkah 9 kita `port-forward` ke Service, padahal hasil di browser sama saja?
- Di langkah 7, kalau `maxUnavailable: 1`, apa yang berbeda di output `kubectl get pods`?
- Berapa ReplicaSet yang tersisa di `kubectl get rs` setelah langkah 8, dan kenapa yang lama tidak langsung dihapus?
- Kalau di langkah 7 kamu `kubectl scale --replicas=4` dulu, apakah revisi baru terbentuk? Cek `kubectl rollout history` dan jelaskan jawabannya.

---

## 5b. Langkah 4: tambahan yang lebih akurat di kluster v1.33+

`kubectl get endpoints web` di v1.33+ mengeluarkan peringatan `Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice`. Ini kabar biasa, bukan masalah klustermu — objeknya masih dibuat, dan jumlah IP di dalamnya tetap bukti yang kamu cari. Tapi karena API lamanya sedang menuju pensiun, biasakan yang baru:

```bash
kubectl get endpointslices -n belajar -l kubernetes.io/service-name=web -o wide
kubectl describe endpointslice -n belajar -l kubernetes.io/service-name=web
```

Bedanya esensial: **satu Service dengan label selector = tepat satu objek Endpoints**, sedangkan Service yang sama bisa punya **banyak EndpointSlice** (masing-masing dibatasi ~100 endpoint). Karena jumlahnya tidak bisa diprediksi dari nama Service, cara menemukannya adalah lewat label `kubernetes.io/service-name=<nama-service>` — tidak ada `kubectl get endpointslice web`.

Di dalam EndpointSlice ada tiga kondisi yang menentukan sebuah Pod layak dikirimi trafik: `ready`, `serving`, dan `terminating`. Ini yang menghubungkan `readinessProbe` di Deployment-mu dengan Routing di Service: **readinessProbe gagal → Pod tetap Running tapi dikeluarkan dari daftar endpoint**, jadi tidak dikirimi trafik dan **tidak** di-restart. Coba sendiri: hapus `readinessProbe` dari manifest, rollout, lalu bandingkan isi endpoint slice-nya.

Sumber: https://kubernetes.io/blog/2025/04/24/endpoints-deprecation (KEP-4974)

---

## 5c. Debug: `no rollout history found` saat `rollout undo`

Error yang kamu dapat:

```text
Warning: resource deployments/web was previously managed with 'kubectl apply'.
Rolling back will not update the kubectl.kubernetes.io/last-applied-configuration
annotation, which may cause unexpected behavior on future 'kubectl apply' operations.
error: no rollout history found for deployment "web"
```

**Warning dan error itu dua masalah berbeda.** Yang kedua yang menggagalkan perintahmu.

**Warning-nya** (ada di source kubectl, kalau sudah kamu jalankan `rollout undo` yang berhasil sekalipun): saat rollback, Deployment ditulis dengan **patch**, sehingga annotation `last-applied-configuration` (yang dipakai oleh `kubectl apply` untuk menghitung diff) ikut **stale** — tidak diperbarui. Karena itu kubectl memperingatkan bahwa `apply` berikutnya bisa menghitung selisih dari kondisi yang sudah kedaluwarsa. Untuk pembelajaran ini, file di disk tetap sumber kebenaranmu: setelah rollback, jalankan `kubectl apply -f 02-deployment.yaml` sekali lagi supaya annotation-nya sinkron lagi.

**Error-nya**: kubectl tidak menemukan ReplicaSet lain untuk dituju. Di source `deploymentRevision()`:

```go
_, allOldRSs, newRS, err := deploymentutil.GetAllReplicaSets(deployment, c.AppsV1())
...
if previousReplicaSet == nil {
    return nil, fmt.Errorf("no rollout history found for deployment %q", deployment.Name)
}
```

Yaitu: dari seluruh ReplicaSet yang ada, tidak ada satu pun yang bisa jadi "target revisi sebelumnya". Penyebabnya, berurutan sesuai kemungkinan:

1. **Deployment baru punya satu revisi.** Ini kasusmu: perubahan `replicas` (2 → 4) **bukan** perubahan template, jadi tidak melahirkan revisi baru. `scale` tidak menambah rollout history — ini jawaban pertanyaan refleksi terakhir di atas. Satu-satunya ReplicaSet yang ada adalah yang sedang aktif, jadi "sebelumnya" kosong.
2. **`revisionHistoryLimit: 0`** → seluruh riwayat di-garbage-collect, tidak ada yang bisa dituju. Kalau itu kasusnya: `kubectl patch deploy/web -n belajar -p '{"spec":{"revisionHistoryLimit":5}}'`, lakukan perubahan template, baru `undo`-nya bermakna.
3. **Revisi target sudah dipangkas** `revisionHistoryLimit` → `unable to find specified revision`. Riwayat yang sudah di-GC tidak bisa dipulihkan; solusinya hanya apply ulang manifest dari source control.

Cara membuktikannya di kluster sendiri:

```bash
kubectl rollout history deploy/web -n belajar
#   REVISION 1 saja -> penyebab #1. Keluar, lakukan langkah 7 dulu
kubectl get deploy web -n belajar -o jsonpath='{.spec.revisionHistoryLimit}{"\n"}'   # cek penyebab #2
kubectl get rs -n belajar                                                            # berapa RS yang benar-benar ada
```

Kalau kamu ingin tabel ReplicaSet + nomor revisinya, **jangan** pakai `-o custom-columns=...deployment\.kubernetes\.io/revision...` di zsh — zsh mencoba meng-glob pola itu dan gagal dengan `zsh: no matches found`. Tiga jalan keluar, pilih satu:

```bash
# (a) matikan glob hanya untuk perintah itu
noglob kubectl get rs -n belajar -o custom-columns=NAME:.metadata.name,REV:.metadata.annotations.deployment\\.kubernetes\\.io/revision,IMAGE:.spec.template.spec.containers[0].image

# (b) bungkus seluruh ekspresi dalam kutip tunggal (paling mudah diingat)
kubectl get rs -n belajar -o 'custom-columns=NAME:.metadata.name,REV:.metadata.annotations.deployment\.kubernetes\.io/revision,IMAGE:.spec.template.spec.containers[0].image'

# (c) jsonpath lewat script yang sudah saya sediakan
./02-deployment/rs-revisi.sh belajar
```

**Penting untuk logika rollback**: `rollback undo` memilih revisi **terbesar yang nomornya di bawah revisi yang sedang aktif**, bukan sekadar "ReplicaSet lain yang tersisa". Perhatikan baris `latestReplicaSet` / `previousReplicaSet` di source di atas: klausa `else if previousRevision < v` hanya jalan **jika ReplicaSet itu sudah pernah terlihat lebih dulu di dalam loop**. Artinya urutan loop ikut menentukan, bukan cuma nomor revisinya.

Di praktiknya ini jarang terasa karena `rollout undo` mengecek dulu apakah template di ReplicaSet target **sama dengan** template yang ada di riwayat revisi aktif; kalau sama, ia melewatinya dan menuju kandidat berikutnya. Tapi jangan pernah bergantung pada "undo = kembali satu langkah". Kalau kamu butuh nomor yang pasti, pakai `--to-revision=N`, dan baca isinya dulu di `kubectl rollout history deploy/web --revision=N` sebelum menekan enter.

**Yang akan kamu lihat setelah `undo` berhasil** (dan ini sering bikin bingung): ReplicaSet bisa muncul **dengan nama yang sama tapi nomor revisi baru**, dan `kubectl rollout history` menampilkan revisi tertinggi sebagai revisi "baru" lagi. Itu memang perilaku yang dimaksud, bukan salah tulis — di `SetNewReplicaSetAnnotations` nomor lama ReplicaSet yang jadi target rollback ikut dinaikkan ke nomor revisi terbaru, sementara nomor lamanya disimpan di annotation `deployment.kubernetes.io/revision-history` (dipangkas di sekitar 2000 karakter). Konsekuensi praktisnya: **setelah rollback, `kubectl get rs` bisa menunjukkan jumlah ReplicaSet yang lebih sedikit dari dugaanmu** — karena ReplicaSet lama itu dipakai ulang, bukan dibuat yang baru.

**Satu jebakan lain yang mudah bikin panik**: `revisionHistoryLimit: 0` **tidak langsung** menghapus ReplicaSet lama. Di `cleanupDeployment` ada penjaga ini:

```go
if rs.Status.Replicas != 0 || *(rs.Spec.Replicas) != 0 || rs.Generation > rs.Status.ObservedGeneration || rs.DeletionTimestamp != nil {
    continue
}
```

Jadi ReplicaSet lama hanya dihapus **setelah skala-nya benar-benar 0 dan statusnya sudah sinkron**. Kalau kamu set limit 0 lalu mengharapkan riwayat hilang seketika, kamu akan lihat ReplicaSet lamanya masih ada beberapa saat — itu normal, bukan bug. Dan sebaliknya: karena penjaga itu, riwayat baru benar-benar bisa dipangkas saat sudah menjadi ReplicaSet lama (bukan yang aktif).

Sumber: [rollback.go](https://github.com/kubernetes/kubernetes/blob/master/staging/src/k8s.io/kubectl/pkg/polymorphichelpers/rollback.go) dan [history.go](https://github.com/kubernetes/kubernetes/blob/master/staging/src/k8s.io/kubectl/pkg/polymorphichelpers/history.go)

---

## 6. Bonus: penyebab `STATUS` aneh di Pod

Hari 1 statusnya `Running`. Nanti kamu akan ketemu `Pending`, `ImagePullBackOff`, `CrashLoopBackOff`, `Completed`, `Terminating`.

**Latihan yang benar bukan menebak, tapi mendeskripsikan objek yang GAGAL dibuat.** Tanpa manifest, `kubectl run` menunggu Pod-nya jadi, jadi jangan pakai itu untuk memancing error. Pakai file (`kubectl apply` tidak menunggu), lalu baca `kubectl describe` bagian Events dan `kubectl get pod -o yaml` bagian `status`.

```bash
# (a) ImagePullBackOff: tag tidak ada
kubectl run badtag --image=nginx:tag-ngawur -n belajar --restart=Never

# (b) ContainerCreating yang menggantung: volume yang tidak pernah ada
kubectl run badvol --image=nginx:1.27-alpine -n belajar --restart=Never \
  --overrides='{"spec":{"volumes":[{"name":"v","persistentVolumeClaim":{"claimName":"pvc-hantu"}}],"containers":[{"name":"badvol","image":"nginx:1.27-alpine","volumeMounts":[{"name":"v","mountPath":"/data"}]}]}}'

# (c) CrashLoopBackOff: keluar dengan kode 1
kubectl run crasher --image=busybox:1.36 -n belajar --restart=Never -- sh -c 'echo halo; exit 1'

# (d) Pending: minta resource yang tidak mungkin
kubectl run laparpending --image=nginx:1.27-alpine -n belajar --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"laparpending","image":"nginx:1.27-alpine","resources":{"requests":{"cpu":"64","memory":"128Gi"}}}]}}'

# setiap kasus, jawab tiga pertanyaan ini:
kubectl get pod <nama> -n belajar            # STATUS-nya apa
kubectl describe pod <nama> -n belajar        # Events-nya berkata apa + bagian mana di spec yang salah
kubectl get pod <nama> -n belajar -o yaml     # status.conditions / containerStatuses (waiting reason, exitCode)
```

Kalau `kubectl get pod` tidak menampilkan `NODE` seperti biasanya, artinya Pod itu **tidak pernah dijadwalkan** — jangan buang waktu mencari isu container; bagian Events-lah yang menyebutkan alasannya.

Pelajaran penting dari (a) vs (b): (a) gagal karena **registry** (kubelet tidak bisa menarik image), (b) tidak pernah sampai ke tahap itu karena **volume/API resource** — sama-sama "Pod tidak jalan", tapi lapisan yang gagal berbeda, dan itu yang harus kamu bedakan.

Istilah keempat status itu, apa adanya (bukan hafalan):

- **`Pending`** — Pod sudah diterima API server, tapi belum bisa dijadwalkan ke node (resource, selector, taint) atau masih menunggu image/volume. Lihat Events.
- **`ImagePullBackOff`** — kubelet menyerah menarik image lalu menunggu dengan backoff. Cek nama tag exist, kredensial registry, dan DNS/jaringan node.
- **`CrashLoopBackOff`** — container berulang kali mati setelah start. Sebabnya di `Last State: Terminated` + `Exit Code`, bukan di nginx-nya.
- **`Completed`** — container keluar dengan exit 0. Ini status untuk Job, bukan untuk server.

Catatan: di Pod yang CrashLoop, `shell` (`kubectl exec -it`) sering tidak bisa dibuka karena container-nya sedang tidak jalan. Untuk kasus seperti itu, jalur debug-nya adalah `kubectl describe` (exit code + alasan) dan event, bukan shell.

`CrashLoopBackOff` = kubelet sengaja menunda restart dengan **exponential backoff: 10s, 20s, 40s, … dibatasi 300 detik (5 menit)**. Kalau container sudah berjalan normal 10 menit tanpa masalah, timer backoff-nya di-reset dan crash berikutnya dianggap sebagai crash pertama. Jadi kalau di `describe` kamu lihat `Back-off restarting failed container`, itu tanda mekanisme backoff bekerja, bukan tanda cluster rusak.

Sumber: https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/

---

## 7. Tugas penyaji: push ke GitHub

Ini yang mengubah latihan jadi artefak yang bisa dilihat orang. Jalankan setelah langkah 1–10 beres:

```bash
cd ~/k8s-observability-homelab
git init                                  # lewati kalau sudah ada .git
mkdir -p 01-pod && git mv 01-pod-nginx.yaml 01-pod/ 2>/dev/null || true

git status                                # PERIKSA dulu sebelum commit
git add 01-pod 02-deployment 03-service.yaml README.md docs
git commit -m "week1: pod -> deployment -> service (belajar)"

# buat repo kosong dulu di web GitHub, JANGAN centang "Add README"
git remote add origin git@github.com:<username>/k8s-observability-homelab.git
git push -u origin main
```

Aturan yang bikin repo ini layak masuk CV:

- **Tidak ada token, password, atau IP rumah di repo.** Cek sebelum push: `git grep -nEi "token|password|bearer|adminPassword"` dan `git status --short`. Kalau kredensial pernah ter-commit, hapus file-nya **dan** anggap nilainya bocor (ganti), bukan sekadar commit "remove secret".
- **Setiap folder punya alasan hidup di README**, bukan daftar folder. Satu paragraf per folder: apa yang dipelajari + keputusan desainnya.
- **Commit kecil dan pesannya menjelaskan alasan**, bukan "update". Contoh yang benar: `02-deployment: pin image 1.27-alpine, maxUnavailable=0 supaya rollout tanpa downtime`.
- Yang belum kamu kuasai **jangan ditulis**. Nanti pindahkan +README ke GitHub Pages agar diagram render (tabel/mermaid tidak render di README).

Isi minimum `README.md`:

```markdown
# k8s-observability-homelab

Kluster Kubernetes lokal (Docker Desktop) untuk belajar Pod, Deployment, Service,
lalu observability (Prometheus/Grafana/Loki). Tiap folder = satu fase belajar.

## Status per <tanggal>
- [x] Hari 1: Pod, describe/logs/exec/port-forward
- [x] Hari 2: Deployment, ReplicaSet, Service
- [ ] Hari 3: Job/CronJob, NodePort, probe & resource limits
- [ ] Hari 4: kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
- [ ] Hari 5: Loki + Promtail, datasource manual di Grafana
- [ ] Hari 6: PrometheusRule + alert Telegram
- [ ] Hari 7: README, runbook, diagram, waktu deteksi sebelum/sesudah

## Isi
- `01-pod/` — satu Pod nginx, plus catatan `describe`/`logs`/`exec`/`port-forward`.
- `02-deployment/` — Deployment (3 replika, probe, request/limit) + Service.
- `docs/` — catatan sesi (mis. `docs/hari-2-rollout.md`).
```

Untuk fase observability (hari 4–6), folder yang dipakai nanti:

```text
k8s-observability-homelab/
├── 01-pod/                  # manifest Pod polos
├── 02-deployment/           # Deployment + Service app contoh
├── 03-service/              # NodePort/Ingress eksperimen
├── 04-monitoring/           # values.yaml kube-prometheus-stack + perintah helm
├── 05-logging/              # values.yaml loki/promtail
├── 06-alerting/             # PrometheusRule + Alertmanager (token TIDAK di repo)
├── docs/                    # catatan sesi, diagram, runbook
└── README.md
```

Dan satu kalimat yang harus jujur ada di README: *"Ini kluster latihan satu node di laptop, bukan setup produksi."* Tanpa itu, pembaca yang teknis akan menebak sendiri — dan lebih buruk dari menemukannya sendiri.