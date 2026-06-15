#!/bin/bash
# Nexus Backend - Termux Installer
# Bu script, Android telefona Nexus backend'i kurar

set -e

echo "=== Nexus Backend Kurulumu ==="
echo ""

# 1. Paketleri güncelle
echo "[1/5] Paketler güncelleniyor..."
pkg update -y

# 2. Gerekli paketleri kur
echo "[2/5] Python, ffmpeg, git kuruluyor..."
pkg install -y python ffmpeg git

# 3. yt-dlp kur
echo "[3/5] yt-dlp kuruluyor..."
pip install yt-dlp

# 4. Backend'i indir
echo "[4/5] Backend kodu indiriliyor..."
if [ -d "Nexus_MusicApp" ]; then
    cd Nexus_MusicApp
    git pull
else
    git clone https://github.com/TahaArslan67/Nexus_MusicApp.git
    cd Nexus_MusicApp
fi

cd backend

# 5. Python bağımlılıkları
echo "[5/5] Python bağımlılıkları kuruluyor..."
pip install -r requirements.txt

echo ""
echo "=== Kurulum tamamlandı! ==="
echo ""
echo "Başlatmak için:"
echo "  cd ~/Nexus_MusicApp/backend"
echo "  uvicorn app.main:app --host 0.0.0.0 --port 8000"
echo ""
echo "Telefon IP adresini öğrenmek için:"
echo "  ifconfig"
echo "  (wlan0 veya ap0 altındaki inet adresi)"
echo ""
echo "Uygulamada Backend URL olarak şunu gir:"
echo "  http://TELEFON_IP:8000"
