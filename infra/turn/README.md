# TURN mandiri untuk voice call

> Mode call saat ini memakai WebSocket melalui ngrok dan tidak membutuhkan coturn. Panduan ini hanya untuk layanan coturn mandiri. Lihat docs/voice-call.md untuk menjalankan aplikasi dan tunnel dengan satu Compose.

Layanan `turn` menggunakan coturn dan profile Docker `turn`, tersedia pada Compose development dan produksi. Konfigurasi mendukung kredensial HMAC sementara; secret hanya disimpan di server. Jalur call WebSocket saat ini tidak menggunakan kredensial TURN. Container berjalan sebagai pengguna non-root. Tidak ada autentikasi anonim.

## Konfigurasi internet

TURN harus memiliki IPv4 publik yang dapat dijangkau, atau router yang meneruskan port secara 1:1 ke host Docker. Jika koneksi ISP memakai CGNAT dan tidak menyediakan port forwarding publik, menjalankan container di laptop tidak akan membuatnya terjangkau internet. Gunakan host/VPS dengan IP publik. Ngrok HTTP untuk website tetap bisa dipakai, tetapi hostname ngrok bukan alamat server TURN.

Isi `.env` project (jangan commit secret):

```dotenv
TURN_EXTERNAL_IP=203.0.113.10
TURN_REALM=turn.example.com
TURN_SHARED_SECRET=<random-hex-minimal-32-karakter>
TURN_URLS=turn:turn.example.com:3478?transport=udp,turn:turn.example.com:3478?transport=tcp
TURN_MIN_PORT=49160
TURN_MAX_PORT=49200
TURN_TLS_ENABLED=false
```

Alamat di atas hanya contoh; ganti dengan IP/hostname sebenarnya. DNS hostname harus menuju IP publik host TURN. Jika di belakang router, `TURN_EXTERNAL_IP` berisi IP publik router; port relay harus diteruskan dengan nomor port yang sama.

PowerShell helper tersedia dari root project:

```powershell
.\infra\turn\Configure-Turn.ps1 -PublicIP IP_PUBLIK_ASLI -TurnHost turn.domainanda.com
```

Helper mempertahankan secret yang ada atau membuat secret acak jika belum ada, memperbarui environment, lalu menjalankan TURN/API. Untuk server Linux, edit `.env` lalu gunakan Docker Compose di bawah. Script tidak mengubah firewall/router.

```sh
docker compose --profile turn up -d turn api
docker compose logs --tail 30 turn
```

Produksi:

```sh
docker compose -f docker-compose.prod.yml --profile turn up -d turn api
```

Jika API dan TURN berada di host terpisah, jalankan `turn` saja di host publik dan gunakan secret serta `TURN_URLS` yang sama pada API. Worker tidak membutuhkan secret TURN. Jangan menggunakan `turn:turn:3478` atau `localhost` untuk browser teman.

## Port dan TLS

| Port | Kegunaan |
| --- | --- |
| 3478 UDP + TCP | Koneksi browser ke TURN |
| 49160–49200 UDP | Trafik media relay; sesuaikan `.env` jika perlu |
| 5349 TCP | Opsional TURN lewat TLS |

Buka port tersebut di firewall host, firewall cloud/security group, dan port forwarding router bila digunakan. Port relay UDP tetap diperlukan ketika browser masuk melalui TCP/TLS. `no-tcp-relay` hanya mematikan relay RFC6062, bukan koneksi browser TCP ke server.

Untuk jaringan yang memblokir UDP, sediakan sertifikat TLS valid untuk hostname TURN. Salin `fullchain.pem` dan `privkey.pem` ke `infra/turn/certs/` (diabaikan Git), set `TURN_TLS_ENABLED=true`, dan tambahkan `turns:turn.example.com:5349?transport=tcp` ke `TURN_URLS`. Pada Linux, pastikan file dapat dibaca UID 65534 container melalui grup/ACL yang sesuai. Restart service setelah sertifikat diperbarui. TLS website ngrok tidak berlaku otomatis untuk coturn. Jaringan yang hanya mengizinkan port 443 dapat membutuhkan listener TURN TLS pada IP/port terpisah; konfigurasi ini tidak mengambil alih port 443 aplikasi/storage Anda.

## Verifikasi

```sh
docker compose --profile turn config --quiet
docker compose exec -T turn turnutils_stunclient -p 3478 127.0.0.1
node infra/turn/smoke-turn.cjs
```

Smoke test memerlukan dependency Playwright dari `tests/e2e` dan Chrome terpasang. Ia menguji autentikasi HMAC dan mendapatkan kandidat `relay` dari TURN lokal pada port Docker 3478; ia tidak membuktikan jangkauan internet. Tutup lalu gabung ulang call setelah konfigurasi berubah. Uji terakhir harus memakai dua perangkat pada jaringan berbeda dan memeriksa audio dua arah, idealnya memaksa `iceTransportPolicy: relay` pada alat uji.

Konfigurasi awal di komputer ini memakai `TURN_EXTERNAL_IP=127.0.0.1` hanya untuk smoke test. `TURN_URLS` dibiarkan kosong agar browser teman tidak diarahkan ke localhost mereka sendiri. Ganti nilai tersebut sebelum mengaktifkan relay internet. Container dapat berjalan tanpa IP publik, tetapi belum dapat dipakai teman dari luar jaringan.

Referensi: https://github.com/coturn/coturn/blob/master/docker/coturn/README.md
