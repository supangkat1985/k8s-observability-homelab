# Hari 2 (versi simpel) — ulang dari nol

Tujuan satu sesi ini cuma tiga:

1. Hapus Pod → **orang lain yang bikin gantinya** (ReplicaSet).
2. `set image` → **versi baru** menggantikan versi lama tanpa downtime.
3. `undo` → **balik ke versi lama**.

Semua teori (QoS, EndpointSlice, isi source kubectl) ada di `catatan/versi-lengkap-dan-teori.md`. **Jangan dibuka sampai 3 poin di atas selesai.** Kalau ada yang gagal di tengah, lihat bagian "Kalau ada yang gagal" di bawah, bukan file catatan.

Semua perintah diketik dari dalam folder `k8s-observability-homelab`. File yang dipakai cuma satu: `02-deployment/web.yaml`.

---

## LANGKAH 0 — buang semua sisa

```bash
kubectl delete namespace belajar
kubectl create namespace belajar
```

Perintah pertama menghapus Pod, Deployment, ReplicaSet, dan Service sekaligus — jadi tidak ada sisa latihan kemarin yang bikin bingung. Kalau `delete` terasa lama (namespace menunggu Pod benar-benar mati, sampai 30 detik), itu normal.

Cek sudah bersih:

```bash
kubectl get all -n belajar
```

Harus muncul `No resources found in belajar namespace.`

## LANGKAH 1 — pasang

```bash
kubectl apply -f 02-deployment/web.yaml
kubectl get all -n belajar
```

Baca hasilnya pelan-pelan. Yang penting: **satu** `deployment.apps/web`, **satu** `replicaset.apps/web-xxxxx`, **tiga** `pod/web-xxxxx-xxxxx`, semuanya `Running`. Deployment, ReplicaSet, Pod — tiga lapis, satu baris masing-masing.

```bash
kubectl get pods -n belajar -o wide
```

Catat tiga IP-nya. Nanti kamu bandingkan.

## LANGKAH 2 — buktikan Pod kembali sendiri

```bash
kubectl delete pods -n belajar -l app=web
kubectl get pods -n belajar -o wide
```

Hapus **semua** Pod sekaligus, lalu lihat lagi: jumlahnya tetap tiga, namanya baru semua. Yang menghidupkan bukan kamu — itu ReplicaSet.

**Ini jawaban pertanyaan Hari 1:** Pod polos tidak kembali karena tidak ada yang mengawasinya; Pod di dalam Deployment kembali karena ReplicaSet terus menyamakan "yang diminta" (3) dengan "yang ada".

Cek buktinya dari sisi ReplicaSet:

```bash
kubectl describe rs -n belajar
kubectl get events -n belajar --sort-by=.lastTimestamp | tail -15
```

Cari baris `SuccessfulCreate` / `Created pod:` — itu ReplicaSet yang bekerja.

## LANGKAH 3 — Service

```bash
kubectl get endpointslices -n belajar -l kubernetes.io/service-name=web -o wide
kubectl port-forward -n belajar svc/web 8080:80
```

Buka `http://localhost:8080` di browser → halaman nginx. Lalu `Ctrl-C`. Ganti `:80` di URL jadi `:8081` dan buka lagi → error, karena tidak ada yang memetakan port itu. Itu membuktikan port-forward itu benar-benar bekerja, bukan sekadar halaman tersimpan di cache.

`kubectl get endpointslices` menampilkan IP Pod yang melayani Service. Ini yang membuat Service tetap punya alamat walau IP Pod berganti-ganti.

## LANGKAH 4 — versi baru

Pakai ulang nama Pod yang **sedang jalan**, bukan yang lama. Di contoh ini `web-9b7c45968-8pk59` — sesuaikan dengan nama di klustermu.

```bash
kubectl get deploy web -n belajar -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
#   harus nginx:1.27-alpine. Kalau bukan, jalankan dulu:
#   kubectl rollout undo deploy/web -n belajar

# terminal 1 — pantau, biarkan terbuka
kubectl get pods -n belajar -w

# terminal 2 — ganti versi
kubectl set image deploy/web nginx=nginx:1.29-alpine -n belajar
```

Kembali ke terminal 1 dan perhatikan: Pod baru muncul dengan status berisi `Pending`/`ContainerCreating` **sementara tiga Pod lama masih Running** — jumlahnya sempat 4. Setelah Pod baru `Running`, Pod lama berubah `Terminating` dan hilang. Tidak ada momen di mana Pod yang melayani tinggal nol. `Ctrl-C` kalau sudah selesai.

Kenapa satu-satu, bukan semua sekaligus? Karena `strategy.rollingUpdate` bawaan: `maxSurge: 1`, `maxUnavailable: 0`.

## LANGKAH 5 — balik ke versi lama

```bash
kubectl rollout history deploy/web -n belajar
kubectl rollout undo deploy/web -n belajar
kubectl get pods -n belajar -o wide
```

Yang perlu kamu tahu: **`undo` tidak menghapus revisi 1, ia membuat revisi baru yang isinya versi lama.** Jadi di `rollout history` setelah undo, nomor tertinggi bukan "versi baru", melainkan versi lama yang dipromosikan jadi paling baru. Itu memang cara kerjanya — bukan salah ketik.

Bacanya gampang: **nama image, bukan nomor revisi**, yang bercerita.

```bash
kubectl get deploy web -n belajar -o jsonpath='{.spec.template.spec.containers[0].image}{"  rev="}{.metadata.annotations.deployment\.kubernetes\.io/revision}{"\n"}'
#   harapan: nginx:1.27-alpine  rev=3
bash 02-deployment/catatan/rs-revisi.sh belajar
#   harapan: hanya SATU ReplicaSet, 4/4, nginx:1.27-alpine, nama hash-nya beda dari web-9b7c45968
```

`kubectl rollout history deploy/web -n belajar --revision=1` akan menampilkan `nginx:1.29-alpine` — itu bukti bahwa revisi yang di-undo tidak hilang, cuma nomornya dipakai ulang.

Selesai. Kalau satu langkah belum jalan, jangan lanjut — Day 2 cuma tiga hal ini.

---

## Rapikan (2 menit)

```bash
kubectl scale deploy/web -n belajar --replicas=3
kubectl get all -n belajar
```

Angka `replicas` di kluster sekarang kembali 3, sama dengan file `web.yaml` di disk. Jadi tidak ada lagi selisih git vs kluster.

## Kalau ada yang gagal

- **`rollout undo` → `no rollout history found`** → belum ada perubahan template sama sekali, jadi cuma ada satu ReplicaSet. Jalankan LANGKAH 4, baru LANGKAH 5.
- **`rollout undo` → `unable to find specified revision`** → nomor revisi yang kamu minta sudah dipangkas `revisionHistoryLimit` (bawaan 10). Pakai nomor yang muncul di `rollout history`.
- **Warning `previously managed with 'kubectl apply'` saat `undo`** → bukan error. `undo` tetap jalan. Warning itu berarti operasi rollback menulis objek dengan patch, sehingga catatan `last-applied-configuration` tidak ikut diperbarui. Obatnya cuma satu: setelah selesai, `kubectl apply -f 02-deployment/web.yaml` sekali lagi.
- **`zsh: no matches found`** saat mengetik perintah dengan `custom-columns` → shell-nya mencoba meng-glob, bukan kubectl. Pakai: `noglob kubectl get ...`, atau kutip seluruh ekspresi: `kubectl get ... -o 'custom-columns=...'`.
- **`kubectl delete pods -n belajar app=web`** → itu dianggap nama Pod. Yang benar pakai tanda `-l`: `kubectl delete pods -n belajar -l app=web`.
- **`ImagePullBackOff`** → tag image salah tulis atau registry tidak bisa diakses. `kubectl describe pod <nama> -n belajar` bagian Events menyebutkan persis tag mana yang gagal.
- **Pod `Pending` terus** → tidak ada node yang sanggup memenuhi `resources.requests`. Events-nya menyebut alasan yang sebenarnya.
- **`container "nginx" in pod "web-..." is waiting to start: PodInitializing`** → tunggu saja, atau tambah `--for=condition=Ready`: `kubectl wait --for=condition=Ready pod -l app=web -n belajar --timeout=60s`.

## Kalau seluruh latihan mau diulang lagi

```bash
kubectl delete namespace belajar && kubectl create namespace belajar
kubectl apply -f 02-deployment/web.yaml
```

Dua perintah itu cukup. Semuanya diulang dari lahan kosong, jadi tidak ada riwayat aneh yang perlu dijelaskan.