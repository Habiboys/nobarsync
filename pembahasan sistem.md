# NobarSync 2.0 — Rancangan Aplikasi Nonton Bareng Real-Time

Target: aplikasi nobar modern, streaming langsung dari cloud, sinkronisasi otomatis, realtime multiplayer, scalable, dan siap digunakan secara end-to-end.

Saya sudah membaca rancangan yang diberikan Claude. Secara konsep, jawabannya benar, terutama penggunaan HLS, Cloudflare R2, dan server sebagai pengendali waktu film. Namun, menurut saya masih banyak bagian penting yang belum dijelaskan, khususnya bagaimana aplikasi benar-benar bekerja ketika ada 50–1.000 penonton, bagaimana menangani buffering, bagaimana mendistribusikan video tanpa membebani VPS, serta bagaimana memastikan beberapa orang menonton pada posisi film yang hampir sama.

Ada satu keputusan arsitektur yang sangat penting.

## 1. Jangan samakan streaming terpusat dengan sinkronisasi terpusat

Bayangkan ada 100 orang masuk ke room yang sama untuk menonton film berdurasi dua jam.

Ada tiga pendekatan berbeda:

A. Streaming individual tanpa sinkronisasi

Sistem lama yang Mas gunakan. Setiap browser memutar video sendiri dan pengguna memperbaiki perbedaan waktu secara manual.

Tidak disarankan

B. Satu broadcast live dari server

Server menjalankan satu pemutaran, lalu mendistribusikan hasil streaming melalui HLS live atau WebRTC. Penonton mengikuti siaran tersebut.

Alternatif

C. Video terdistribusi, playback terpusat

Video dikirim langsung dari CDN ke setiap penonton, tetapi satu server mengontrol posisi, play, pause, seek, dan sinkronisasi seluruh room.

Rekomendasi

Saya merekomendasikan pendekatan C untuk NobarSync 2.0.

Mengapa? Karena tujuan sebenarnya bukan membuat semua penonton menerima paket video yang sama pada milidetik yang sama, melainkan membuat mereka menyaksikan adegan yang sama pada waktu yang hampir bersamaan.

Dengan pendekatan C:

- Penonton tidak perlu menyinkronkan film secara manual.
- Server tidak perlu mengirim ulang file video kepada setiap penonton.
- Setiap penonton dapat menyesuaikan kualitas video dengan internetnya sendiri.
- VPS terutama menangani API, room, chat, dan sinkronisasi.
- Pengguna baru bisa bergabung ketika film sudah berjalan dan otomatis menuju posisi terkini.
- Host tetap bisa melakukan play, pause, seek, dan mengganti film untuk semua penonton.

Perlu diperjelas: secara teknis setiap perangkat tetap menerima aliran video melalui koneksinya sendiri. Hal ini memang diperlukan untuk menampilkan video di perangkat masing-masing. Yang dibuat terpusat adalah sumber kebenaran status pemutaran dan waktu filmnya.

Kalau memang ingin semua orang mengikuti satu siaran live dan tidak bisa melakukan seek sesuka hati, pendekatan B juga bisa dibuat. Saya akan membandingkan keduanya dalam rancangan.

## 2. Memilih teknologi streaming: R2 atau Cloudflare Stream?

Saya sudah memeriksa dokumentasi Cloudflare terbaru. Ada dua produk yang menurut saya paling menarik untuk kebutuhan ini.

[Exploring Cloudflare R2 Storage: A Cost-Effective Alternative to S3 - DEV Community](https://images.openai.com/static-rsc-4/xljlD0zJ_k8bVw7nC77Jk7Z9VYaGR2V4P2r4yRxM_R38JTA4-LsdRLg-7yyjOhO4pOVUglsHirCjqLDP2Kgnobkp1YDES_bRsxZm0GL5YD0YBetrmNQPDDFY0A3QPrGJbRLDSVlklPQ1oyNQ4XXIhytfkkf_e5j3A0di_PVlyGU?purpose=inline)

Cloudflare R2 + FFmpeg

Penyimpanan objek untuk video, subtitle, thumbnail, dan hasil transcoding. Kita membangun pipeline streaming sendiri.

Pilihan untuk kontrol teknis penuh dan optimasi biaya skala besar.

[Cloudflare Stream Delivery | Streaming Video CDN  | Cloudflare](https://images.openai.com/static-rsc-4/WnVJTninAuhJe64jnYbr8EraMFokXPD6cRDclH3IVaJIZei-EK-mBrx4kfZhkhuxpZw4IhJw7EhdxMnTRBfmO4ZmTAVDiA8-U3CzAkqhjdyu-5AX3XI4w9ugIARCxkZ2rikQFnDcDiq-4X8te7gc7d1Ff65ap6FAzy0Kdwyhu1g?purpose=inline)

Cloudflare Stream

Layanan video terkelola yang menangani upload, encoding, adaptive bitrate, delivery, dan perlindungan akses video.

Pilihan untuk pengembangan lebih cepat dengan pengelolaan video lebih sederhana.

| Aspek            | R2 + FFmpeg                                             | Cloudflare Stream                       |
| ---------------- | ------------------------------------------------------- | --------------------------------------- |
| Penyimpanan      | Berdasarkan GB                                          | Berdasarkan durasi video                |
| Encoding video   | Dikerjakan sendiri                                      | Otomatis                                |
| Kualitas adaptif | Konfigurasi sendiri                                     | Otomatis                                |
| Biaya delivery   | Tanpa biaya egress R2, ada biaya operasi/Worker terkait | Berdasarkan menit ditonton              |
| Upload langsung  | S3-compatible API                                       | Direct upload API                       |
| Subtitle         | Kelola sendiri                                          | Ada dukungan WebVTT                     |
| Fleksibilitas    | Sangat tinggi                                           | Mengikuti kapabilitas layanan           |
| Kompleksitas     | Menengah–tinggi                                         | Rendah–menengah                         |
| Server FFmpeg    | Diperlukan                                              | Tidak diperlukan untuk encoding standar |

Cloudflare Stream mendukung upload langsung, encoding otomatis, serta distribusi HLS/DASH. Video dengan ukuran lebih dari 200 MB dapat diunggah menggunakan protokol TUS yang mendukung resumable upload.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://developers.cloudflare.com\&sz=32)

Cloudflare Stream docs+2



### Perkiraan biaya

SIMULASI CLOUDFARE STREAM

Jumlah penonton

### 20 orang

Durasi ditonton per orang

### 120 menit

Total durasi video tersimpan

### 120 menit

Delivery video

# $2.40

2.400 menit dikirim

Kapasitas storage

# $5.00

Prabayar per 1.000 menit/bulan

Total simulasi

# $7.40

Asumsi penonton menonton sampai selesai, tarif $1 per 1.000 menit delivery dan $5 per 1.000 menit kapasitas storage per bulan. Belum termasuk aplikasi, database, pajak, ataupun layanan tambahan.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://developers.cloudflare.com\&sz=32)

Cloudflare Stream docs+1

Sebagai perbandingan, tarif R2 Standard saat ini adalah $0,015/GB-bulan, dengan alokasi gratis 10 GB-bulan dan tanpa biaya egress R2. Namun, biaya transcoding, Worker, request, dan server tetap harus diperhitungkan.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://developers.cloudflare.com\&sz=32)

Cloudflare R2 docs+1



### Pilihan saya untuk proyek ini

Saya akan menjadikan R2 + FFmpeg sebagai arsitektur utama karena Mas ingin memiliki kontrol penuh terhadap aplikasi dan memahami cara streaming bekerja. Namun, sejak awal sistem kita rancang menggunakan media provider abstraction, sehingga nantinya bisa menggunakan Cloudflare Stream tanpa mengubah modul room dan sinkronisasi.

Artinya ada dua adapter:

- `R2HlsProvider` — video diproses sendiri dan disimpan sebagai HLS di R2.
- `CloudflareStreamProvider` — video dikelola Cloudflare Stream.

Tidak perlu menjalankan kedua provider sekaligus. Pilih R2 sebagai default dan gunakan Stream sebagai alternatif konfigurasi.

## 3. Arsitektur NobarSync 2.0

\#chatgpt-mermaid-\_r_r2\_{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;fill:rgb(13, 13, 13);}@keyframes edge-animation-frame{from{stroke-dashoffset:0;}}@keyframes dash{to{stroke-dashoffset:0;}}#chatgpt-mermaid-\_r_r2\_ .edge-animation-slow{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 50s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_r2\_ .edge-animation-fast{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 20s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_r2\_ .error-icon{fill:rgb(243, 243, 243);}#chatgpt-mermaid-\_r_r2\_ .error-text{fill:rgb(13, 13, 13);stroke:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_r2\_ .edge-thickness-normal{stroke-width:1px;}#chatgpt-mermaid-\_r_r2\_ .edge-thickness-thick{stroke-width:3.5px;}#chatgpt-mermaid-\_r_r2\_ .edge-pattern-solid{stroke-dasharray:0;}#chatgpt-mermaid-\_r_r2\_ .edge-thickness-invisible{stroke-width:0;fill:none;}#chatgpt-mermaid-\_r_r2\_ .edge-pattern-dashed{stroke-dasharray:3;}#chatgpt-mermaid-\_r_r2\_ .edge-pattern-dotted{stroke-dasharray:2;}#chatgpt-mermaid-\_r_r2\_ .marker{fill:rgb(143, 143, 143);stroke:rgb(143, 143, 143);}#chatgpt-mermaid-\_r_r2\_ .marker.cross{stroke:rgb(143, 143, 143);}#chatgpt-mermaid-\_r_r2\_ svg{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;}#chatgpt-mermaid-\_r_r2\_ p{margin:0;}#chatgpt-mermaid-\_r_r2\_ .label{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";color:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_r2\_ .cluster-label text{fill:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_r2\_ .cluster-label span{color:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_r2\_ .cluster-label span p{background-color:transparent;}#chatgpt-mermaid-\_r_r2\_ .label text,#chatgpt-mermaid-\_r_r2\_ span{fill:rgb(13, 13, 13);color:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_r2\_ .node rect,#chatgpt-mermaid-\_r_r2\_ .node circle,#chatgpt-mermaid-\_r_r2\_ .node ellipse,#chatgpt-mermaid-\_r_r2\_ .node polygon,#chatgpt-mermaid-\_r_r2\_ .node path{fill:rgb(222, 234, 251);stroke:rgb(83, 154, 248);stroke-width:1px;}#chatgpt-mermaid-\_r_r2\_ .rough-node .label text,#chatgpt-mermaid-\_r_r2\_ .node .label text,#chatgpt-mermaid-\_r_r2\_ .image-shape .label,#chatgpt-mermaid-\_r_r2\_ .icon-shape .label{text-anchor:middle;}#chatgpt-mermaid-\_r_r2\_ .node .katex path{fill:#000;stroke:#000;stroke-width:1px;}#chatgpt-mermaid-\_r_r2\_ .rough-node .label,#chatgpt-mermaid-\_r_r2\_ .node .label,#chatgpt-mermaid-\_r_r2\_ .image-shape .label,#chatgpt-mermaid-\_r_r2\_ .icon-shape .label{text-align:center;}#chatgpt-mermaid-\_r_r2\_ .node.clickable{cursor:pointer;}#chatgpt-mermaid-\_r_r2\_ .root .anchor path{fill:rgb(143, 143, 143)!important;stroke-width:0;stroke:rgb(143, 143, 143);}#chatgpt-mermaid-\_r_r2\_ .arrowheadPath{fill:rgb(143, 143, 143);}#chatgpt-mermaid-\_r_r2\_ .edgePath .path{stroke:rgb(143, 143, 143);stroke-width:1px;}#chatgpt-mermaid-\_r_r2\_ .flowchart-link{stroke:rgb(143, 143, 143);fill:none;}#chatgpt-mermaid-\_r_r2\_ .edgeLabel{background-color:rgb(252, 252, 252);text-align:center;}#chatgpt-mermaid-\_r_r2\_ .edgeLabel p{background-color:rgb(252, 252, 252);}#chatgpt-mermaid-\_r_r2\_ .edgeLabel rect{opacity:0.5;background-color:rgb(252, 252, 252);fill:rgb(252, 252, 252);}#chatgpt-mermaid-\_r_r2\_ .labelBkg{background-color:rgba(252, 252, 252, 0.5);}#chatgpt-mermaid-\_r_r2\_ .cluster rect{fill:rgb(243, 243, 243);stroke:rgba(0, 0, 0, 0.1);stroke-width:1px;}#chatgpt-mermaid-\_r_r2\_ .cluster text{fill:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_r2\_ .cluster span{color:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_r2\_ div.mermaidTooltip{position:absolute;text-align:center;max-width:200px;padding:2px;font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:12px;background:rgb(243, 243, 243);border:1px solid rgba(0, 0, 0, 0.1);border-radius:2px;pointer-events:none;z-index:100;}#chatgpt-mermaid-\_r_r2\_ .flowchartTitleText{text-anchor:middle;font-size:18px;fill:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_r2\_ rect.text{fill:none;stroke-width:0;}#chatgpt-mermaid-\_r_r2\_ .icon-shape,#chatgpt-mermaid-\_r_r2\_ .image-shape{background-color:rgb(252, 252, 252);text-align:center;}#chatgpt-mermaid-\_r_r2\_ .icon-shape p,#chatgpt-mermaid-\_r_r2\_ .image-shape p{background-color:rgb(252, 252, 252);padding:2px;}#chatgpt-mermaid-\_r_r2\_ .icon-shape .label rect,#chatgpt-mermaid-\_r_r2\_ .image-shape .label rect{opacity:0.5;background-color:rgb(252, 252, 252);fill:rgb(252, 252, 252);}#chatgpt-mermaid-\_r_r2\_ .label-icon{display:inline-block;height:1em;overflow:visible;vertical-align:-0.125em;}#chatgpt-mermaid-\_r_r2\_ .node .label-icon path{fill:currentColor;stroke:revert;stroke-width:revert;}#chatgpt-mermaid-\_r_r2\_ .node .neo-node{stroke:rgb(83, 154, 248);}#chatgpt-mermaid-\_r_r2\_ [data-look="neo"].node rect,#chatgpt-mermaid-\_r_r2\_ [data-look="neo"].cluster rect,#chatgpt-mermaid-\_r_r2\_ [data-look="neo"].node polygon{stroke:url(#chatgpt-mermaid-\_r_r2\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_r2\_ [data-look="neo"].swimlane.cluster rect{filter:none;}#chatgpt-mermaid-\_r_r2\_ [data-look="neo"].node path{stroke:url(#chatgpt-mermaid-\_r_r2\_-gradient);stroke-width:1px;}#chatgpt-mermaid-\_r_r2\_ [data-look="neo"].node .outer-path{filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_r2\_ [data-look="neo"].node .neo-line path{stroke:rgb(83, 154, 248);filter:none;}#chatgpt-mermaid-\_r_r2\_ [data-look="neo"].node circle{stroke:url(#chatgpt-mermaid-\_r_r2\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_r2\_ [data-look="neo"].node circle .state-start{fill:#000000;}#chatgpt-mermaid-\_r_r2\_ [data-look="neo"].icon-shape .icon{fill:url(#chatgpt-mermaid-\_r_r2\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_r2\_ [data-look="neo"].icon-shape .icon-neo path{stroke:url(#chatgpt-mermaid-\_r_r2\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_r2\_ .node text{font-size:14px;font-weight:600;letter-spacing:normal;fill:rgb(0, 79, 153);}#chatgpt-mermaid-\_r_r2\_ .edgeLabels text{font-size:13px;font-weight:600;letter-spacing:-0.08px;fill:rgb(0, 79, 153);}#chatgpt-mermaid-\_r_r2\_ .node tspan[font-weight="normal"],#chatgpt-mermaid-\_r_r2\_ .edgeLabels tspan[font-weight="normal"]{font-weight:600;}#chatgpt-mermaid-\_r_r2\_ .edgeLabel .label rect{opacity:1;rx:13px;ry:13px;fill:rgb(245, 250, 255);stroke:rgb(206, 219, 229);stroke-width:1px;}#chatgpt-mermaid-\_r_r2\_ .node rect,#chatgpt-mermaid-\_r_r2\_ .node circle,#chatgpt-mermaid-\_r_r2\_ .node ellipse,#chatgpt-mermaid-\_r_r2\_ .node polygon,#chatgpt-mermaid-\_r_r2\_ .node path{fill:rgb(229, 243, 255);stroke:rgba(0, 0, 0, 0.1);stroke-width:1px;}#chatgpt-mermaid-\_r_r2\_ .node rect{rx:16px;ry:16px;}#chatgpt-mermaid-\_r_r2\_ .mermaid-decision .label-container{fill:rgb(245, 250, 255);stroke:rgb(206, 219, 229);stroke-dasharray:2,2;}#chatgpt-mermaid-\_r_r2\_ .edgePaths .flowchart-link{stroke:rgb(143, 143, 143);stroke-width:1px;stroke-linecap:round;stroke-linejoin:round;}#chatgpt-mermaid-\_r_r2\_ .marker{fill:rgb(143, 143, 143);stroke:rgb(143, 143, 143);}#chatgpt-mermaid-\_r_r2\_ :root{--mermaid-font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";}Host / PenontonReact + TypeScriptElixir Phoenix APIPhoenix ChannelsPostgreSQLRoom Playback CoordinatorOban Job QueueFFmpeg WorkerCloudflare R2Cloudflare Worker / CDNWebSocketDirect UploadHLS + SubtitleRequest videoPrivate R2 bindingSigned playback token

Diagram tersebut menunjukkan pembagian tanggung jawab yang jelas.

Frontend — React + TypeScript

Mengelola player, room, tampilan film, chat, peserta, dan perhitungan sinkronisasi di browser.

Backend — Elixir + Phoenix

Mengelola autentikasi, room, permissions, playback coordinator, WebSocket, event realtime, serta state playback yang otoritatif.

Media Worker — FFmpeg + FFprobe

Memeriksa metadata video, membuat beberapa kualitas HLS, mengolah subtitle, dan menyimpan hasil ke R2.

Media Storage — Cloudflare R2

Menyimpan objek video dan HLS, sementara Cloudflare Worker memberikan akses terautentikasi melalui CDN.

Database — PostgreSQL

Menyimpan pengguna, room, daftar film, metadata, riwayat perintah, chat, serta snapshot state untuk pemulihan ketika server restart.

### Mengapa Elixir?

Menurut saya, Elixir memang masuk akal untuk aplikasi realtime seperti ini.

Elixir berjalan di atas BEAM dan memiliki mekanisme proses ringan serta supervisi yang cocok untuk pengelolaan banyak koneksi dan room secara bersamaan.

Phoenix juga memiliki Channels, PubSub, dan Presence untuk melacak aktivitas pengguna dan menyebarkan perubahan realtime.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://github.com\&sz=32)

GitHub+1



Saya menyarankan menggunakan satu proses `RoomCoordinator` untuk setiap room aktif. Proses ini bertugas:

1. Memegang state pemutaran terkini.
2. Memvalidasi perintah dari host.
3. Mengatur waktu pelaksanaan perintah.
4. Menyebarkan pembaruan state.
5. Mengelola kondisi pause, seek, dan pergantian film.
6. Memastikan perintah lama tidak menimpa state terbaru.

Jangan menjalankan encoding video langsung di proses request Phoenix. Pekerjaan berat FFmpeg harus berjalan di worker terpisah sehingga koneksi realtime tidak terganggu.

Dan jangan langsung menggunakan Redis atau Kubernetes untuk MVP. Satu instance Phoenix dengan PostgreSQL, Oban, dan worker terpisah sudah cukup sebagai fondasi. Redis baru dipertimbangkan ketika kebutuhan scaling atau shared state benar-benar menuntutnya.

## 4. Alur pengelolaan film: tanpa menyimpan permanen di VPS

Di sistem lama, Mas harus mengunduh film dari Google Drive ke disk server. Pada arsitektur baru, kita mengubah alur upload menjadi seperti berikut.

\#chatgpt-mermaid-\_r_rt\_{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;fill:rgb(13, 13, 13);}@keyframes edge-animation-frame{from{stroke-dashoffset:0;}}@keyframes dash{to{stroke-dashoffset:0;}}#chatgpt-mermaid-\_r_rt\_ .edge-animation-slow{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 50s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_rt\_ .edge-animation-fast{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 20s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_rt\_ .error-icon{fill:rgb(243, 243, 243);}#chatgpt-mermaid-\_r_rt\_ .error-text{fill:rgb(13, 13, 13);stroke:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_rt\_ .edge-thickness-normal{stroke-width:1px;}#chatgpt-mermaid-\_r_rt\_ .edge-thickness-thick{stroke-width:3.5px;}#chatgpt-mermaid-\_r_rt\_ .edge-pattern-solid{stroke-dasharray:0;}#chatgpt-mermaid-\_r_rt\_ .edge-thickness-invisible{stroke-width:0;fill:none;}#chatgpt-mermaid-\_r_rt\_ .edge-pattern-dashed{stroke-dasharray:3;}#chatgpt-mermaid-\_r_rt\_ .edge-pattern-dotted{stroke-dasharray:2;}#chatgpt-mermaid-\_r_rt\_ .marker{fill:rgb(143, 143, 143);stroke:rgb(143, 143, 143);}#chatgpt-mermaid-\_r_rt\_ .marker.cross{stroke:rgb(143, 143, 143);}#chatgpt-mermaid-\_r_rt\_ svg{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;}#chatgpt-mermaid-\_r_rt\_ p{margin:0;}#chatgpt-mermaid-\_r_rt\_ .label{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";color:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_rt\_ .cluster-label text{fill:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_rt\_ .cluster-label span{color:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_rt\_ .cluster-label span p{background-color:transparent;}#chatgpt-mermaid-\_r_rt\_ .label text,#chatgpt-mermaid-\_r_rt\_ span{fill:rgb(13, 13, 13);color:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_rt\_ .node rect,#chatgpt-mermaid-\_r_rt\_ .node circle,#chatgpt-mermaid-\_r_rt\_ .node ellipse,#chatgpt-mermaid-\_r_rt\_ .node polygon,#chatgpt-mermaid-\_r_rt\_ .node path{fill:rgb(222, 234, 251);stroke:rgb(83, 154, 248);stroke-width:1px;}#chatgpt-mermaid-\_r_rt\_ .rough-node .label text,#chatgpt-mermaid-\_r_rt\_ .node .label text,#chatgpt-mermaid-\_r_rt\_ .image-shape .label,#chatgpt-mermaid-\_r_rt\_ .icon-shape .label{text-anchor:middle;}#chatgpt-mermaid-\_r_rt\_ .node .katex path{fill:#000;stroke:#000;stroke-width:1px;}#chatgpt-mermaid-\_r_rt\_ .rough-node .label,#chatgpt-mermaid-\_r_rt\_ .node .label,#chatgpt-mermaid-\_r_rt\_ .image-shape .label,#chatgpt-mermaid-\_r_rt\_ .icon-shape .label{text-align:center;}#chatgpt-mermaid-\_r_rt\_ .node.clickable{cursor:pointer;}#chatgpt-mermaid-\_r_rt\_ .root .anchor path{fill:rgb(143, 143, 143)!important;stroke-width:0;stroke:rgb(143, 143, 143);}#chatgpt-mermaid-\_r_rt\_ .arrowheadPath{fill:rgb(143, 143, 143);}#chatgpt-mermaid-\_r_rt\_ .edgePath .path{stroke:rgb(143, 143, 143);stroke-width:1px;}#chatgpt-mermaid-\_r_rt\_ .flowchart-link{stroke:rgb(143, 143, 143);fill:none;}#chatgpt-mermaid-\_r_rt\_ .edgeLabel{background-color:rgb(252, 252, 252);text-align:center;}#chatgpt-mermaid-\_r_rt\_ .edgeLabel p{background-color:rgb(252, 252, 252);}#chatgpt-mermaid-\_r_rt\_ .edgeLabel rect{opacity:0.5;background-color:rgb(252, 252, 252);fill:rgb(252, 252, 252);}#chatgpt-mermaid-\_r_rt\_ .labelBkg{background-color:rgba(252, 252, 252, 0.5);}#chatgpt-mermaid-\_r_rt\_ .cluster rect{fill:rgb(243, 243, 243);stroke:rgba(0, 0, 0, 0.1);stroke-width:1px;}#chatgpt-mermaid-\_r_rt\_ .cluster text{fill:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_rt\_ .cluster span{color:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_rt\_ div.mermaidTooltip{position:absolute;text-align:center;max-width:200px;padding:2px;font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:12px;background:rgb(243, 243, 243);border:1px solid rgba(0, 0, 0, 0.1);border-radius:2px;pointer-events:none;z-index:100;}#chatgpt-mermaid-\_r_rt\_ .flowchartTitleText{text-anchor:middle;font-size:18px;fill:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_rt\_ rect.text{fill:none;stroke-width:0;}#chatgpt-mermaid-\_r_rt\_ .icon-shape,#chatgpt-mermaid-\_r_rt\_ .image-shape{background-color:rgb(252, 252, 252);text-align:center;}#chatgpt-mermaid-\_r_rt\_ .icon-shape p,#chatgpt-mermaid-\_r_rt\_ .image-shape p{background-color:rgb(252, 252, 252);padding:2px;}#chatgpt-mermaid-\_r_rt\_ .icon-shape .label rect,#chatgpt-mermaid-\_r_rt\_ .image-shape .label rect{opacity:0.5;background-color:rgb(252, 252, 252);fill:rgb(252, 252, 252);}#chatgpt-mermaid-\_r_rt\_ .label-icon{display:inline-block;height:1em;overflow:visible;vertical-align:-0.125em;}#chatgpt-mermaid-\_r_rt\_ .node .label-icon path{fill:currentColor;stroke:revert;stroke-width:revert;}#chatgpt-mermaid-\_r_rt\_ .node .neo-node{stroke:rgb(83, 154, 248);}#chatgpt-mermaid-\_r_rt\_ [data-look="neo"].node rect,#chatgpt-mermaid-\_r_rt\_ [data-look="neo"].cluster rect,#chatgpt-mermaid-\_r_rt\_ [data-look="neo"].node polygon{stroke:url(#chatgpt-mermaid-\_r_rt\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_rt\_ [data-look="neo"].swimlane.cluster rect{filter:none;}#chatgpt-mermaid-\_r_rt\_ [data-look="neo"].node path{stroke:url(#chatgpt-mermaid-\_r_rt\_-gradient);stroke-width:1px;}#chatgpt-mermaid-\_r_rt\_ [data-look="neo"].node .outer-path{filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_rt\_ [data-look="neo"].node .neo-line path{stroke:rgb(83, 154, 248);filter:none;}#chatgpt-mermaid-\_r_rt\_ [data-look="neo"].node circle{stroke:url(#chatgpt-mermaid-\_r_rt\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_rt\_ [data-look="neo"].node circle .state-start{fill:#000000;}#chatgpt-mermaid-\_r_rt\_ [data-look="neo"].icon-shape .icon{fill:url(#chatgpt-mermaid-\_r_rt\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_rt\_ [data-look="neo"].icon-shape .icon-neo path{stroke:url(#chatgpt-mermaid-\_r_rt\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_rt\_ .node text{font-size:14px;font-weight:600;letter-spacing:normal;fill:rgb(0, 79, 153);}#chatgpt-mermaid-\_r_rt\_ .edgeLabels text{font-size:13px;font-weight:600;letter-spacing:-0.08px;fill:rgb(0, 79, 153);}#chatgpt-mermaid-\_r_rt\_ .node tspan[font-weight="normal"],#chatgpt-mermaid-\_r_rt\_ .edgeLabels tspan[font-weight="normal"]{font-weight:600;}#chatgpt-mermaid-\_r_rt\_ .edgeLabel .label rect{opacity:1;rx:13px;ry:13px;fill:rgb(245, 250, 255);stroke:rgb(206, 219, 229);stroke-width:1px;}#chatgpt-mermaid-\_r_rt\_ .node rect,#chatgpt-mermaid-\_r_rt\_ .node circle,#chatgpt-mermaid-\_r_rt\_ .node ellipse,#chatgpt-mermaid-\_r_rt\_ .node polygon,#chatgpt-mermaid-\_r_rt\_ .node path{fill:rgb(229, 243, 255);stroke:rgba(0, 0, 0, 0.1);stroke-width:1px;}#chatgpt-mermaid-\_r_rt\_ .node rect{rx:16px;ry:16px;}#chatgpt-mermaid-\_r_rt\_ .mermaid-decision .label-container{fill:rgb(245, 250, 255);stroke:rgb(206, 219, 229);stroke-dasharray:2,2;}#chatgpt-mermaid-\_r_rt\_ .edgePaths .flowchart-link{stroke:rgb(143, 143, 143);stroke-width:1px;stroke-linecap:round;stroke-linejoin:round;}#chatgpt-mermaid-\_r_rt\_ .marker{fill:rgb(143, 143, 143);stroke:rgb(143, 143, 143);}#chatgpt-mermaid-\_r_rt\_ :root{--mermaid-font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";}Host memilih file videoBackend membuat uploadsessionBrowser upload langsung keR2Backend verifikasi fileOban membuat transcode jobWorker membaca file dari R2FFprobe + FFmpegHLS 480p / 720p / 1080pUpload hasil ke R2Video READYFilm bisa diputar di room

Keuntungan terbesar: video tidak perlu melewati Phoenix API saat upload. Browser mengunggah file langsung ke R2 menggunakan mekanisme presigned upload atau multipart upload.

Untuk encoding, worker masih perlu membaca data sumber. Dalam implementasi awal, worker boleh menyimpan file sementara di scratch disk, memprosesnya, lalu menghapusnya. Dengan demikian, file tidak disimpan permanen di VPS dan tidak memenuhi disk aplikasi utama.

### Sumber video yang perlu didukung

| Sumber                     | Strategi implementasi                                            |
| -------------------------- | ---------------------------------------------------------------- |
| Upload dari laptop         | Direct upload ke R2                                              |
| File dari Google Drive     | Import menggunakan akses resmi yang diizinkan, lalu simpan ke R2 |
| File dari URL langsung     | Import hanya dari sumber tepercaya dan konten yang diizinkan     |
| Video YouTube              | Gunakan YouTube IFrame Player API                                |
| Video yang sudah ada di R2 | Langsung gunakan media yang telah diproses                       |
| Cloudflare Stream          | Gunakan adapter provider alternatif                              |

Ada batasan penting pada YouTube. Kebijakan YouTube API melarang pengunduhan dan penyimpanan ulang konten audiovisual tanpa persetujuan tertulis YouTube. Karena itu, untuk dukungan umum YouTube, gunakan embedded player resmi dan mekanisme sinkronisasi khusus YouTube, bukan `yt-dlp` untuk mengunduh video sembarangan.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://developers.google.com\&sz=32)

Developer Policies  |  Google for Developers+1



YouTube juga tidak selalu dapat disinkronkan sepresisi player HLS sendiri karena ada pembatasan embedding, iklan, dan perilaku player yang berbeda.

Untuk Google Drive, jangan gunakan link share sebagai CDN permanen. Bahkan Cloudflare sendiri menyatakan bahwa link berbagi Google Drive rentan terhadap pembatasan akses dan rate limiting ketika digunakan untuk mengimpor video.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://developers.cloudflare.com\&sz=32)

Cloudflare Stream docs



## 5. Format streaming yang digunakan

Untuk film biasa yang telah tersedia sebagai file, gunakan HLS Video on Demand (VOD), bukan Live HLS.

HLS membagi film menjadi potongan kecil yang disebut segments. Browser mengunduh potongan-potongan tersebut sesuai kebutuhan dan kondisi jaringan.

Contoh struktur hasil encoding:

```
videos/
  movie-001/
    source/
      original.mp4
    hls/
      master.m3u8
      480p/
        index.m3u8
        init.mp4
        segment_00001.m4s
        segment_00002.m4s
      720p/
        index.m3u8
        init.mp4
        segment_00001.m4s
      1080p/
        index.m3u8
        init.mp4
        segment_00001.m4s
    subtitles/
      id.vtt
      en.vtt
    thumbnails/
      poster.webp
      preview_001.webp
    metadata.json
```

`master.m3u8` adalah playlist yang menunjuk beberapa pilihan kualitas video.

Browser akan mengambil kualitas berdasarkan kemampuan perangkat dan kondisi internet. Contohnya, penonton A menggunakan 1080p, sedangkan penonton B menggunakan 480p. Keduanya tetap berada pada detik film yang sama meskipun menerima file segment dengan kualitas berbeda.

Untuk konfigurasi awal:

| Resolusi | Target bitrate video ilustratif |
| -------- | ------------------------------- |
| 480p     | 800–1.200 kbps                  |
| 720p     | 2.000–3.000 kbps                |
| 1080p    | 4.000–6.000 kbps                |

Gunakan H.264 + AAC untuk kompatibilitas luas, fragmentasi HLS 4 detik dengan keyframe yang selaras antarkualitas, dan jangan melakukan upscaling jika sumber aslinya hanya 720p. Subtitle eksternal dapat dikonversi ke WebVTT.

Angka bitrate tersebut bukan nilai mutlak. Profil encoding sebaiknya disesuaikan dengan karakter video dan kemampuan server.

## 6. Inti aplikasi: Smart Sync Engine

Ini bagian paling penting. Tanpa mekanisme yang matang, meskipun backend memakai Elixir dan video ada di R2, masalah sinkronisasi akan tetap muncul.

Saya mengusulkan NobarSync Smart Sync Engine dengan lima komponen.

Server-authoritative timeline

Clock-offset estimation

Scheduled playback commands

Automatic drift correction

Buffering and reconnect recovery

### A. Server memegang satu timeline

Misalkan host memulai film pada menit ke-10.

Server menyimpan:

```
{
  "room_id": "ROOM-A123",
  "media_id": "movie-001",
  "revision": 42,
  "status": "playing",
  "anchor_position_ms": 600000,
  "anchor_server_time_ms": 1794100000000,
  "playback_rate": 1.0
}
```

Artinya film diputar dari posisi 600 detik (10 menit), dimulai pada waktu server yang dicatat dalam `anchor_server_time_ms`.

Posisi seharusnya dihitung dengan:

\\[ P(t)= \begin{cases} P_0, & \text{jika paused},\\\ P_0+(t-t_0)r, & \text{jika playing}. \end{cases} \\]

Keterangan:

- \\(P_0\\): posisi film saat state terakhir ditetapkan.
- \\(t_0\\): waktu server saat anchor dibuat.
- \\(t\\): waktu server saat ini.
- \\(r\\): playback rate.

Semua satuan waktu dalam perhitungan harus konsisten. Dalam contoh implementasi, semuanya menggunakan milidetik.

Jika lima detik berlalu, posisi target menjadi 605 detik, tidak peduli apakah pesan WebSocket tertentu datang terlambat atau tidak.

### B. Sinkronisasi jam browser dengan server

Browser pengguna belum tentu memiliki jam yang sama, dan koneksi setiap orang juga berbeda.

Karena itu, frontend mengirim ping untuk mengestimasi perbedaan antara waktu browser dan waktu server. Estimasi menggunakan midpoint request-response dan memilih sampel dengan round-trip time terendah.

Lakukan pengukuran awal beberapa kali, kemudian refresh secara periodik, misalnya setiap 30 detik. Gunakan jam monotonic untuk mengukur interval agar perubahan jam sistem tidak mengganggu perhitungan.

### C. Host menekan Play

Pada sistem lama, kurang lebih seperti ini:

```
Host klik Play
  -> WebSocket mengirim play
  -> User A menerima setelah 50 ms
  -> User B menerima setelah 220 ms
  -> User C menerima setelah 600 ms
  -> Playback tidak seragam
```

Pada sistem baru, host mengirim intent, bukan menyuruh semua perangkat langsung memutar.

Server menentukan waktu mulai bersama, misalnya 1,5 detik ke depan.

Penonton CPenonton BPenonton ASync ServerHostPenonton CPenonton BPenonton ASync ServerHost#chatgpt-mermaid-\_r_sv\_{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;fill:rgb(13, 13, 13);}@keyframes edge-animation-frame{from{stroke-dashoffset:0;}}@keyframes dash{to{stroke-dashoffset:0;}}#chatgpt-mermaid-\_r_sv\_ .edge-animation-slow{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 50s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_sv\_ .edge-animation-fast{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 20s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_sv\_ .error-icon{fill:rgb(243, 243, 243);}#chatgpt-mermaid-\_r_sv\_ .error-text{fill:rgb(13, 13, 13);stroke:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_sv\_ .edge-thickness-normal{stroke-width:1px;}#chatgpt-mermaid-\_r_sv\_ .edge-thickness-thick{stroke-width:3.5px;}#chatgpt-mermaid-\_r_sv\_ .edge-pattern-solid{stroke-dasharray:0;}#chatgpt-mermaid-\_r_sv\_ .edge-thickness-invisible{stroke-width:0;fill:none;}#chatgpt-mermaid-\_r_sv\_ .edge-pattern-dashed{stroke-dasharray:3;}#chatgpt-mermaid-\_r_sv\_ .edge-pattern-dotted{stroke-dasharray:2;}#chatgpt-mermaid-\_r_sv\_ .marker{fill:rgb(143, 143, 143);stroke:rgb(143, 143, 143);}#chatgpt-mermaid-\_r_sv\_ .marker.cross{stroke:rgb(143, 143, 143);}#chatgpt-mermaid-\_r_sv\_ svg{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;}#chatgpt-mermaid-\_r_sv\_ p{margin:0;}#chatgpt-mermaid-\_r_sv\_ .actor{stroke:rgb(83, 154, 248);fill:rgb(222, 234, 251);stroke-width:1;}#chatgpt-mermaid-\_r_sv\_ rect.actor.outer-path[data-look="neo"]{filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_sv\_ rect.note[data-look="neo"]{stroke:rgb(107, 198, 127);fill:rgb(243, 243, 243);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_sv\_ text.actor>tspan{fill:rgb(13, 13, 13);stroke:none;}#chatgpt-mermaid-\_r_sv\_ .actor-line{stroke:rgb(143, 143, 143);}#chatgpt-mermaid-\_r_sv\_ .innerArc{stroke-width:1.5;stroke-dasharray:none;}#chatgpt-mermaid-\_r_sv\_ .messageLine0{stroke-width:1.5;stroke-dasharray:none;stroke:rgb(143, 143, 143);}#chatgpt-mermaid-\_r_sv\_ .messageLine1{stroke-width:1.5;stroke-dasharray:2,2;stroke:rgb(143, 143, 143);}#chatgpt-mermaid-\_r_sv\_ [id$="-arrowhead"] path{fill:rgb(143, 143, 143);stroke:rgb(143, 143, 143);}#chatgpt-mermaid-\_r_sv\_ .sequenceNumber{fill:#707070;}#chatgpt-mermaid-\_r_sv\_ [id$="-sequencenumber"]{fill:rgb(143, 143, 143);}#chatgpt-mermaid-\_r_sv\_ [id$="-crosshead"] path{fill:rgb(143, 143, 143);stroke:rgb(143, 143, 143);}#chatgpt-mermaid-\_r_sv\_ .messageText{fill:rgb(13, 13, 13);stroke:none;}#chatgpt-mermaid-\_r_sv\_ .labelBox{stroke:rgba(0, 0, 0, 0.1);fill:rgb(252, 252, 252);filter:none;}#chatgpt-mermaid-\_r_sv\_ .labelText,#chatgpt-mermaid-\_r_sv\_ .labelText>tspan{fill:rgb(13, 13, 13);stroke:none;}#chatgpt-mermaid-\_r_sv\_ .loopText,#chatgpt-mermaid-\_r_sv\_ .loopText>tspan{fill:rgb(13, 13, 13);stroke:none;}#chatgpt-mermaid-\_r_sv\_ .sectionTitle,#chatgpt-mermaid-\_r_sv\_ .sectionTitle>tspan{fill:rgb(13, 13, 13);stroke:none;}#chatgpt-mermaid-\_r_sv\_ .loopLine{stroke-width:2px;stroke-dasharray:2,2;stroke:rgba(0, 0, 0, 0.1);fill:rgba(0, 0, 0, 0.1);}#chatgpt-mermaid-\_r_sv\_ .note{stroke:rgb(107, 198, 127);fill:rgb(243, 243, 243);}#chatgpt-mermaid-\_r_sv\_ .noteText,#chatgpt-mermaid-\_r_sv\_ .noteText>tspan{fill:rgb(13, 13, 13);stroke:none;font-weight:normal;}#chatgpt-mermaid-\_r_sv\_ .activation0{fill:rgb(243, 243, 243);stroke:hsl(0, 0%, 85.2941176471%);}#chatgpt-mermaid-\_r_sv\_ .activation1{fill:rgb(243, 243, 243);stroke:hsl(0, 0%, 85.2941176471%);}#chatgpt-mermaid-\_r_sv\_ .activation2{fill:rgb(243, 243, 243);stroke:hsl(0, 0%, 85.2941176471%);}#chatgpt-mermaid-\_r_sv\_ .actorPopupMenu{position:absolute;}#chatgpt-mermaid-\_r_sv\_ .actorPopupMenuPanel{position:absolute;fill:rgb(222, 234, 251);box-shadow:0px 8px 16px 0px rgba(0,0,0,0.2);filter:drop-shadow(3px 5px 2px rgb(0 0 0 / 0.4));}#chatgpt-mermaid-\_r_sv\_ .actor-man circle,#chatgpt-mermaid-\_r_sv\_ line{fill:rgb(222, 234, 251);stroke-width:2px;}#chatgpt-mermaid-\_r_sv\_ g rect.rect{filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));stroke:rgb(83, 154, 248);}#chatgpt-mermaid-\_r_sv\_ .node .neo-node{stroke:rgb(83, 154, 248);}#chatgpt-mermaid-\_r_sv\_ [data-look="neo"].node rect,#chatgpt-mermaid-\_r_sv\_ [data-look="neo"].cluster rect,#chatgpt-mermaid-\_r_sv\_ [data-look="neo"].node polygon{stroke:url(#chatgpt-mermaid-\_r_sv\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_sv\_ [data-look="neo"].swimlane.cluster rect{filter:none;}#chatgpt-mermaid-\_r_sv\_ [data-look="neo"].node path{stroke:url(#chatgpt-mermaid-\_r_sv\_-gradient);stroke-width:1px;}#chatgpt-mermaid-\_r_sv\_ [data-look="neo"].node .outer-path{filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_sv\_ [data-look="neo"].node .neo-line path{stroke:rgb(83, 154, 248);filter:none;}#chatgpt-mermaid-\_r_sv\_ [data-look="neo"].node circle{stroke:url(#chatgpt-mermaid-\_r_sv\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_sv\_ [data-look="neo"].node circle .state-start{fill:#000000;}#chatgpt-mermaid-\_r_sv\_ [data-look="neo"].icon-shape .icon{fill:url(#chatgpt-mermaid-\_r_sv\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_sv\_ [data-look="neo"].icon-shape .icon-neo path{stroke:url(#chatgpt-mermaid-\_r_sv\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_sv\_ :root{--mermaid-font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";}Semua menghitung waktu T berdasarkan server clockplay.requestValidasi + revision baruplay scheduled at Tplay at T, position Xplay at T, position Xplay at T, position XPlay / catch upPlay / catch upPlay / catch upplayback heartbeatplayback heartbeatplayback heartbeat

Contoh event:

```
{
  "event": "playback.state",
  "room_id": "ROOM-A123",
  "revision": 43,
  "media_id": "movie-001",
  "state": {
    "status": "playing",
    "anchor_position_ms": 600000,
    "anchor_server_time_ms": 1794100001500,
    "playback_rate": 1.0
  },
  "effective_at_ms": 1794100001500
}
```

Perhatikan bahwa `effective_at_ms` menunjukkan kapan perintah mulai berlaku. Sebelum waktu tersebut, server tetap mempertahankan state sebelumnya.

Jeda scheduling harus memperhitungkan RTT peserta. Jika pesan baru diterima setelah waktu eksekusi, klien langsung menuju posisi timeline terkini, bukan memulai dari posisi yang sudah tertinggal.

### D. Koreksi otomatis ketika penonton tertinggal

Misalnya kondisi saat menonton:

Timeline server

## 12:35.000

Penonton A

12:34.900 — tertinggal 100 ms

Normal

Penonton B

12:34.400 — tertinggal 600 ms

Koreksi halus

Penonton C

12:31.000 — tertinggal 4 detik

Seek otomatis

Strategi awal yang bisa digunakan:

| Selisih playback    | Tindakan                                                |
| ------------------- | ------------------------------------------------------- |
| Sampai 200 ms       | Tidak perlu koreksi                                     |
| 200–1.500 ms        | Koreksi `playbackRate` secara halus, misalnya 0,97–1,05 |
| Lebih dari 1.500 ms | Seek ke posisi target                                   |
| Sedang buffering    | Tunggu hingga cukup buffered, lalu catch up             |
| Baru reconnect      | Ambil state terbaru dan hitung posisi target            |

Angka-angka tersebut adalah parameter awal yang harus dituning melalui pengujian. Jangan melakukan seek berulang setiap detik karena bisa mengakibatkan video tersendat. Tambahkan hysteresis, cooldown, dan pemeriksaan buffer sebelum melakukan hard correction.

Target realistis: pada koneksi dan perangkat yang memadai, usahakan selisih playback p95 tidak lebih dari 500 ms. Target 200–300 ms boleh dijadikan sasaran optimasi, tetapi jangan mengklaim semua penonton akan selalu frame-perfect. Jaringan, decoder video, dan browser memiliki keterbatasan.

### E. Buffering: apakah semuanya harus ikut pause?

Ini perlu disediakan sebagai pengaturan room, bukan dipaksakan untuk semua pengguna.

Saya menyarankan tiga mode.

| Mode                 | Perilaku                                                                                      |
| -------------------- | --------------------------------------------------------------------------------------------- |
| Independent Recovery | Penonton yang buffering akan mengejar timeline sendiri. Penonton lain tetap menonton.         |
| Pause for Everyone   | Jika peserta aktif mengalami buffering melewati ambang yang ditentukan, seluruh room dipause. |
| Host Controlled      | Hanya host yang bisa memutuskan pause bersama.                                                |

Untuk room besar, mode pertama jauh lebih praktis. Bayangkan ada 500 penonton; tidak masuk akal jika satu koneksi lambat menghentikan film untuk semuanya.

Untuk room kecil bersama teman, mode pause otomatis justru bisa lebih menyenangkan.

### F. Masalah autoplay browser

Ada satu kondisi yang sering terlewat dalam aplikasi seperti ini.

Browser dapat memblokir pemutaran video bersuara yang dijalankan otomatis oleh JavaScript tanpa interaksi pengguna. Pemanggilan `video.play()` bisa gagal dengan `NotAllowedError`.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://developer.mozilla.org\&sz=32)

MDN



Karena itu, saat join room, tampilkan tombol:

"Siap Nonton — Aktifkan Player"

Setelah pengguna mengaktifkan player, sistem melakukan preload dan menunggu instruksi host. Jika pemutaran masih diblokir, tampilkan overlay untuk mengizinkan playback dan otomatis mengejar timeline setelah pengguna menekan tombol.

Dengan pendekatan ini, masalah autoplay tidak membuat room berhenti bekerja.

## 7. Pengalaman pengguna yang saya usulkan

Aplikasinya sebaiknya bukan hanya menampilkan video dan chat, tetapi terasa seperti sebuah ruang bioskop digital.

[Watch Party App | Watch Together Online | Movmash](https://images.openai.com/static-rsc-4/Xndq4QBiYKBzX-qY5JQzxJbnX50dQkH-RsOW1Ydsx6uoJX7nuQHA88YKjWZJShCegmjyCU2l2T-2VVboyRoONvTf7lSnzhHhbqID7o0aU7tt23bqh3wBKfTgAYzLmQh-_arPA_El-ZKT9wXcqT5vbTvNLw2f_DhLEqYcEIMyIEo?purpose=inline)

[HBO Max Watch Party | Teleparty | Watch HBO Max Together](https://images.openai.com/static-rsc-4/ewnX9mQu6LqY2Wkmsviq0-i1RjAX-UO0PbnAn2maJB4tUeptzaDlDZ1I8KaPJX5EsLZy7rhCjk27Nm1wIAPlzfeYSJlL8tGJwSATZITYIxwcobzw2veNy8-absyQ1jZIxAQCJOCXJEyc3vd8K6aCB62ARPUzPO0m1IVkPN3I2bQ?purpose=inline)

[Multi - Media Platform by irakli talavadze for TiMN on Dribbble](https://images.openai.com/static-rsc-4/phsSH-M7pWJPdDKxIvIBLJXa-f5rWxqvJPftATK2LUZGG2jeuBLDLAlisOdebQghc36SdSJpJvEXs-Q59iiUdes3iDTFRMrtn0zDlMNz3SRzhHjJZOfX324UVJRKjtba1jgFrjQylVKP6vuJ3obtL72QASvqU1sn0Tq6v0f6QZE?purpose=inline)

12

Referensi visual untuk arah desain antarmuka, bukan hasil implementasi NobarSync.

### Halaman dan fitur

| Halaman        | Fitur                                             |
| -------------- | ------------------------------------------------- |
| Landing        | Hero, fitur aplikasi, buat/join room              |
| Authentication | Login, register, guest join                       |
| Dashboard      | Room aktif, riwayat, lanjut menonton              |
| Media Library  | Upload, import, poster, status encoding           |
| Create Room    | Pilih film, privasi, password, mode kontrol       |
| Waiting Room   | Daftar peserta, ready check, countdown            |
| Watch Room     | Video player, chat, reaksi, peserta, kontrol host |
| Profile        | Nama, avatar, pengaturan pengguna                 |
| Admin          | Pengelolaan video, pengguna, room, storage, jobs  |

### Fitur tambahan yang membuat aplikasi menarik

Saya akan mengurutkannya berdasarkan prioritas:

- Wajib: room code, undangan, guest access, host-only control, autoplay preparation, chat realtime, participant presence, reconnect otomatis, sinkronisasi, subtitle, dan quality selector.
- Sangat direkomendasikan: ready check sebelum film dimulai, countdown 3-2-1, emoji reactions, host transfer, waiting room, playlist, dan voting film berikutnya.
- Pengembangan berikutnya: voice chat menggunakan LiveKit, picture-in-picture, theater ambience, timestamped reactions, watch history, dan jadwal nobar bersama.

Untuk voice chat, saya tidak akan menggabungkan audio percakapan dengan pipeline HLS film. Gunakan sistem WebRTC terpisah agar suara percakapan tidak mencampuri jalur distribusi video.

## 8. Desain backend dan database

### Modul Elixir/Phoenix

```
NobarSync
├── Accounts
│   ├── Users
│   ├── Sessions
│   └── GuestIdentity
├── Media
│   ├── MediaAssets
│   ├── MediaVariants
│   ├── UploadSessions
│   ├── MediaProviders
│   └── MediaProcessing
├── WatchRooms
│   ├── Rooms
│   ├── Memberships
│   ├── Invitations
│   └── RoomSettings
├── Playback
│   ├── RoomCoordinator
│   ├── Timeline
│   ├── CommandHandler
│   ├── StatePersistence
│   └── PlaybackRecovery
├── Realtime
│   ├── RoomChannel
│   ├── RoomPresence
│   └── PubSub
├── Messaging
│   ├── Messages
│   └── Reactions
└── Analytics
    ├── SyncMetrics
    └── SessionMetrics
```

Elixir mengelola semua event realtime. Untuk room yang aktif, coordinator memegang timeline playback, sementara PostgreSQL menyimpan snapshot dan riwayat perubahan yang penting.

### Skema database utama

| Tabel                  | Informasi utama                                  |
| ---------------------- | ------------------------------------------------ |
| `users`                | ID, nama, email, password hash, avatar           |
| `sessions`             | User, token/session, kedaluwarsa                 |
| `media_assets`         | Judul, sumber, provider, status, durasi, pemilik |
| `media_variants`       | Resolusi, codec, bitrate, playlist path          |
| `media_subtitles`      | Bahasa, format, object key                       |
| `upload_sessions`      | Upload ID, status, ukuran, progress              |
| `rooms`                | Kode, host, privasi, media aktif, konfigurasi    |
| `room_members`         | Room, user/guest, role, waktu bergabung          |
| `room_playback_states` | Revision, status, anchor, effective time         |
| `playback_events`      | Riwayat play, pause, seek, pergantian media      |
| `room_messages`        | Pengirim, room, isi, timestamp                   |
| `room_invitations`     | Kode undangan, kedaluwarsa, batas pemakaian      |
| `audit_logs`           | Aktivitas administratif penting                  |

Gunakan UUID untuk identifier internal, sementara kode room yang dibagikan ke pengguna dibuat lebih pendek dan mudah diketik.

Tambahkan indeks untuk `room_code`, `media_status`, `room_id + created_at`, serta constraint yang mencegah state atau membership duplikat.

### REST API

```
POST   /api/v1/auth/register
POST   /api/v1/auth/login
POST   /api/v1/auth/logout
GET    /api/v1/auth/me

GET    /api/v1/media
POST   /api/v1/media/uploads
POST   /api/v1/media/uploads/:id/complete
GET    /api/v1/media/:id
DELETE /api/v1/media/:id
GET    /api/v1/media/:id/processing

POST   /api/v1/rooms
GET    /api/v1/rooms
GET    /api/v1/rooms/:code
POST   /api/v1/rooms/:code/join
POST   /api/v1/rooms/:code/leave
PATCH  /api/v1/rooms/:code/settings
POST   /api/v1/rooms/:code/transfer-host
GET    /api/v1/rooms/:code/playback
POST   /api/v1/rooms/:code/media

POST   /api/v1/playback/token
GET    /api/v1/health
```

REST digunakan untuk resource dan transaksi biasa. Operasi playback yang memerlukan komunikasi realtime dilakukan melalui Phoenix Channels.

### Protokol WebSocket

| Event                   | Arah            | Keterangan                   |
| ----------------------- | --------------- | ---------------------------- |
| `room.join`             | Client → Server | Bergabung                    |
| `room.snapshot`         | Server → Client | State terbaru                |
| `room.presence`         | Server → Client | Peserta online               |
| `clock.ping`            | Client ↔ Server | Estimasi offset              |
| `playback.play`         | Client → Server | Request play                 |
| `playback.pause`        | Client → Server | Request pause                |
| `playback.seek`         | Client → Server | Request seek                 |
| `playback.state`        | Server → Client | State otoritatif             |
| `playback.heartbeat`    | Client → Server | Laporan posisi dan buffering |
| `player.ready`          | Client → Server | Player sudah siap            |
| `player.buffering`      | Client → Server | Status buffering             |
| `chat.send`             | Client → Server | Mengirim pesan               |
| `chat.message`          | Server → Client | Broadcast pesan              |
| `reaction.send`         | Client → Server | Mengirim reaksi              |
| `room.media_changed`    | Server → Client | Film berganti                |
| `room.settings_changed` | Server → Client | Pengaturan berubah           |

Setiap command playback harus diberi `request_id` untuk idempotensi dan setiap state memiliki `revision` yang meningkat.

Contohnya, jika state revision 52 sudah diterima, pesan revision 51 tidak boleh diterapkan lagi.

## 9. Keamanan akses video

Ini salah satu bagian yang perlu ditangani dengan cermat.

Cloudflare R2 pada dasarnya merupakan private object storage. Jika bucket dibuka menggunakan custom domain biasa, objek dapat menjadi publik melalui URL tersebut. Selain itu, presigned URL S3 R2 tidak dapat langsung digunakan pada custom domain CDN.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://developers.cloudflare.com\&sz=32)

Cloudflare Cache (CDN) docs+1



Untuk aplikasi dengan room private, gunakan:

\#chatgpt-mermaid-\_r_ug\_{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;fill:rgb(13, 13, 13);}@keyframes edge-animation-frame{from{stroke-dashoffset:0;}}@keyframes dash{to{stroke-dashoffset:0;}}#chatgpt-mermaid-\_r_ug\_ .edge-animation-slow{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 50s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_ug\_ .edge-animation-fast{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 20s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_ug\_ .error-icon{fill:rgb(243, 243, 243);}#chatgpt-mermaid-\_r_ug\_ .error-text{fill:rgb(13, 13, 13);stroke:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_ug\_ .edge-thickness-normal{stroke-width:1px;}#chatgpt-mermaid-\_r_ug\_ .edge-thickness-thick{stroke-width:3.5px;}#chatgpt-mermaid-\_r_ug\_ .edge-pattern-solid{stroke-dasharray:0;}#chatgpt-mermaid-\_r_ug\_ .edge-thickness-invisible{stroke-width:0;fill:none;}#chatgpt-mermaid-\_r_ug\_ .edge-pattern-dashed{stroke-dasharray:3;}#chatgpt-mermaid-\_r_ug\_ .edge-pattern-dotted{stroke-dasharray:2;}#chatgpt-mermaid-\_r_ug\_ .marker{fill:rgb(143, 143, 143);stroke:rgb(143, 143, 143);}#chatgpt-mermaid-\_r_ug\_ .marker.cross{stroke:rgb(143, 143, 143);}#chatgpt-mermaid-\_r_ug\_ svg{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;}#chatgpt-mermaid-\_r_ug\_ p{margin:0;}#chatgpt-mermaid-\_r_ug\_ .label{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";color:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_ug\_ .cluster-label text{fill:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_ug\_ .cluster-label span{color:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_ug\_ .cluster-label span p{background-color:transparent;}#chatgpt-mermaid-\_r_ug\_ .label text,#chatgpt-mermaid-\_r_ug\_ span{fill:rgb(13, 13, 13);color:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_ug\_ .node rect,#chatgpt-mermaid-\_r_ug\_ .node circle,#chatgpt-mermaid-\_r_ug\_ .node ellipse,#chatgpt-mermaid-\_r_ug\_ .node polygon,#chatgpt-mermaid-\_r_ug\_ .node path{fill:rgb(222, 234, 251);stroke:rgb(83, 154, 248);stroke-width:1px;}#chatgpt-mermaid-\_r_ug\_ .rough-node .label text,#chatgpt-mermaid-\_r_ug\_ .node .label text,#chatgpt-mermaid-\_r_ug\_ .image-shape .label,#chatgpt-mermaid-\_r_ug\_ .icon-shape .label{text-anchor:middle;}#chatgpt-mermaid-\_r_ug\_ .node .katex path{fill:#000;stroke:#000;stroke-width:1px;}#chatgpt-mermaid-\_r_ug\_ .rough-node .label,#chatgpt-mermaid-\_r_ug\_ .node .label,#chatgpt-mermaid-\_r_ug\_ .image-shape .label,#chatgpt-mermaid-\_r_ug\_ .icon-shape .label{text-align:center;}#chatgpt-mermaid-\_r_ug\_ .node.clickable{cursor:pointer;}#chatgpt-mermaid-\_r_ug\_ .root .anchor path{fill:rgb(143, 143, 143)!important;stroke-width:0;stroke:rgb(143, 143, 143);}#chatgpt-mermaid-\_r_ug\_ .arrowheadPath{fill:rgb(143, 143, 143);}#chatgpt-mermaid-\_r_ug\_ .edgePath .path{stroke:rgb(143, 143, 143);stroke-width:1px;}#chatgpt-mermaid-\_r_ug\_ .flowchart-link{stroke:rgb(143, 143, 143);fill:none;}#chatgpt-mermaid-\_r_ug\_ .edgeLabel{background-color:rgb(252, 252, 252);text-align:center;}#chatgpt-mermaid-\_r_ug\_ .edgeLabel p{background-color:rgb(252, 252, 252);}#chatgpt-mermaid-\_r_ug\_ .edgeLabel rect{opacity:0.5;background-color:rgb(252, 252, 252);fill:rgb(252, 252, 252);}#chatgpt-mermaid-\_r_ug\_ .labelBkg{background-color:rgba(252, 252, 252, 0.5);}#chatgpt-mermaid-\_r_ug\_ .cluster rect{fill:rgb(243, 243, 243);stroke:rgba(0, 0, 0, 0.1);stroke-width:1px;}#chatgpt-mermaid-\_r_ug\_ .cluster text{fill:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_ug\_ .cluster span{color:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_ug\_ div.mermaidTooltip{position:absolute;text-align:center;max-width:200px;padding:2px;font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:12px;background:rgb(243, 243, 243);border:1px solid rgba(0, 0, 0, 0.1);border-radius:2px;pointer-events:none;z-index:100;}#chatgpt-mermaid-\_r_ug\_ .flowchartTitleText{text-anchor:middle;font-size:18px;fill:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_ug\_ rect.text{fill:none;stroke-width:0;}#chatgpt-mermaid-\_r_ug\_ .icon-shape,#chatgpt-mermaid-\_r_ug\_ .image-shape{background-color:rgb(252, 252, 252);text-align:center;}#chatgpt-mermaid-\_r_ug\_ .icon-shape p,#chatgpt-mermaid-\_r_ug\_ .image-shape p{background-color:rgb(252, 252, 252);padding:2px;}#chatgpt-mermaid-\_r_ug\_ .icon-shape .label rect,#chatgpt-mermaid-\_r_ug\_ .image-shape .label rect{opacity:0.5;background-color:rgb(252, 252, 252);fill:rgb(252, 252, 252);}#chatgpt-mermaid-\_r_ug\_ .label-icon{display:inline-block;height:1em;overflow:visible;vertical-align:-0.125em;}#chatgpt-mermaid-\_r_ug\_ .node .label-icon path{fill:currentColor;stroke:revert;stroke-width:revert;}#chatgpt-mermaid-\_r_ug\_ .node .neo-node{stroke:rgb(83, 154, 248);}#chatgpt-mermaid-\_r_ug\_ [data-look="neo"].node rect,#chatgpt-mermaid-\_r_ug\_ [data-look="neo"].cluster rect,#chatgpt-mermaid-\_r_ug\_ [data-look="neo"].node polygon{stroke:url(#chatgpt-mermaid-\_r_ug\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_ug\_ [data-look="neo"].swimlane.cluster rect{filter:none;}#chatgpt-mermaid-\_r_ug\_ [data-look="neo"].node path{stroke:url(#chatgpt-mermaid-\_r_ug\_-gradient);stroke-width:1px;}#chatgpt-mermaid-\_r_ug\_ [data-look="neo"].node .outer-path{filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_ug\_ [data-look="neo"].node .neo-line path{stroke:rgb(83, 154, 248);filter:none;}#chatgpt-mermaid-\_r_ug\_ [data-look="neo"].node circle{stroke:url(#chatgpt-mermaid-\_r_ug\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_ug\_ [data-look="neo"].node circle .state-start{fill:#000000;}#chatgpt-mermaid-\_r_ug\_ [data-look="neo"].icon-shape .icon{fill:url(#chatgpt-mermaid-\_r_ug\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_ug\_ [data-look="neo"].icon-shape .icon-neo path{stroke:url(#chatgpt-mermaid-\_r_ug\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_ug\_ .node text{font-size:14px;font-weight:600;letter-spacing:normal;fill:rgb(0, 79, 153);}#chatgpt-mermaid-\_r_ug\_ .edgeLabels text{font-size:13px;font-weight:600;letter-spacing:-0.08px;fill:rgb(0, 79, 153);}#chatgpt-mermaid-\_r_ug\_ .node tspan[font-weight="normal"],#chatgpt-mermaid-\_r_ug\_ .edgeLabels tspan[font-weight="normal"]{font-weight:600;}#chatgpt-mermaid-\_r_ug\_ .edgeLabel .label rect{opacity:1;rx:13px;ry:13px;fill:rgb(245, 250, 255);stroke:rgb(206, 219, 229);stroke-width:1px;}#chatgpt-mermaid-\_r_ug\_ .node rect,#chatgpt-mermaid-\_r_ug\_ .node circle,#chatgpt-mermaid-\_r_ug\_ .node ellipse,#chatgpt-mermaid-\_r_ug\_ .node polygon,#chatgpt-mermaid-\_r_ug\_ .node path{fill:rgb(229, 243, 255);stroke:rgba(0, 0, 0, 0.1);stroke-width:1px;}#chatgpt-mermaid-\_r_ug\_ .node rect{rx:16px;ry:16px;}#chatgpt-mermaid-\_r_ug\_ .mermaid-decision .label-container{fill:rgb(245, 250, 255);stroke:rgb(206, 219, 229);stroke-dasharray:2,2;}#chatgpt-mermaid-\_r_ug\_ .edgePaths .flowchart-link{stroke:rgb(143, 143, 143);stroke-width:1px;stroke-linecap:round;stroke-linejoin:round;}#chatgpt-mermaid-\_r_ug\_ .marker{fill:rgb(143, 143, 143);stroke:rgb(143, 143, 143);}#chatgpt-mermaid-\_r_ug\_ :root{--mermaid-font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";}PenontonPhoenix: validasi membershipPlayback token scopedCloudflare WorkerToken valid?403 ForbiddenEdge CachePrivate R2TidakYaCache missCache hit

Worker harus memvalidasi token sebelum melakukan cache lookup, bukan hanya memvalidasi manifest. Segment video dan subtitle juga memerlukan perlindungan akses.

Gunakan token yang dibatasi berdasarkan media, room, dan waktu kedaluwarsa. Untuk menjaga performa, gunakan validasi tanda tangan lokal di edge, bukan memanggil Phoenix API untuk setiap segment. Endpoint untuk memperbarui hak akses dapat memeriksa membership terkini.

Hal penting lainnya:

- Batasi ukuran dan jenis file upload.
- Validasi file menggunakan FFprobe dan pemeriksaan konten, bukan ekstensi saja.
- Cegah SSRF pada fitur import URL dengan allowlist sumber, validasi redirect, dan pemblokiran IP internal/metadata endpoint.
- Batasi CPU, memory, waktu, dan storage sementara untuk worker.
- Terapkan rate limiting, akses berbasis role, log audit, serta sanitasi chat.
- Pisahkan kredensial R2 dan Cloudflare dari frontend.
- Pastikan cache segment tidak memasukkan identitas pengguna ke cache key yang menyebabkan duplikasi, tetapi setiap request tetap melewati pemeriksaan otorisasi.
- Simpan secrets di environment atau secret manager, bukan repository.

Untuk fitur import dan hosting film, aplikasi harus digunakan dengan konten yang memang memiliki izin untuk disimpan dan didistribusikan. Room tertutup tidak otomatis menghilangkan kewajiban perizinan konten.

## 10. Deployment dan infrastruktur

Untuk tahap awal, saya menyarankan satu VPS yang menjalankan aplikasi serta worker, sementara file film disimpan di R2.

```
Internet
  |
  v
Cloudflare DNS + TLS
  |
  v
VPS
├── Caddy / Reverse Proxy
├── Phoenix API + Channels
├── React Frontend
├── PostgreSQL
├── Oban Worker
└── FFmpeg / FFprobe
       |
       v
Cloudflare R2 + Media Worker/CDN
```

Jika penggunaan meningkat, worker encoding dapat dipindahkan ke server terpisah tanpa mengubah arsitektur API.

Kebutuhan awal yang masuk akal adalah VPS dengan 2–4 vCPU dan RAM 4–8 GB untuk pengembangan/room kecil. Jika melakukan transcoding 1080p pada server yang sama, kapasitas CPU dan scratch disk mungkin perlu dinaikkan. Ini adalah titik awal sizing, bukan jaminan kapasitas penonton.

### Kapan perlu scale?

| Skala                    | Strategi                                               |
| ------------------------ | ------------------------------------------------------ |
| Beberapa room kecil      | Satu Phoenix node + satu worker                        |
| Banyak room aktif        | Tambah Phoenix node dan load balancer                  |
| Encoding semakin banyak  | Tambah media worker dan concurrency limit              |
| Realtime multi-node      | Distributed PubSub, coordinator ownership dan failover |
| Lalu lintas video tinggi | Optimalkan CDN, caching dan media delivery             |

Jangan menilai kapasitas hanya berdasarkan jumlah WebSocket. Profil aktivitas per room, heartbeat, chat, jumlah event dan beban database juga memengaruhi kapasitas.

## 11. Tahapan implementasi end-to-end

Berikut urutan yang saya anggap paling aman supaya tidak terjebak membangun banyak fitur tetapi sistem utama belum benar-benar berjalan.

01

Foundation

Monorepo, Phoenix, React, PostgreSQL, Docker Compose, environment, auth, dan migrations.

Output: register/login, frontend terhubung ke backend, semua service bisa dijalankan.

02

Realtime Room

Create/join room, host permissions, Presence, daftar peserta, room settings, invitation.

Output: pengguna dari browser berbeda bisa masuk room yang sama secara realtime.

03

Smart Sync Engine

Timeline server, clock sync, scheduled commands, drift correction, reconnect, late join, buffering.

Output: video sampel tersinkron otomatis tanpa R2 terlebih dahulu.

04

Media Pipeline

Direct upload R2, Oban, FFmpeg, HLS variants, subtitle, thumbnail, metadata, retry dan cleanup.

Output: file yang diunggah menjadi video siap streaming dari cloud.

05

Production Player

HLS player, adaptive bitrate, token akses, quality selector, subtitle, fullscreen, audio controls.

Output: seluruh room bisa menonton konten HLS dengan sinkronisasi otomatis.

06

Watch Party Experience

Chat, reaksi, playlist, voting, countdown, ready check, host transfer, responsive UI.

Output: aplikasi terasa lengkap sebagai platform nobar, bukan sekadar video player.

07

Testing dan Production Hardening

Playwright E2E, unit/integration tests, simulated network delay, WebSocket load test, monitoring, TLS, deployment.

Output: build produksi, migration, backup, panduan deploy, dan laporan pengujian.

### Skenario pengujian yang wajib lolos

Setidaknya sistem harus diuji dalam kondisi berikut:

1. Tiga browser membuka satu room dan semuanya mengikuti play/pause/seek host.
2. Satu penonton terlambat join 30 menit, lalu otomatis masuk ke posisi terkini.
3. Koneksi satu penonton putus selama 15 detik, kemudian reconnect tanpa kehilangan status room.
4. Host menekan play dan seek secara berurutan dalam waktu singkat; revision lama tidak mengacaukan timeline.
5. Satu penonton menggunakan koneksi lambat dan berpindah ke kualitas lebih rendah, sementara yang lain tetap memutar film.
6. Refresh halaman, pergantian host, room berpassword, dan percobaan mengakses video tanpa izin.
7. Server aplikasi direstart saat film berjalan, lalu room dapat dipulihkan dari snapshot yang tersimpan.
8. Upload beberapa GB yang terputus dapat dilanjutkan, dan pekerjaan transcoding yang gagal bisa di-retry tanpa menghasilkan data duplikat.
9. Dua puluh atau lebih klien simulasi diberi RTT dan jitter berbeda, kemudian sistem mencatat distribusi playback drift.
10. Seluruh alur dijalankan menggunakan build produksi, bukan hanya developer server.

Ukuran kualitasnya bukan hanya “video berjalan”, tetapi juga sinkronisasi p50/p95, reconnect recovery, buffering rate, latency command, error rate, dan keberhasilan proses upload.

## 12. Alternatif: bagaimana jika benar-benar ingin satu siaran live?

Jika tujuan Mas adalah konsep seperti televisi, yaitu semua orang mengikuti satu siaran yang sedang berlangsung, kita bisa membangun mode kedua bernama Broadcast Mode.

| Komponen     | Watch Party Mode                | Broadcast Mode                |
| ------------ | ------------------------------- | ----------------------------- |
| Sumber video | File HLS VOD                    | FFmpeg live encoder           |
| Pengendali   | Timeline server                 | Timeline siaran               |
| Seek         | Bisa dikontrol host             | Terbatas atau tidak tersedia  |
| Latensi      | Tidak ada latency siaran bawaan | Ada latency siaran            |
| CDN          | VOD HLS                         | Live HLS / LL-HLS             |
| WebRTC       | Tidak diperlukan                | Opsional untuk latensi rendah |
| Biaya server | Relatif rendah                  | Lebih tinggi                  |

Untuk Live HLS, keterlambatan playback dapat mencapai beberapa detik sampai puluhan detik, tergantung konfigurasi dan player. WebRTC dapat mengurangi latensi, tetapi membutuhkan arsitektur media yang lebih rumit, biasanya menggunakan SFU.

Bahkan pada broadcast live, buffering dan perbedaan latency player tetap bisa menyebabkan penonton berada pada posisi berbeda. Jadi, teknologi broadcast bukan jaminan sinkronisasi sempurna.

Saya menyarankan Watch Party Mode sebagai fitur utama dan Broadcast Mode sebagai modul tahap berikutnya, tanpa memaksakan keduanya pada implementasi awal.

# 13. Master Prompt — Bangun NobarSync 2.0 End-to-End

Berikut prompt yang saya susun agar bisa Mas berikan kepada Codex, Claude Code, Cursor, atau coding agent lain yang dapat membaca repository, membuat file, menjalankan terminal, dan menguji aplikasi.

Prompt ini tidak hanya meminta arsitektur atau rancangan. Instruksinya menuntut implementasi, integrasi, testing, deployment, serta bukti bahwa alur aplikasi benar-benar bekerja.

Implementation Prompt

&#x20;Salin prompt

Prompt lengkap untuk coding agent. Tombol salin memuat seluruh instruksi implementasi.

## 14. Rekomendasi akhir saya

Untuk kasus Mas yang sebelumnya memakai Go dan React, ada dua keputusan yang paling berpengaruh.

Pertama, jangan menganggap migrasi Go ke Elixir sebagai solusi utama sinkronisasi. Elixir dapat menjadi pilihan yang sangat bagus untuk membangun room, presence, dan komunikasi realtime, tetapi ketepatan nobar terutama ditentukan oleh desain timeline serta algoritma koreksi playback.

Kedua, pisahkan pengelolaan video dari sistem realtime. Dengan begitu, di kemudian hari Mas bisa mengganti R2 ke Cloudflare Stream, menambah server encoding, atau menggunakan beberapa Phoenix node tanpa harus menulis ulang keseluruhan aplikasi.

Saya akan memilih konfigurasi berikut sebagai versi pertama NobarSync 2.0 yang benar-benar layak digunakan:

| Komponen          | Keputusan                    |
| ----------------- | ---------------------------- |
| Frontend          | React + TypeScript + Vite    |
| Backend           | Elixir + Phoenix             |
| Realtime          | Phoenix Channels + Presence  |
| Playback          | HLS VOD + Smart Sync Engine  |
| Storage           | Cloudflare R2                |
| Encoding          | FFmpeg worker + Oban         |
| Database          | PostgreSQL                   |
| CDN private media | Cloudflare Worker            |
| Local testing     | Docker Compose + MinIO       |
| Testing           | ExUnit + Vitest + Playwright |
| Live broadcast    | Pengembangan berikutnya      |

Fokus implementasi paling kritis adalah menyelesaikan RoomCoordinator dan Smart Sync Engine terlebih dahulu dengan video pengujian. Jika kedua komponen tersebut berhasil, mengganti sumber video dari file lokal ke R2 tidak akan mengubah prinsip sinkronisasinya.

Itulah fondasi yang membuat NobarSync 2.0 jauh lebih baik daripada versi lama: bukan hanya bisa mengirim video ke banyak orang, tetapi mampu mempertahankan pengalaman menonton bersama meskipun kondisi jaringan para penonton berbeda-beda.