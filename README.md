# AppForge

CLI Bash untuk mengelola lifecycle aplikasi Node.js berbasis Docker di VM aplikasi. Artifact yang sudah jadi masuk, container jalan keluar — tanpa Nginx, tanpa SSL, tanpa Git pull di server.

## Daftar isi

- [Apa itu AppForge?](#apa-itu-appforge)
- [Cara kerja](#cara-kerja)
- [Fitur](#fitur)
- [Yang bukan tanggung jawab AppForge](#yang-bukan-tanggung-jawab-appforge)
- [Persyaratan](#persyaratan)
- [Instalasi](#instalasi)
- [Struktur direktori](#struktur-direktori)
- [Konfigurasi](#konfigurasi)
- [Template runtime](#template-runtime)
- [Setup awal server baru](#setup-awal-server-baru)
- [Menambah app ke server yang sudah jalan](#menambah-app-ke-server-yang-sudah-jalan)
- [Update dan rollback](#update-dan-rollback)
- [Referensi perintah](#referensi-perintah)
- [Menu interaktif](#menu-interaktif)
- [Status dan health check](#status-dan-health-check)
- [Troubleshooting](#troubleshooting)
- [Keamanan](#keamanan)
- [Prinsip desain](#prinsip-desain)
- [Roadmap](#roadmap)

## Apa itu AppForge?

AppForge adalah tool provisioning dan lifecycle manager untuk aplikasi Node.js (Next.js dan Node generik) yang berjalan sebagai container Docker di satu VM aplikasi.

Skenario tipikalnya:

1. Developer atau CI membangun aplikasi di luar server (laptop / CI).
2. Hasil build (artifact jadi) disalin ke `apps/<app-id>/` di VM aplikasi via `scp`/`rsync`.
3. AppForge memvalidasi config, men-generate `Dockerfile` + `docker-compose.yml` dari template, lalu build image dan menjalankan container.
4. VM reverse proxy (terpisah, di luar tanggung jawab AppForge) meneruskan trafik HTTP ke `IP-VM-APLIKASI:APP_PORT`.

Satu VM bisa menampung banyak aplikasi, masing-masing dengan port sendiri:

```text
Internet
   |
   v
+---------------------------+
| VM Reverse Proxy          |
| Nginx / SSL / Domain      |
+-------------+-------------+
              |
              | HTTP :APP_PORT
              v
+---------------------------+
| VM Application            |
|                           |
| AppForge + Docker         |
|   Tawani     :3101        |
|   HanQuran   :3102        |
|   HanSholat  :3103        |
+---------------------------+
```

AppForge bukan panel web, bukan CI/CD server, dan bukan reverse proxy. Ia adalah CLI yang dijalankan langsung di VM aplikasi, bisa lewat menu interaktif maupun one-shot command untuk automation.

## Cara kerja

Sumber kebenaran tunggal (source of truth) adalah file config per aplikasi di `config/apps/*.env`. File Docker di `generated/` selalu diturunkan dari config tersebut — jangan edit manual, karena akan tertimpa saat regenerate.

```text
config/apps/tawani.env
        |
        v  (render template)
templates/nextjs/
        |
        v
generated/tawani/
  ├── Dockerfile
  ├── docker-compose.yml
  └── app.env
        |
        v  (docker compose build + up)
Container appforge-tawani :3101
```

Alur deploy artifact:

```text
Developer / CI
      |
      | build (npm run build, dsb — di LUAR AppForge)
      v
Prebuilt Artifact
      |
      | scp / rsync
      v
apps/<app-id>/            (wajib ada package.json)
      |
      | ./appforge.sh deploy <app-id>
      v
Docker Image -> Container :APP_PORT
```

Contoh deploy:

```bash
# di laptop/CI: build dulu sampai jadi
scp -r tawani-build/* deploy@server:/opt/appforge/apps/tawani/

# di server:
cd /opt/appforge
./appforge.sh deploy tawani
```

## Fitur

- **Lifecycle lengkap per app:** create, start, stop, restart, deploy, rebuild, logs, shell, status, config, remove.
- **Dua mode operasi:** menu interaktif untuk operator + CLI one-shot untuk scripting/automation/SSH remote.
- **Config per app (`.env`):** `APP_ID`, `APP_TYPE`, `NODE_VERSION`, `APP_PORT` manual, `INTERNAL_PORT` opsional, plus variabel bebas (mis. `DATABASE_URL`) yang otomatis diteruskan ke container.
- **Template runtime:** `nextjs` dan `node` bawaan; tambah tipe baru cukup dengan folder di `templates/` tanpa mengubah core.
- **Generate Docker deterministik:** `Dockerfile` + `docker-compose.yml` + `app.env` selalu bisa di-regenerate dari config.
- **Validasi berlapis:** app-id, tipe, versi Node, port (format + tabrakan antar app), keberadaan artifact.
- **Health check dasar:** status container Docker + probe HTTP ke `http://127.0.0.1:APP_PORT` (butuh `curl`/`wget`, kalau tidak ada status HTTP jadi `UNKNOWN` tapi status Docker tetap tampil).
- **Init Setup submenu:** setup wizard langkah demi langkah, `doctor` preflight check, dan panduan operasional.
- **Operasi destruktif selalu konfirmasi:** `remove`, `image prune`, `builder prune` tidak pernah jalan diam-diam.
- **Idempotent:** menjalankan `start` dua kali tidak membuat container ganda atau state rusak.

## Yang bukan tanggung jawab AppForge

Agar ekspektasi jelas, ini daftar yang **sengaja tidak** dikerjakan AppForge:

- Nginx / reverse proxy / routing domain
- SSL / Certbot / DNS / Cloudflare
- Kubernetes / Docker Swarm
- Alokasi port otomatis (port ditentukan manual via `APP_PORT`)
- Web dashboard, database provisioning, monitoring eksternal, agregasi log
- CI/CD server, backup otomatis, konfigurasi firewall otomatis

Hal di atas adalah urusan infrastruktur di luar AppForge dan bisa jadi tool/fitur terpisah di masa depan.

## Persyaratan

- Linux (teruji di Ubuntu; keluarga RHEL seperti Rocky/Alma/RHEL/CentOS/Fedora didukung dengan catatan SELinux di bawah).
- Bash 4+.
- Docker Engine + plugin Docker Compose v2 (`docker compose version` harus jalan).
- `curl` atau `wget` untuk health check HTTP (opsional tapi disarankan).
- Akses ke Docker daemon: user harus bisa `docker info` (biasanya via grup `docker`) atau jalankan sebagai root.

Cek semuanya sekaligus dengan:

```bash
./appforge.sh doctor
```

## Instalasi

```bash
# 1. salin ke server, mis. /opt/appforge
scp -r appforge/ deploy@server:/opt/appforge

# 2. di server
ssh deploy@server
cd /opt/appforge
chmod +x appforge.sh
./appforge.sh setup        # buka submenu Init Setup
```

`./appforge.sh setup` membuka submenu berisi wizard, doctor, dan panduan. Untuk langsung ke wizard:

```bash
./appforge.sh setup wizard
```

Perbaikan permission yang paling umum (tool juga akan menyarankannya saat gagal):

```bash
sudo usermod -aG docker <user>   # lalu: newgrp docker (atau logout/login)
sudo chown -R <user>:<user> /opt/appforge
```

## Struktur direktori

```text
appforge/
├── appforge.sh            # entry point / router (tipis, bukan monolit)
├── lib/
│   ├── ui.sh              # warna, log, prompt, confirm, pause
│   ├── config.sh          # load/validasi config, parsing .env aman, artifact check
│   ├── docker.sh          # generate Dockerfile/compose, wrapper compose
│   ├── health.sh          # health container + HTTP
│   ├── system.sh          # info sistem, Docker status, cleanup
│   ├── app.sh             # lifecycle: create/start/stop/deploy/dsb.
│   └── setup.sh           # setup wizard, doctor, panduan operasional
├── templates/
│   ├── nextjs/            # Dockerfile + docker-compose.yml untuk Next.js
│   └── node/              # Dockerfile + docker-compose.yml untuk Node generik
├── config/
│   ├── defaults.env       # nilai default (NODE_ENV, INTERNAL_PORT)
│   └── apps/
│       ├── tawani.env
│       ├── hanquran.env
│       └── hansholat.env
├── generated/             # hasil generate (JANGAN edit manual, di-gitignore)
│   └── <app-id>/
│       ├── Dockerfile
│       ├── docker-compose.yml
│       └── app.env
└── apps/                  # artifact prebuilt per app (di-gitignore kecuali .gitkeep)
    └── <app-id>/
        ├── package.json   # wajib ada
        └── ...            # hasil build (.next/, public/, dist/, dsb.)
```

Penamaan konsisten: `APP_ID=tawani` berarti config `config/apps/tawani.env`, artifact `apps/tawani/`, hasil generate `generated/tawani/`, container `appforge-tawani`, compose project `tawani`.

## Konfigurasi

Contoh `config/apps/tawani.env`:

```env
APP_ID=tawani
APP_NAME=Tawani

APP_TYPE=nextjs
NODE_VERSION=22

APP_PORT=3101
INTERNAL_PORT=3000

NODE_ENV=production
```

| Variabel | Wajib | Keterangan |
|---|---|---|
| `APP_ID` | Ya | Huruf kecil, angka, strip (`^[a-z0-9][a-z0-9-]*$`). Harus sama dengan nama file. |
| `APP_NAME` | Ya | Nama tampilan untuk status/menu. |
| `APP_TYPE` | Ya | `nextjs` atau `node`. Menentukan template yang dipakai. |
| `NODE_VERSION` | Ya | Angka mayor image Node, mis. `22` → `node:22-alpine`. |
| `APP_PORT` | Ya | Port eksternal di VM (1–65535). Ditentukan manual, dicek tabrakan antar app. |
| `INTERNAL_PORT` | Tidak | Port di dalam container, default `3000`. |
| `NODE_ENV` | Ya | Biasanya `production`. Ada default di `config/defaults.env`. |

**Variabel custom:** baris `KEY=value` lain di `.env` (mis. `DATABASE_URL`, `API_KEY`) otomatis diteruskan ke container lewat `generated/<id>/app.env`. Kunci harus pola `^[A-Za-z_][A-Za-z0-9_]*$`, nilai dibaca literal (tidak dievaluasi sebagai shell, jadi aman dari command injection).

**Secret masking:** saat `config view`, nilai untuk kunci yang mengandung `PASSWORD`, `SECRET`, `KEY`, atau `TOKEN` ditampilkan sebagai `********`. Ini masking tampilan saja, bukan enkripsi.

**Validasi port:** selain format angka 1–65535, AppForge menolak port yang sudah dipakai app lain. Contoh error:

```text
[ERROR] Port 3101 is already in use by app 'tawani'.
```

## Template runtime

### Next.js (`APP_TYPE=nextjs`)

```text
node:22-alpine -> npm ci -> copy source -> npm run build -> npm run start
```

Mapping default: `VM:APP_PORT -> container:INTERNAL_PORT` (mis. `:3101 -> :3000`).

### Node generik (`APP_TYPE=node`)

```text
node:22-alpine -> npm ci --omit=dev -> copy source -> npm start
```

### Menambah tipe baru

Buat folder `templates/<tipe>/` berisi `Dockerfile` dan `docker-compose.yml` dengan placeholder `${VAR}` (mis. `${NODE_VERSION}`, `${APP_PORT}`, `${INTERNAL_PORT}`, `${BUILD_CONTEXT}`, `${DOCKERFILE_PATH}`, `${IMAGE_NAME}`, `${CONTAINER_NAME}`, `${NODE_ENV}`). Tidak perlu mengubah `lib/` — cukup pakai `APP_TYPE=<tipe>` di config. Calon tipe berikutnya: `nestjs`, `express`, `static`.

Catatan template saat ini memakai single-stage build (`npm ci` + copy source + build di dalam image). Ini disengaja untuk MVP agar flow mudah dipahami; multi-stage bisa ditambahkan nanti tanpa mengubah CLI.

## Setup awal server baru

Jalankan di server (butuh TTY interaktif):

```bash
cd /opt/appforge
./appforge.sh setup wizard
```

Wizard berjalan 5 langkah: (1) cek Docker Engine + Compose plugin dengan petunjuk install per distro Ubuntu vs RHEL, (2) cek akses daemon dengan opsi auto-fix `usermod -aG docker` pakai konfirmasi, (3) cek writability `config/`, `generated/`, `apps/` dengan opsi auto-fix `chown`, (4) cek `curl`/`wget`, (5) verifikasi akhir via `doctor`.

Kapan saja setelah itu:

```bash
./appforge.sh doctor   # read-only, aman dijalankan berulang
```

`doctor` memeriksa 6 hal: binary Docker, Compose v2, akses daemon (membedakan "permission denied" vs "daemon mati"), `curl`/`wget`, writability direktori, dan status SELinux (keluarga RHEL).

## Menambah app ke server yang sudah jalan

App yang sudah `RUNNING` tidak tersentuh oleh prosedur ini. Panduan interaktif lengkap juga tersedia via menu `Init Setup > Guide` atau:

```bash
./appforge.sh guide add-app
```

Versi singkat:

```bash
cd /opt/appforge
./appforge.sh doctor          # harus: all critical checks passed
./appforge.sh list            # pilih APP_PORT yang belum dipakai, mis. 3104
./appforge.sh create myapp    # jawab prompt: nama, tipe, versi node, port

# dari laptop/CI (sudah di-build dulu), salin artifact:
scp -r myapp-build/* deploy@server:/opt/appforge/apps/myapp/

# di server: samakan ownership + sanity check
sudo chown -R $(id -un):$(id -un) apps/myapp
ls apps/myapp/package.json

# deploy
./appforge.sh deploy myapp
# ekspektasi: Deployment successful. Container: RUNNING
```

Verifikasi dari VM reverse proxy, lalu arahkan Nginx ke sana:

```bash
curl http://<ip-vm-aplikasi>:<APP_PORT>/
```

## Update dan rollback

Update = timpa artifact + deploy ulang. Tidak ada `git pull` di server menurut desain.

```bash
scp -r myapp-build/* deploy@server:/opt/appforge/apps/myapp/
ssh deploy@server "cd /opt/appforge && ./appforge.sh deploy myapp"
```

Progress deploy selalu 5 tahap:

```text
[1/5] Validating config...
[2/5] Validating artifact...
[3/5] Generating Docker configuration...
[4/5] Building Docker image...
[5/5] Starting container and health checking...

Deployment successful.
```

Jika deploy bermasalah:

```bash
./appforge.sh logs myapp follow   # lihat log
./appforge.sh rebuild myapp       # build ulang bersih (no-cache) + start
./appforge.sh status myapp        # cek container, port, health, CPU/mem
```

Image sebelumnya masih ada secara lokal di Docker, jadi `rebuild`/`deploy` ulang dari artifact lama adalah jalan rollback tercepat.

Menghapus app (konfirmasi dulu, artifact dipertahankan kecuali `--purge`):

```bash
./appforge.sh remove myapp                 # tanya konfirmasi, hapus container+generated+config
./appforge.sh remove myapp --force         # tanpa konfirmasi
./appforge.sh remove myapp --force --purge # ikut hapus apps/myapp/
```

## Referensi perintah

Semua perintah bisa jalan headless (cocok untuk SSH/automation). Tanpa argumen, `./appforge.sh` membuka menu interaktif.

| Perintah | Fungsi |
|---|---|
| `list` | Tabel app + status Docker live (`RUNNING`/`STOPPED`/`NOT_CREATED`). |
| `create [app-id]` | Buat config, scaffold `apps/<id>/`, generate Docker. Interaktif bila argumen kosong. Tidak pernah menimpa app existing. |
| `start <id>` | Validasi + generate bila perlu, lalu `compose up -d`. |
| `stop <id>` | `compose stop` (tidak hapus container/image). Fallback stop langsung bila file compose hilang. |
| `restart <id>` | `compose restart`; fallback generate+start bila file compose hilang. |
| `deploy <id>` | Pipeline penuh: validasi config → validasi artifact → generate → build → `up -d` → health check. |
| `rebuild <id>` | `build --no-cache` + `up -d`. Berbeda dari deploy (tanpa validasi artifact ulang). |
| `logs <id> [follow\|100\|500]` | `compose logs -f --tail=100` / `--tail=100` / `--tail=500`. Tanpa argumen tampilkan submenu. |
| `shell <id>` | `exec app sh` ke container. Menolak dengan pesan jelas bila container tidak running. |
| `status <id>` | Container, image, port eksternal/internal, health container+HTTP, CPU/mem/uptime. |
| `config <id> [view\|edit\|validate\|regenerate]` | Submenu config; `view` masking secret, `edit` pakai `$EDITOR`, `validate` cek required+format+tabrakan port, `regenerate` render ulang Docker. |
| `remove <id> [--force] [--purge]` | Konfirmasi, `compose down`, hapus generated + config. Artifact `apps/<id>/` hanya ikut terhapus dengan `--purge`. |
| `system` | Submenu: Docker status, disk usage, clean unused images, clean build cache (semua prune konfirmasi dulu), system info. |
| `setup [wizard]` | Submenu Init Setup (wizard, doctor, panduan). `setup wizard` langsung ke wizard. |
| `doctor` | Preflight check read-only, aman kapan saja. Return non-zero bila ada yang gagal (berguna untuk script). |
| `guide [add-app]` | Submenu panduan; `guide add-app` langsung cetak panduan tambah app. |
| `help` | Tampilkan bantuan. |

Contoh non-interaktif (urutan deploy pertama realistis):

```bash
./appforge.sh doctor
./appforge.sh create shop "Shop" nextjs 22 3104 3000
./appforge.sh config shop validate
ls apps/shop/package.json
./appforge.sh deploy shop
./appforge.sh status shop
```

## Menu interaktif

Menu utama (jalankan `./appforge.sh`):

```text
╔════════════════════════════════════════════╗
║              AppForge Launcher             ║
╠════════════════════════════════════════════╣
║                                            ║
║  1. List Apps                              ║
║  2. Create App                             ║
║  3. Start App                              ║
║  4. Stop App                               ║
║  5. Restart App                            ║
║  6. Deploy / Update                        ║
║  7. Rebuild                                ║
║  8. Logs                                   ║
║  9. Shell                                  ║
║ 10. Status / Health                        ║
║ 11. App Config                             ║
║ 12. Remove App                             ║
║                                            ║
║ 13. System                                 ║
║ 14. Init Setup                             ║
║                                            ║
║  0. Exit                                   ║
║                                            ║
╚════════════════════════════════════════════╝
```

Submenu terkait:

```text
Init Setup
 1. Setup Wizard (first-time server setup)
 2. Doctor (preflight checks)
 3. Guide: Add App to live server
 4. Back
```

```text
System
 1. Docker Status
 2. Docker Disk Usage
 3. Clean Unused Images
 4. Clean Build Cache
 5. System Info
 6. Back
```

```text
App Config: <id>
 1. View Config
 2. Edit Config
 3. Validate Config
 4. Regenerate Docker Files
 5. Back
```

```text
Logs for '<id>':
 1. Follow logs
 2. Last 100 lines
 3. Last 500 lines
 4. Back
```

Menu interaktif membutuhkan TTY (tidak bisa di-pipe penuh dari script). Untuk automation selalu pakai mode CLI one-shot di atas.

## Status dan health check

Contoh `status`:

```text
Tawani

Docker:
  Container       RUNNING
  Image           appforge-tawani:latest

Application:
  Port            3101
  Internal Port   3000

Health:
  Container       OK
  HTTP            OK

Runtime:
  CPU             1.2%
  Memory          184 MB
  Uptime          Up 2 hours
```

`Container` berasal dari state Docker aktual (bukan tebakan dari file). `HTTP` adalah probe ke `http://127.0.0.1:APP_PORT`; bila app belum respons atau `curl`/`wget` tidak ada, field ini `FAIL`/`UNKNOWN` tetapi info Docker tetap ditampilkan.

## Troubleshooting

| Gejala | Penyebab umum | Perintah / solusi |
|---|---|---|
| `Docker is not installed` | Docker belum terpasang / tidak di PATH | Ikuti petunjuk per distro dari `./appforge.sh setup wizard`. |
| `Docker Compose v2 is not available` | Plugin compose belum terpasang | Ubuntu: `sudo apt-get install -y docker-compose-plugin`; RHEL: `sudo dnf install -y docker-compose-plugin`. |
| `Permission denied on Docker socket` | User belum masuk grup `docker` | `sudo usermod -aG docker <user>` lalu `newgrp docker` atau logout/login. |
| `Docker daemon is not reachable` | `dockerd` mati | `systemctl status docker`, `sudo systemctl enable --now docker`. |
| `not writable: ...` (doctor) | Ownership campur (scp sebagai root, jalan sebagai user) | `sudo chown -R <user>:<user> /opt/appforge`, termasuk `apps/<id>` setelah scp. |
| `Port XXXX is already in use` | `APP_PORT` dipakai app lain | `./appforge.sh list`, pilih port bebas, edit config + regenerate. |
| `artifact directory missing` / `package.json not found` | Artifact belum disalin / salah path | `ls apps/<id>/package.json`; salin ulang hasil build. |
| `generated docker-compose.yml missing` | Folder `generated/` terhapus manual | `./appforge.sh config <id> regenerate` (atau deploy ulang). |
| `container is not running` saat `shell` | App belum start / crash | `./appforge.sh status <id>`, `./appforge.sh logs <id> follow`. |
| HTTP `FAIL` tapi container `RUNNING` | App listen di port/interface berbeda, atau butuh env | Cek `INTERNAL_PORT`, pastikan app listen `0.0.0.0`, cek `generated/<id>/app.env`. |
| Error SELinux (RHEL) | Konteks file / policy | Cek `getenforce` + audit log; build membaca `apps/<id>/` via daemon, mount volume di masa depan mungkin butuh label `:z`/konteks. |

Error selalu menyebut app terkait, mengembalikan exit code non-zero di mode CLI, dan tidak menumpahkan stack trace Bash mentah sebagai satu-satunya info.

## Keamanan

- File `.env` di-parse sebagai pasangan `KEY=value` literal — tidak pernah di-`source` sebagai shell, jadi injeksi `$(...)`/backtick tidak dieksekusi.
- App-id divalidasi ketat (`^[a-z0-9][a-z0-9-]*$`) sebelum dipakai membangun path, menutup path traversal (`../x`) di semua command.
- Secret hanya di-masking saat tampil (`view`); jangan mengandalkan ini sebagai enkripsi — perlakukan `config/apps/*.env` seperti kredensial: batasi akses baca di server.
- Grup `docker` setara root secara praktis (bisa mount host). Berikan hanya ke user operator yang dipercaya.
- Operasi destruktif (`remove`, `prune`) selalu minta konfirmasi eksplisit.

## Prinsip desain

- **Simple:** tanpa abstraksi berlebihan untuk MVP; satu fungsi Bash per operasi.
- **Modular:** `appforge.sh` hanya router; logika tinggal di `lib/` per concern (`config`, `docker`, `health`, `system`, `ui`, `app lifecycle`, `setup`).
- **Idempotent:** command aman dijalankan ulang tanpa state rusak.
- **Explicit:** tidak ada operasi destruktif diam-diam.
- **Predictable:** `.env` adalah sumber perilaku; `generated/` selalu bisa dibangun ulang.
- **Extensible:** tipe app baru = folder template baru, tanpa bedah core lifecycle.

## Roadmap

Ide yang secara sadar di luar MVP tapi cocok sebagai lanjutan: `nestjs`/`express`/`static` profile, multi-stage Dockerfile, `INTERNAL_PORT` per-service yang lebih kaya, env per-environment (`staging`/`production`), panduan firewall/UFW/firewalld per distro, backup/restore volume, dan integrasi CI (contoh workflow upload artifact + trigger deploy remote).
