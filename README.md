# 🤖 FIKY STORE - WhatsApp Bot Auto Order & PPOB

![Version](https://img.shields.io/badge/Version-8.0-blue.svg)
![Node.js](https://img.shields.io/badge/Node.js-v20.x-green.svg)
![Platform](https://img.shields.io/badge/Platform-Ubuntu%20%2F%20Debian-orange.svg)

**FIKY STORE** adalah script Bot WhatsApp otomatis berbasis *Node.js* (Baileys) yang dirancang khusus untuk berjualan produk digital (PPOB, Top Up Game, Pulsa, dll) secara otomatis. Dilengkapi dengan **Panel Kontrol Interaktif**, bot ini sangat mudah dikelola langsung dari terminal VPS Anda tanpa perlu mengedit kode secara manual.

---

## ✨ Fitur Unggulan

- **🛒 Transaksi Otomatis (Digiflazz API):** Terintegrasi langsung dengan Digiflazz. Pesanan diproses otomatis saat member melakukan order.
- **👥 Sistem Saldo Member:** Member memiliki saldo masing-masing yang akan terpotong otomatis saat transaksi berhasil, dan kembali (refund) jika transaksi gagal.
- **🛠️ Panel Kontrol Interaktif:** Menu Bash (CUI) yang memudahkan Anda menambah produk, mengatur saldo, hingga merestart bot hanya dengan mengetik angka.
- **💾 Auto-Backup Telegram:** Tidak perlu takut kehilangan data (database saldo, produk, config)! Sistem akan mengirim file *backup* ke Telegram Anda secara berkala.
- **🚀 Berjalan 24/7 (PM2):** Bot berjalan dengan aman di latar belakang VPS menggunakan proses manajer PM2.
- **📢 Fitur Broadcast:** Kirim informasi atau promo ke seluruh member terdaftar hanya dengan satu klik.

---

## ⚡ Cara Cepat Instalasi (1-Click Install)

Jika Anda sudah memiliki VPS (Disarankan: **Ubuntu 20.04 / 22.04**), Anda bisa menginstal seluruh sistem bot, *library*, dan dependensinya hanya dengan satu baris perintah.

*(Ganti URL di bawah dengan link raw GitHub/Hosting file `install.sh` Anda jika sudah di-upload. Jika belum, gunakan cara manual di bawahnya)*.

```bash
apt update && apt install wget -y && wget -qO install.sh https://raw.githubusercontent.com/fikystorez/Bot-WhatsApp-orderkuota/main/install.sh && chmod +x install.sh && ./install.sh
