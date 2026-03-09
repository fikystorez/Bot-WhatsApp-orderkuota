#!/bin/bash

# ==========================================
# 1. BIKIN SHORTCUT 'BOT' OTOMATIS DI VPS
# ==========================================
if [ ! -f "/usr/bin/bot" ]; then
    if [ -f "/usr/bin/menu" ]; then sudo rm -f /usr/bin/menu; fi
    echo -e '#!/bin/bash\ncd "'$(pwd)'"\n./install.sh' | sudo tee /usr/bin/bot > /dev/null
    sudo chmod +x /usr/bin/bot
fi

# ==========================================
# 2. FUNGSI UNTUK MEMBUAT FILE INDEX.JS
# ==========================================
generate_bot_script() {
    echo "Membuat file index.js..."
    cat << 'EOF' > index.js
const { default: makeWASocket, useMultiFileAuthState, DisconnectReason, Browsers, jidNormalizedUser, fetchLatestBaileysVersion } = require('@whiskeysockets/baileys');
const { Boom } = require('@hapi/boom');
const fs = require('fs');
const pino = require('pino');
const express = require('express');
const bodyParser = require('body-parser');
const { exec } = require('child_process');
const axios = require('axios'); 
const crypto = require('crypto'); 

const app = express();
app.use(bodyParser.json());

const configFile = './config.json';
const dbFile = './database.json';
const produkFile = './produk.json';
const trxFile = './trx.json';

const loadJSON = (file) => fs.existsSync(file) ? JSON.parse(fs.readFileSync(file)) : {};
const saveJSON = (file, data) => fs.writeFileSync(file, JSON.stringify(data, null, 2));

let configAwal = loadJSON(configFile);
configAwal.botName = configAwal.botName || "FIKY STORE";
configAwal.botNumber = configAwal.botNumber || "";
configAwal.teleToken = configAwal.teleToken || "";
configAwal.teleChatId = configAwal.teleChatId || "";
configAwal.autoBackup = configAwal.autoBackup || false;
saveJSON(configFile, configAwal);

if (!fs.existsSync(dbFile)) saveJSON(dbFile, {});
if (!fs.existsSync(produkFile)) saveJSON(produkFile, {});
if (!fs.existsSync(trxFile)) saveJSON(trxFile, {});

let pairingRequested = false; 

// FUNGSI AUTO BACKUP KE TELEGRAM 
function doBackupAndSend() {
    let cfg = loadJSON(configFile);
    if (!cfg.teleToken || !cfg.teleChatId) return;
    
    console.log("⏳ Memulai proses Auto-Backup ke Telegram...");
    exec(`rm -f backup.zip && zip backup.zip config.json database.json trx.json index.js install.sh package-lock.json package.json produk.json 2>/dev/null`, (err) => {
        if (!err) {
            let caption = `📦 *Auto-Backup FIKY STORE*\n⏰ Waktu: ${new Date().toLocaleString('id-ID')}`;
            exec(`curl -s -F chat_id="${cfg.teleChatId}" -F document=@"backup.zip" -F caption="${caption}" https://api.telegram.org/bot${cfg.teleToken}/sendDocument`, (err2) => {
                if (!err2) console.log("✅ Auto-Backup berhasil dikirim ke Telegram!");
                exec(`rm -f backup.zip`); 
            });
        }
    });
}

if (configAwal.autoBackup) {
    setInterval(doBackupAndSend, 12 * 60 * 60 * 1000); 
}

async function startBot() {
    console.log("\n⏳ Sedang menyiapkan mesin bot...");
    const { state, saveCreds } = await useMultiFileAuthState('sesi_bot');
    let config = loadJSON(configFile);
    
    console.log("⏳ Mengambil konfigurasi keamanan WhatsApp terbaru...");
    const { version, isLatest } = await fetchLatestBaileysVersion();
    console.log(`📡 Menghubungkan ke WA Web v${version.join('.')} (Stabil: ${isLatest})`);
    
    const sock = makeWASocket({
        version,
        auth: state,
        logger: pino({ level: 'silent' }),
        browser: Browsers.ubuntu('Chrome'),
        printQRInTerminal: false,
        syncFullHistory: false
    });

    if (!sock.authState.creds.registered && !pairingRequested) {
        pairingRequested = true;
        let phoneNumber = config.botNumber;
        
        if (!phoneNumber) {
            console.log('\n❌ NOMOR BOT BELUM DIATUR! Keluar...');
            process.exit(0);
        }

        setTimeout(async () => {
            try {
                let formattedNumber = phoneNumber.replace(/[^0-9]/g, '');
                const code = await sock.requestPairingCode(formattedNumber);
                console.log(`\n=======================================================`);
                console.log(`🔑 KODE TAUTAN ANDA :  ${code}  `);
                console.log(`=======================================================`);
                console.log('👉 Buka WA di HP -> Perangkat Tertaut -> Tautkan dengan nomor telepon saja.');
                console.log('⚠️ SEGERA MASUKKAN KODENYA KE HP ANDA!\n');
            } catch (error) {
                pairingRequested = false; 
            }
        }, 8000); 
    }

    sock.ev.on('creds.update', saveCreds);

    sock.ev.on('connection.update', (update) => {
        const { connection, lastDisconnect } = update;
        if (connection === 'close') {
            let reason = new Boom(lastDisconnect?.error)?.output?.statusCode;
            if (reason === DisconnectReason.loggedOut) {
                process.exit(0);
            } else {
                pairingRequested = false;
                setTimeout(startBot, 4000);
            }
        } else if (connection === 'open') {
            console.log('\n✅ BOT WHATSAPP BERHASIL TERHUBUNG DENGAN AMAN!');
        }
    });

    // ==========================================
    // AUTO-POLLING CEK STATUS PENDING DIGIFLAZZ
    // ==========================================
    setInterval(async () => {
        let trxs = loadJSON(trxFile);
        let keys = Object.keys(trxs);
        if (keys.length === 0) return;

        let cfg = loadJSON(configFile);
        let userAPI = (cfg.digiflazzUsername || '').trim();
        let keyAPI = (cfg.digiflazzApiKey || '').trim();
        if (!userAPI || !keyAPI) return;

        for (let ref of keys) {
            let trx = trxs[ref];
            let signCheck = crypto.createHash('md5').update(userAPI + keyAPI + ref).digest('hex');

            try {
                const cekRes = await axios.post('https://api.digiflazz.com/v1/transaction', {
                    username: userAPI,
                    buyer_sku_code: trx.sku,
                    customer_no: trx.tujuan,
                    ref_id: ref,
                    sign: signCheck
                });

                const resData = cekRes.data.data;
                const statusUpdate = resData.status;
                const sn = resData.sn || '-';

                if (statusUpdate === 'Sukses') {
                    let msg = `✅ *UPDATE STATUS: SUKSES*\n\n📦 Produk: ${trx.nama}\n📱 Tujuan: ${trx.tujuan}\n🔖 Ref: ${ref}\n🔑 SN/Catatan: ${sn}`;
                    await sock.sendMessage(trx.jid, { text: msg });
                    delete trxs[ref];
                    saveJSON(trxFile, trxs);
                } else if (statusUpdate === 'Gagal') {
                    let db = loadJSON(dbFile);
                    let senderNum = trx.jid.split('@')[0];
                    if (db[senderNum]) {
                        db[senderNum].saldo += trx.harga;
                        saveJSON(dbFile, db);
                    }
                    let msg = `❌ *UPDATE STATUS: GAGAL*\n\n📦 Produk: ${trx.nama}\n📱 Tujuan: ${trx.tujuan}\n🔖 Ref: ${ref}\nAlasan: ${resData.message}\n\n_💰 Saldo Rp ${trx.harga.toLocaleString('id-ID')} telah dikembalikan._`;
                    await sock.sendMessage(trx.jid, { text: msg });
                    delete trxs[ref];
                    saveJSON(trxFile, trxs);
                } else {
                    if (Date.now() - trx.tanggal > 24 * 60 * 60 * 1000) {
                        delete trxs[ref];
                        saveJSON(trxFile, trxs);
                    }
                }
            } catch (err) {}
            await new Promise(r => setTimeout(r, 2000)); 
        }
    }, 15000); 

    sock.ev.on('messages.upsert', async m => {
        try {
            const msg = m.messages[0];
            if (!msg.message || msg.key.fromMe) return;

            const from = msg.key.remoteJid;
            const senderJid = jidNormalizedUser(msg.key.participant || msg.key.remoteJid);
            const sender = senderJid.split('@')[0]; 
            
            const body = msg.message.conversation || msg.message.extendedTextMessage?.text || "";
            if (!body) return;
            
            const command = body.split(' ')[0].toLowerCase();
            
            let config = loadJSON(configFile);
            let namaBot = config.botName || "FIKY STORE";
            let db = loadJSON(dbFile);
            let produkDB = loadJSON(produkFile);

            if (!db[sender]) {
                db[sender] = { saldo: 0, tanggal_daftar: new Date().toLocaleDateString('id-ID'), jid: senderJid };
                saveJSON(dbFile, db);
            }

            if (command === '.menu') {
                await sock.sendMessage(from, { 
                    text: `👋 Selamat Datang di *${namaBot}* (v8)\n📌 *ID Member:* ${sender}\n\n1. *.saldo* (Cek saldo)\n2. *.order* [kode] [tujuan]\n3. *.harga* (Cek harga)\n\n_Ketik perintah di atas untuk menggunakan bot._`
                });
                return;
            }

            if (command === '.saldo') {
                await sock.sendMessage(from, { 
                    text: `💰 Saldo Anda saat ini: *Rp ${db[sender].saldo.toLocaleString('id-ID')}*` 
                });
                return;
            }

            if (command === '.harga') {
                let keys = Object.keys(produkDB);
                if (keys.length === 0) {
                    await sock.sendMessage(from, { text: `🛒 *Daftar Harga ${namaBot}*\n\nMaaf, belum ada produk yang tersedia saat ini.`});
                    return;
                }

                let textHarga = `🛒 *DAFTAR PRODUK ${namaBot}*\n\n`;
                keys.forEach((k, i) => {
                    textHarga += `*${i+1}. ${produkDB[k].nama}*\n`;
                    textHarga += `   Ketik: *.order ${k} tujuan*\n`;
                    textHarga += `   Harga: *Rp ${produkDB[k].harga.toLocaleString('id-ID')}*\n\n`;
                });
                textHarga += `_Contoh order: .order ${keys[0]} 08123456789_`;
                
                await sock.sendMessage(from, { text: textHarga.trim() });
                return;
            }

            if (command === '.order') {
                const args = body.split(' ').slice(1);
                
                if (args.length < 2) {
                    let contohKode = Object.keys(produkDB)[0] || 'E15GB';
                    return await sock.sendMessage(from, { text: `❌ *Format salah!*\n\nKetik: *.order [kode] [nomor_tujuan]*\nContoh: .order ${contohKode} 08123456789` });
                }

                const kodeProduk = args[0].toUpperCase();
                const tujuan = args[1];

                if (!produkDB[kodeProduk]) {
                    return await sock.sendMessage(from, { text: `❌ Kode produk *${kodeProduk}* tidak ditemukan.\nKetik *.harga* untuk melihat daftar kode produk yang tersedia.` });
                }

                const hargaProduk = produkDB[kodeProduk].harga;

                if (db[sender].saldo < hargaProduk) {
                    return await sock.sendMessage(from, { text: `❌ *Saldo tidak mencukupi!*\n\n💰 Saldo Anda: Rp ${db[sender].saldo.toLocaleString('id-ID')}\n🏷️ Harga Produk: Rp ${hargaProduk.toLocaleString('id-ID')}\n\nSilakan isi saldo terlebih dahulu.` });
                }

                let username = (config.digiflazzUsername || '').trim();
                let apiKey = (config.digiflazzApiKey || '').trim();

                if (!username || !apiKey) {
                    return await sock.sendMessage(from, { text: `❌ Sistem bermasalah: API Digiflazz belum dikonfigurasi oleh Admin.` });
                }

                let refId = 'FIKY-' + Date.now();
                let sign = crypto.createHash('md5').update(username + apiKey + refId).digest('hex');

                await sock.sendMessage(from, { text: `⏳ *Sedang memproses pesanan...*\n\n📦 Produk: ${produkDB[kodeProduk].nama}\n📱 Tujuan: ${tujuan}\n🔖 Ref: ${refId}` });

                try {
                    const response = await axios.post('https://api.digiflazz.com/v1/transaction', {
                        username: username,
                        buyer_sku_code: kodeProduk,
                        customer_no: tujuan,
                        ref_id: refId,
                        sign: sign
                    });

                    const resData = response.data.data;
                    const statusOrder = resData.status; 
                    const sn = resData.sn || '-';
                    const message = resData.message || '';

                    if (statusOrder === 'Gagal') {
                        await sock.sendMessage(from, { text: `❌ *Transaksi Gagal!*\nAlasan: ${message}\n\n_Saldo Anda tidak dipotong._` });
                    } else if (statusOrder === 'Pending') {
                        db[sender].saldo -= hargaProduk;
                        saveJSON(dbFile, db);

                        let trxs = loadJSON(trxFile);
                        trxs[refId] = { jid: from, sku: kodeProduk, tujuan: tujuan, harga: hargaProduk, nama: produkDB[kodeProduk].nama, tanggal: Date.now() };
                        saveJSON(trxFile, trxs);

                        let pesanPending = `⏳ *PESANAN SEDANG DIPROSES*\n\n`;
                        pesanPending += `📦 Produk: ${produkDB[kodeProduk].nama}\n`;
                        pesanPending += `📱 Tujuan: ${tujuan}\n`;
                        pesanPending += `🔖 Ref ID: ${refId}\n`;
                        pesanPending += `⚙️ Status: *Pending (Menunggu)*\n\n`;
                        pesanPending += `_Sistem akan menginformasikan kembali jika transaksi sukses atau gagal. Saldo sementara dipotong Rp ${hargaProduk.toLocaleString('id-ID')}._`;

                        await sock.sendMessage(from, { text: pesanPending });
                    } else {
                        db[sender].saldo -= hargaProduk;
                        saveJSON(dbFile, db);

                        let pesanSukses = `✅ *PESANAN BERHASIL DIPROSES*\n\n`;
                        pesanSukses += `📦 Produk: ${produkDB[kodeProduk].nama}\n`;
                        pesanSukses += `📱 Tujuan: ${tujuan}\n`;
                        pesanSukses += `🔖 Ref ID: ${refId}\n`;
                        pesanSukses += `⚙️ Status: *${statusOrder}*\n`;
                        pesanSukses += `🔑 SN/Catatan: ${sn}\n\n`;
                        pesanSukses += `💰 Sisa Saldo: Rp ${db[sender].saldo.toLocaleString('id-ID')}`;

                        await sock.sendMessage(from, { text: pesanSukses });
                    }

                } catch (error) {
                    let errMessage = error.response?.data?.data?.message || 'Terjadi kesalahan saat menghubungi server Digiflazz/API Down.';
                    await sock.sendMessage(from, { text: `❌ *Transaksi Gagal!*\nAlasan: ${errMessage}\n\n_Saldo Anda tidak dipotong._` });
                }
                return;
            }
        } catch (err) {
            console.error("Kesalahan sistem WhatsApp: ", err);
        }
    });

    if (global.broadcastInterval) clearInterval(global.broadcastInterval);
    global.broadcastInterval = setInterval(async () => {
        if (fs.existsSync('./broadcast.txt')) {
            let textBroadcast = fs.readFileSync('./broadcast.txt', 'utf-8');
            fs.unlinkSync('./broadcast.txt');

            if (textBroadcast.trim()) {
                let db = loadJSON(dbFile);
                let config = loadJSON(configFile);
                let namaBot = config.botName || "FIKY STORE";
                let members = Object.keys(db);
                for (let num of members) {
                    try {
                        let targetJid = db[num].jid || (num + '@s.whatsapp.net');
                        await sock.sendMessage(targetJid, { text: `📢 *INFORMASI ${namaBot}*\n\n${textBroadcast.trim()}` });
                        await new Promise(res => setTimeout(res, 3000));
                    } catch (err) {}
                }
            }
        }
    }, 5000);
}

if (require.main === module) {
    app.listen(3000, () => {
        console.log('🌐 Server Webhook siap.');
    }).on('error', (err) => {});
    startBot().catch(err => console.error(err));
}
EOF
}

# ==========================================
# 3. FUNGSI INSTALASI DEPENDENSI (MODE SENYAP)
# ==========================================
install_dependencies() {
    clear
    echo "==============================================="
    echo "      🚀 MENGINSTALL SISTEM BOT FIKY 🚀      "
    echo "==============================================="
    
    export DEBIAN_FRONTEND=noninteractive
    export NEEDRESTART_MODE=a
    export NEEDRESTART_SUSPEND=1

    sudo -E apt-get update
    sudo -E apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
    sudo -E apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" curl git wget nano zip unzip
    
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo -E apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" nodejs
    
    sudo npm install -g npm@11.11.0
    sudo npm install -g pm2
    
    generate_bot_script
    if [ ! -f "package.json" ]; then npm init -y; fi
    rm -rf node_modules package-lock.json
    npm install @whiskeysockets/baileys pino qrcode-terminal axios express body-parser
    
    echo "==============================================="
    echo " ✅ INSTALASI SELESAI! "
    echo "==============================================="
    read -p "Tekan Enter untuk kembali ke Menu Utama..."
}

# ==========================================
# 4. SUB-MENU TELEGRAM SETUP
# ==========================================
menu_telegram() {
    while true; do
        clear
        echo "==============================================="
        echo "            ⚙️ BOT TELEGRAM SETUP ⚙️           "
        echo "==============================================="
        echo "1. Change BOT API & CHATID"
        echo "2. Set Notifikasi Backup Otomatis (12 Jam)"
        echo "0. Kembali ke Menu Utama"
        echo "==============================================="
        read -p "Pilih menu [0-2]: " telechoice

        case $telechoice in
            1)
                echo "--- PENGATURAN BOT TELEGRAM ---"
                read -p "Masukkan Token Bot Telegram: " token
                read -p "Masukkan Chat ID Anda: " chatid
                node -e "
                    const fs = require('fs');
                    let config = fs.existsSync('config.json') ? JSON.parse(fs.readFileSync('config.json')) : {};
                    config.teleToken = '$token';
                    config.teleChatId = '$chatid';
                    fs.writeFileSync('config.json', JSON.stringify(config, null, 2));
                    console.log('\n✅ Data Telegram berhasil disimpan!');
                "
                read -p "Tekan Enter untuk kembali..."
                ;;
            2)
                echo "--- SET AUTO BACKUP ---"
                read -p "Aktifkan Auto-Backup ke Telegram setiap 12 Jam? (y/n): " set_auto
                if [ "$set_auto" == "y" ] || [ "$set_auto" == "Y" ]; then
                    status="true"
                    echo -e "\n✅ Auto-Backup DIAKTIFKAN!"
                else
                    status="false"
                    echo -e "\n❌ Auto-Backup DIMATIKAN!"
                fi
                node -e "
                    const fs = require('fs');
                    let config = fs.existsSync('config.json') ? JSON.parse(fs.readFileSync('config.json')) : {};
                    config.autoBackup = $status;
                    fs.writeFileSync('config.json', JSON.stringify(config, null, 2));
                "
                echo "⚠️ Silakan restart bot (Menu 4 lalu 3) agar fitur aktif."
                read -p "Tekan Enter untuk kembali..."
                ;;
            0) break ;;
            *) echo "❌ Pilihan tidak valid!"; sleep 1 ;;
        esac
    done
}

# ==========================================
# 5. SUB-MENU BACKUP & RESTORE
# ==========================================
menu_backup() {
    while true; do
        clear
        echo "==============================================="
        echo "              💾 BACKUP & RESTORE 💾            "
        echo "==============================================="
        echo "1. Backup Sekarang (Kirim file ZIP ke Telegram)"
        echo "2. Restore Database & Bot dari Direct Link"
        echo "0. Kembali ke Menu Utama"
        echo "==============================================="
        read -p "Pilih menu [0-2]: " backchoice

        case $backchoice in
            1)
                echo -e "\n⏳ Sedang memproses arsip backup. Mohon tunggu..."
                if ! command -v zip &> /dev/null; then sudo apt install zip -y; fi
                
                rm -f backup.zip
                zip backup.zip config.json database.json trx.json index.js install.sh package-lock.json package.json produk.json 2>/dev/null
                echo "✅ File backup.zip berhasil dikompresi!"
                
                node -e "
                    const fs = require('fs');
                    const { exec } = require('child_process');
                    let config = fs.existsSync('config.json') ? JSON.parse(fs.readFileSync('config.json')) : {};
                    if(config.teleToken && config.teleChatId) {
                        console.log('⏳ Sedang mengirim ke Telegram Anda...');
                        let cmd = \`curl -s -F chat_id=\"\${config.teleChatId}\" -F document=@\"backup.zip\" -F caption=\"📦 Manual Backup FIKY STORE\" https://api.telegram.org/bot\${config.teleToken}/sendDocument\`;
                        exec(cmd, (err) => {
                            if(err) console.log('❌ Gagal mengirim ke Telegram.');
                            else console.log('✅ File Backup berhasil mendarat di Telegram Anda!');
                        });
                    } else {
                        console.log('⚠️ Token/Chat ID Telegram belum diisi.');
                    }
                "
                read -p "Tekan Enter untuk kembali..."
                ;;
            2)
                echo -e "\n⚠️ PERHATIAN: Restore akan MENIMPA seluruh file bot Anda!"
                read -p "Apakah Anda yakin? (y/n): " yakin
                if [ "$yakin" == "y" ] || [ "$yakin" == "Y" ]; then
                    read -p "🔗 Masukkan Direct Link file ZIP Backup: " linkzip
                    if [ ! -z "$linkzip" ]; then
                        wget -O restore.zip "$linkzip"
                        if [ -f "restore.zip" ]; then
                            unzip -o restore.zip
                            rm restore.zip
                            npm install
                            echo -e "\n✅ RESTORE BERHASIL SEPENUHNYA!"
                        else
                            echo "❌ Gagal download."
                        fi
                    fi
                fi
                read -p "Tekan Enter untuk kembali..."
                ;;
            0) break ;;
            *) echo "❌ Pilihan tidak valid!"; sleep 1 ;;
        esac
    done
}

# ==========================================
# 6-7 (Menu Member & Produk tetap sama, hanya teks display menyesuaikan)
# ==========================================
menu_member() {
    while true; do
        clear
        echo "==============================================="
        echo "          👥 MANAJEMEN MEMBER FIKY 👥          "
        echo "==============================================="
        echo "1. Tambah Saldo Member"
        echo "2. Kurangi Saldo Member"
        echo "3. Lihat Daftar Semua Member"
        echo "0. Kembali ke Menu Utama"
        echo "==============================================="
        read -p "Pilih menu [0-3]: " subchoice
        case $subchoice in
            1)
                read -p "Masukkan ID Member: " nomor
                read -p "Masukkan Jumlah Saldo: " jumlah
                node -e "
                    const fs = require('fs');
                    let db = fs.existsSync('database.json') ? JSON.parse(fs.readFileSync('database.json')) : {};
                    let target = '$nomor';
                    if(!db[target]) db[target] = { saldo: 0, tanggal_daftar: new Date().toLocaleDateString('id-ID'), jid: target + '@s.whatsapp.net' };
                    db[target].saldo += parseInt('$jumlah');
                    fs.writeFileSync('database.json', JSON.stringify(db, null, 2));
                    console.log('\n✅ Berhasil!');
                "
                read -p "Tekan Enter..." ;;
            2) 
                # Logika sama seperti sebelumnya
                read -p "Masukkan ID Member: " nomor
                read -p "Jumlah pengurangan: " jumlah
                node -e "
                    const fs = require('fs');
                    let db = fs.existsSync('database.json') ? JSON.parse(fs.readFileSync('database.json')) : {};
                    if(db['$nomor']) {
                        db['$nomor'].saldo -= parseInt('$jumlah');
                        fs.writeFileSync('database.json', JSON.stringify(db, null, 2));
                        console.log('✅ Saldo dikurangi');
                    }
                "
                read -p "Tekan Enter..." ;;
            3)
                node -e "
                    const fs = require('fs');
                    let db = fs.existsSync('database.json') ? JSON.parse(fs.readFileSync('database.json')) : {};
                    console.log(JSON.stringify(db, null, 2));
                "
                read -p "Tekan Enter..." ;;
            0) break ;;
        esac
    done
}

menu_produk() {
    while true; do
        clear
        echo "==============================================="
        echo "          🛒 MANAJEMEN PRODUK FIKY 🛒          "
        echo "==============================================="
        echo "1. Tambah / Edit Produk"
        echo "2. Hapus Produk"
        echo "3. Lihat Daftar Produk"
        echo "0. Kembali ke Menu Utama"
        echo "==============================================="
        read -p "Pilih menu [0-3]: " prodchoice
        case $prodchoice in
            1)
                read -p "Kode: " kode
                read -p "Nama: " nama
                read -p "Harga: " harga
                node -e "
                    const fs = require('fs');
                    let produk = fs.existsSync('produk.json') ? JSON.parse(fs.readFileSync('produk.json')) : {};
                    produk['$kode'.toUpperCase()] = { nama: '$nama', harga: parseInt('$harga') };
                    fs.writeFileSync('produk.json', JSON.stringify(produk, null, 2));
                "
                read -p "Selesai..." ;;
            3)
                node -e "
                    const fs = require('fs');
                    let p = fs.existsSync('produk.json') ? JSON.parse(fs.readFileSync('produk.json')) : {};
                    console.log(p);
                "
                read -p "Tekan Enter..." ;;
            0) break ;;
        esac
    done
}

# ==========================================
# 8. MENU UTAMA (PANEL KONTROL)
# ==========================================
while true; do
    clear
    echo "==============================================="
    echo "      🤖 PANEL PENGELOLA FIKY STORE 🤖      "
    echo "==============================================="
    echo "--- MANAJEMEN BOT ---"
    echo "1. Install & Buat File Bot Otomatis"
    echo "2. Mulai Bot (Terminal)"
    echo "3. Jalankan Bot di Latar Belakang (PM2)"
    echo "4. Hentikan Bot (PM2)"
    echo "5. Lihat Log / Error Bot"
    echo ""
    echo "--- MANAJEMEN TOKO & SISTEM ---"
    echo "6. 👥 Manajemen Member (Saldo)"
    echo "7. 🛒 Manajemen Produk (Harga)"
    echo "8. ⚙️ Bot Telegram Setup (Auto-Backup)"
    echo "9. 💾 Backup & Restore Data"
    echo "10. 🔌 Ganti API Digiflazz"
    echo "11. 🔄 Ganti Akun Bot WA (Reset Sesi)"
    echo "12. 📢 Kirim Pesan Broadcast"
    echo "0. Keluar"
    echo "==============================================="
    read -p "Pilih menu [0-12]: " choice

    case $choice in
        1) install_dependencies ;;
        2) 
            if [ ! -f "index.js" ]; then echo "❌ Anda harus menjalankan Menu 1 dulu!"; sleep 2; continue; fi
            if [ ! -d "sesi_bot" ] || [ -z "$(ls -A sesi_bot 2>/dev/null)" ]; then
                read -p "📲 Masukkan Nomor WA Bot (Awali 628...): " nomor_bot
                if [ ! -z "$nomor_bot" ]; then
                    node -e "
                        const fs = require('fs');
                        let config = fs.existsSync('config.json') ? JSON.parse(fs.readFileSync('config.json')) : {};
                        config.botNumber = '$nomor_bot';
                        config.botName = config.botName || 'FIKY STORE';
                        fs.writeFileSync('config.json', JSON.stringify(config, null, 2));
                    "
                fi
            fi
            echo -e "\n⏳ Menjalankan bot... (Tekan CTRL+C untuk mematikan dan kembali ke menu)"
            node index.js
            echo -e "\n⚠️ Proses bot terhenti."
            read -p "Tekan Enter untuk kembali ke menu utama..."
            ;;
        3) 
            pm2 delete fiky-bot 2>/dev/null
            pm2 start index.js --name "fiky-bot"
            pm2 save
            echo "✅ Bot FIKY STORE berjalan di latar belakang!"
            sleep 2 ;;
        4) 
            pm2 stop fiky-bot 2>/dev/null
            pm2 delete fiky-bot 2>/dev/null
            echo "✅ Bot dihentikan."
            sleep 2 ;;
        5) pm2 logs fiky-bot ;;
        6) menu_member ;;
        7) menu_produk ;;
        8) menu_telegram ;;
        9) menu_backup ;;
        10)
            read -p "Username Digiflazz: " u
            read -p "API Key: " k
            node -e "
                const fs = require('fs');
                let c = JSON.parse(fs.readFileSync('config.json'));
                c.digiflazzUsername = '$u';
                c.digiflazzApiKey = '$k';
                fs.writeFileSync('config.json', JSON.stringify(c, null, 2));
            "
            ;;
        11)
            rm -rf sesi_bot
            echo "✅ Sesi dihapus."
            sleep 2 ;;
        12)
            read -p "Pesan: " p
            echo -e "$p" > broadcast.txt
            echo "✅ Antrean broadcast dibuat."
            sleep 2 ;;
        0) exit 0 ;;
    esac
done
