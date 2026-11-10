# Pembaruan Manonton, 10 November 2026

Perubahan diterapkan di `C:\Project\nobarkan2` untuk dua permintaan baru: impor tautan video dan pemantauan kehadiran. Pekerjaan lama tidak dilanjutkan.

## Impor URL

Tautan Cloudflare yang diberikan membuka HTML. Di dalamnya terdapat elemen `video` dengan sumber relatif `/video?key=...`. Pemeriksaan sumber tersebut mengembalikan HTTP 206, `video/mp4`, dan ukuran total **3.419.036.585 byte**. Resolver baru membaca sumber HTML5 ini secara otomatis dan mempertahankan parameter URL.

Tautan Acefile membuka halaman HTML dengan script dan iframe, tanpa sumber video HTML5 statis yang dapat diimpor. Aplikasi sekarang menjelaskan kondisi tersebut di dalam modal. Gunakan URL berkas video langsung yang disediakan penyedia atau unggah berkasnya. Tanda kutip tambahan di akhir URL, seperti pada screenshot, juga mendapat pesan khusus.

Perubahan teknis:

- `IMPORT_HOST_ALLOWLIST` dan `IMPORT_MAX_BYTES` diteruskan ke **API dan worker**, pada Compose development maupun production.
- `.env` lokal ditambahkan dua domain spesifik yang diberikan, tanpa membuka seluruh domain tunnel publik. Batas lokal menjadi **4 GiB**, sehingga sumber 3,4 GB lolos pemeriksaan ukuran.
- Pemeriksaan awal memakai permintaan parsial, bukan mengunduh seluruh film dalam request API.
- Unduhan worker ditulis per bagian ke disk, dengan batas byte selama streaming dan penghapusan berkas parsial jika gagal. Implementasi lama menampung respons penuh di memori.
- Setiap pengalihan dan sumber HTML5 diperiksa ulang terhadap daftar domain, HTTPS, dan alamat privat. Script serta iframe tidak dijalankan. Impor playlist HLS/DASH belum didukung.
- Modal menampilkan status pemeriksaan, mencegah submit ganda selama menunggu, serta menampilkan error dan hasil di dekat formulir.

Impor tetap berarti **unduh lalu olah menjadi HLS**. Film tidak langsung siap diputar. Sumber 3,4 GB hanya diverifikasi sampai resolusi dan pemeriksaan parsial; tidak diunduh dan di-encode seluruhnya dalam verifikasi ini.

Jika hostname tunnel berubah, ubah `.env`:

```dotenv
IMPORT_HOST_ALLOWLIST=hostname-tunnel-yang-baru.trycloudflare.com,acefile.co
IMPORT_MAX_BYTES=4294967296
```

Lalu muat konfigurasi development:

```sh
docker compose up -d --no-deps api worker
```

Pada server production, perubahan kode juga perlu image baru:

```sh
docker compose -f docker-compose.prod.yml up -d --build
```

Jangan menyalin hostname tunnel sementara ini sebagai daftar domain publik umum. Domain tujuan pengalihan yang berbeda harus ditambahkan secara terpisah. Sediakan ruang disk untuk sumber dan keluaran pengolahan.

## Detail room dan admin

Detail room menampilkan peserta yang memiliki koneksi pemutar aktif, bukan riwayat keanggotaan. Membuka halaman detail saja tidak menambahkan penonton. Perubahan koneksi memberi notifikasi untuk menyegarkan detail; polling 3 detik tetap tersedia sebagai cadangan.

Jika satu akun menonton dari dua tab, peserta dihitung sekali. Menutup satu tab mempertahankan peserta sampai tab pemutar terakhir ditutup. Keluar room secara eksplisit menutup channel pemutar dan call akun tersebut pada tab lain, dan keanggotaan yang sudah keluar/diblokir tidak ditampilkan kembali sebagai peserta aktif.

Buka **Admin → Langsung** untuk melihat:

- Akun online di seluruh aplikasi, termasuk Pustaka, dashboard, dan halaman akun.
- Nama, email, peran, jumlah tab, dan halaman yang sedang dibuka. Parameter query tidak disimpan sebagai aktivitas.
- Peserta yang sedang menonton, room mereka, dan peran dalam room.
- Room terbuka yang berpenghuni atau kosong, status kunci, film aktif, status diputar/dijeda, posisi waktu, dan durasi yang diketahui.
- Pencarian room, film, atau peserta; filter room berpenghuni; tombol pembaruan; dan tautan detail room.

Kehadiran mengikuti koneksi WebSocket. Posisi pemutaran berasal dari coordinator server dan diperbarui setiap **4 detik**, bukan pemantauan layar pengguna. Putus jaringan mendadak baru terdeteksi setelah transport menyatakan koneksi terputus. Halaman yang masih memakai build lama perlu dimuat ulang agar melaporkan kehadiran aplikasi.

Daftar mengambil **100 room terbuka terbaru**. Jika jumlahnya melebihi itu, UI memberi keterangan cakupan. Belum ada pagination pemantauan untuk seluruh riwayat room. Endpoint dan observer admin tetap memeriksa otorisasi admin.

Error tambahan yang ditemukan selama verifikasi: objek player YouTube dapat terbentuk sebelum metode API-nya siap. Referensi yang dipakai untuk membaca/mengendalikan player sekarang diaktifkan setelah `onReady`, sehingga tidak melempar `getCurrentTime is not a function` saat room terhubung.

## Bukti verifikasi

- **19 tes backend lolos**, mencakup URL HTML5 dan query, iframe/script yang tidak didukung, URL malformed, pengalihan privat, batas ukuran, streaming serta pembersihan berkas parsial, observer tanpa keanggotaan penonton, akun online di luar pemutar, keluar room, call, dan proyeksi film/posisi diputar serta dijeda.
- **2 tes Playwright lolos** dalam 34,7 detik: beberapa konteks akun dan tab; perubahan daftar detail/admin; akun di Pustaka; penolakan admin untuk pengguna biasa; filter/pembaruan/tautan detail; tema terang/gelap pada 393, 768, dan 1440 px; modal error URL dan Escape; tidak ada error JavaScript halaman pada alur tersebut.
- `npm run lint` dan `npm run build` lolos. Build masih memberi peringatan ukuran chunk HLS, tidak ada klaim benchmark performa baru.
- Compose development dan production lolos validasi konfigurasi. API dan worker lokal memakai batas identik 4 GiB.
- Resolusi nyata dari container berhasil ke path `/video` pada tunnel yang diberikan. Acefile menghasilkan error terarah `unsupported_player_page`.
- Akun admin sementara untuk pengujian dinonaktifkan dan sesi-sesinya dihapus sesudah pengujian.

## Gerbang antislop, lingkup UI yang diubah

**Hard Gate PASS:** formulir URL memiliki label, status, error inline dan submit aktif; modal dapat ditutup dengan Escape. Kontrol pencarian, filter, pembaruan, dan detail admin diuji melalui browser. Tidak ada overflow halaman pada tiga ukuran yang diuji di kedua tema. Pasangan teks semantic yang dipakai terukur 5,20 sampai 14,83:1; tombol putih/rust 6,09:1; error terang 6,74:1 dan gelap 8,49:1. Batas kontrol terukur 3,32:1 dan 3,99:1. Ini pemeriksaan lingkup perubahan, bukan audit aksesibilitas seluruh aplikasi.

**Purpose Gate PASS:** perubahan mempertahankan permukaan, tipografi, dan aksen pada DESIGN.md. Nama akun ditebalkan agar terpisah dari email dan aktivitas. Tidak ada ilustrasi, statistik pemasaran, animasi dekoratif, atau identitas baru. Logo yang sudah ada diberi filter putih pada tema gelap agar terbaca.

**Liveliness PASS:** arah yang sudah ada tetap ENERGY 2 / RHYTHM 2 / MOTION 1. Pemantauan menempatkan akun online, peserta, dan room sebagai tugas berbeda; modal berfokus pada URL dan hasilnya. Aksen tetap untuk tindakan dan status fungsional.

**Craftsmanship PASS:** data berasal dari akun/presence/coordinator, bukan contoh yang disajikan sebagai data nyata. Keadaan kosong, menunggu, gagal, dan filter tanpa hasil mempunyai pesan. Screenshot terang/gelap pada ukuran ponsel dan desktop diperiksa; nama/email panjang membungkus. Implementasi ditulis melalui patch sumber, kemudian disalin ke proyek. Hasil build dan batas kemampuan dicatat di atas.
