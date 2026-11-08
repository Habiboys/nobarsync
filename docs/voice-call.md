# Call melalui ngrok saja

Voice call sekarang memakai relay audio melalui Phoenix WebSocket pada origin aplikasi yang sama. Semua peserta mengakses URL HTTPS ngrok yang sama; browser tidak membuka koneksi WebRTC, STUN, atau TURN. Audio film tetap memakai player dan volume tersendiri.

## Satu perintah

Di root `C:\Project\nobarkan2`:

```powershell
docker compose up -d
```

Environment komputer ini sudah memiliki `COMPOSE_PROFILES=tunnel`, `NGROK_AUTHTOKEN` dari konfigurasi ngrok yang sebelumnya tersedia, dan `NGROK_URL=` kosong agar ngrok menetapkan alamat gratis. Agent ngrok kini berada dalam Docker network dan meneruskan ke Caddy. Proses ngrok Windows yang dibuat sebelumnya sudah dihentikan. Tidak perlu menjalankan ngrok manual atau profile `turn`.

Lihat URL:

```powershell
(Invoke-RestMethod http://127.0.0.1:4040/api/tunnels).tunnels.public_url
```

Untuk checkout baru, isi `NGROK_AUTHTOKEN` serta `COMPOSE_PROFILES=tunnel` dalam `.env` satu kali. Alternatif tanpa mengaktifkan profile di environment: `docker compose --profile tunnel up -d`. Produksi: `docker compose -f docker-compose.prod.yml --profile tunnel up -d` dengan environment produksi yang sesuai. Jangan commit `.env` atau membagikan authtoken.

Alamat aktif saat konfigurasi ini dibuat: **https://e59d-114-122-72-110.ngrok-free.app**. Alamat gratis dapat berubah ketika sesi dibuat ulang. Pada domain baru, login kembali, izinkan mikrofon dan gabung call. Jika muncul peringatan ngrok, tekan Visit Site. Kedua peserta harus memuat ulang halaman agar memakai versi call yang sama.

## Upload R2 setelah URL berubah

Tambahkan origin baru pada CORS bucket R2; pertahankan origin lama dan aturan lainnya. Contoh JSON untuk dashboard:

```json
[
  {
    "AllowedOrigins": [
      "http://localhost:5173",
      "http://localhost:8080",
      "https://f286-114-122-75-86.ngrok-free.app",
      "https://e59d-114-122-72-110.ngrok-free.app"
    ],
    "AllowedMethods": ["GET", "HEAD", "PUT"],
    "AllowedHeaders": ["*"],
    "ExposeHeaders": ["ETag"],
    "MaxAgeSeconds": 3600
  }
]
```

Kredensial project sebelumnya ditolak saat membaca pengaturan CORS (`403`), sehingga perubahan CORS cloud ini tetap perlu disimpan dari dashboard akun Anda. CORS R2 mengatur upload langsung, terpisah dari jalur call.

## Cara audio bekerja dan batas percobaan

Mikrofon diproses di AudioWorklet, mono 16 kHz, frame 80 ms, companding mu-law 8 bit. Audio dikirim sebagai base64 melalui WebSocket, lalu server meneruskannya ke peserta call lain di room yang sama. Audio tidak disimpan atau dimasukkan ke log channel. Buffer playback dibatasi agar gangguan jaringan tidak membuat antrean suara panjang. Ada penekanan silence, batas frame server, pembatasan frame menunggu ack, dan maksimum 8 peserta call.

Mikrofon tetap tertutup setelah bergabung. Suara hanya terkirim saat tombol bicara ditahan, dan baru setelah server mengizinkan buka mikrofon. Selama ada yang bicara, pemutar film di perangkat itu disenyapkan sementara; posisi slider film tidak berubah dan pulih sekitar 400 ms setelah suara teman berhenti. Gambar film tetap berjalan di masing-masing perangkat.

Jalur ini cocok untuk percobaan tanpa VPS/TURN, tetapi penggunaan upload server meningkat seiring jumlah pembicara dan pendengar. Satu mikrofon aktif memakai sekitar 0,17–0,18 Mbps per aliran termasuk base64, lalu server mengirim salinan ke setiap pendengar. Delapan peserta berbicara bersamaan dapat mendekati 10 Mbps upload relay server, belum termasuk film dan overhead jaringan. TCP/ngrok dapat menambah latensi pada koneksi lambat. Voice ini bukan audio musik fidelitas tinggi; film tetap menggunakan audio aslinya.

Coturn masih tersedia sebagai service profile `turn` untuk percobaan terpisah. Ia tidak dibutuhkan dan tidak digunakan oleh jalur call WebSocket saat ini. Petunjuk IP publik di `infra/turn/README.md` berlaku untuk coturn mandiri, bukan untuk mode ini.

## Pemeriksaan

Tes browser sengaja membuat `RTCPeerConnection` gagal dibuat, sehingga keberhasilan audio tidak bisa bergantung pada koneksi langsung antarperangkat. Tes memeriksa frame diterima saat tombol bicara ditahan, sampel audio nonzero, volume call terpisah, peredaman film saat bicara, izin mikrofon ditolak, pelepasan track/context saat keluar, gabung ulang, serta penutupan ruang. Pengujian mobile memakai emulasi browser dan mikrofon simulasi; hasil pada perangkat fisik tetap perlu dicoba.

Konfigurasi Compose development dan produksi divalidasi. Terdapat tes backend untuk autentikasi, identitas pengirim, frame tidak valid, replay, mute, dan pembatasan laju. Modul AudioWorklet dibundel bersama aplikasi agar tidak tertukar dengan HTML peringatan ngrok.
