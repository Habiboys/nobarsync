# Perbaikan daftar domain impor server

Dari terminal yang dikirim, proyek server berada di `/www/wwwroot/manonton` dan memakai `docker-compose.yml`.

Penyebab domain tetap ditolak: `.env` berisi dua `IMPORT_HOST_ALLOWLIST`. Daftar domain terisi di bagian atas, lalu ditimpa baris kosong pada bagian `encode limits`. Batas impor juga masih 2 GiB, sementara sumber video yang diperiksa berukuran sekitar 3,4 GB.

Jalankan pada terminal server. Perintah ini hanya mengganti dua variabel impor dan membuat ulang container API/worker; tidak menghapus volume atau mengubah kredensial lain:

```bash
cd /www/wwwroot/manonton
sed -i '/^IMPORT_HOST_ALLOWLIST=/d; /^IMPORT_MAX_BYTES=/d' .env
printf '\nIMPORT_HOST_ALLOWLIST=matthew-count-favors-don.trycloudflare.com,acefile.co\nIMPORT_MAX_BYTES=4294967296\n' >> .env
docker compose up -d --no-deps --force-recreate api worker
docker compose exec -T api printenv IMPORT_HOST_ALLOWLIST
docker compose exec -T worker printenv IMPORT_HOST_ALLOWLIST
docker compose exec -T api printenv IMPORT_MAX_BYTES
docker compose exec -T worker printenv IMPORT_MAX_BYTES
```

Kedua output domain harus sama:

```text
matthew-count-favors-don.trycloudflare.com,acefile.co
```

Kedua output ukuran harus `4294967296`.

Lakukan impor melalui modal Pustaka. Endpoint `/api/v1/media/import-url` menerima POST; membukanya melalui address bar mengirim GET dan tidak mengimpor film.

Bug terpisah GET yang ditafsirkan sebagai ID film sudah diperbaiki pada kode lokal: GET endpoint impor memberi JSON 405 dengan `Allow: POST`; ID film invalid atau tidak ditemukan memberi JSON 404. Perubahan ini belum dipasang pada server dalam sesi ini. Perbaikan sudah lolos 12 tes backend terkait route dan impor.

Jangan kirim seluruh `.env` lagi karena lampiran sebelumnya memuat kredensial layanan. Output `printenv` untuk dua variabel impor di atas sudah cukup untuk memeriksa konfigurasi ini.
