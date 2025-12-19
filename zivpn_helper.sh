CONFIG_DIR="/etc/zivpn"
TELEGRAM_CONF="${CONFIG_DIR}/telegram.conf"
function get_host() {
local CERT_CN
CERT_CN=$(openssl x509 -in "${CONFIG_DIR}/zivpn.crt" -noout -subject | sed -n 's/.*CN = \([^,]*\).*/\1/p')
if [ "$CERT_CN" == "zivpn" ]; then
curl -4 -s ifconfig.me
else
echo "$CERT_CN"
fi
}
function send_telegram_notification() {
local message="$1"
local keyboard="$2"
if [ ! -f "$TELEGRAM_CONF" ]; then
return 1
fi
source "$TELEGRAM_CONF"
if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
local api_url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
if [ -n "$keyboard" ]; then
curl -s -X POST "$api_url" -d "chat_id=${TELEGRAM_CHAT_ID}" --data-urlencode "text=${message}" -d "reply_markup=${keyboard}" > /dev/null
else
curl -s -X POST "$api_url" -d "chat_id=${TELEGRAM_CHAT_ID}" --data-urlencode "text=${message}" -d "parse_mode=Markdown" > /dev/null
fi
fi
}
function setup_telegram() {
echo "--- Konfigurasi Notifikasi Telegram ---"
read -p "Masukkan Bot API Key Anda: " api_key
read -p "Masukkan ID Chat Telegram Anda (dapatkan dari @userinfobot): " chat_id
if [ -z "$api_key" ] || [ -z "$chat_id" ]; then
echo "API Key dan ID Chat tidak boleh kosong. Pengaturan dibatalkan."
return 1
fi
echo "TELEGRAM_BOT_TOKEN=${api_key}" > "$TELEGRAM_CONF"
echo "TELEGRAM_CHAT_ID=${chat_id}" >> "$TELEGRAM_CONF"
chmod 600 "$TELEGRAM_CONF"
echo "Konfigurasi berhasil disimpan di $TELEGRAM_CONF"
return 0
}
function handle_backup() {
echo "--- Memulai Proses Backup ---"
source "$TELEGRAM_CONF"
GITHUB_USER="arivpnstores"
GITHUB_TOKEN="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"
GITHUB_REPO="backup"
VPS_IP=$(curl -4 -s ifconfig.me || curl -6 -s ifconfig.me)
backup_filename="zivpn_backup_${VPS_IP}_$(date +%Y%m%d-%H%M%S).zip"
temp_backup_path="/tmp/${backup_filename}"
files_to_backup=(
"$CONFIG_DIR/config.json"
"$CONFIG_DIR/users.db"
"$CONFIG_DIR/api_auth.key"
"$CONFIG_DIR/telegram.conf"
"$CONFIG_DIR/total_users.txt"
"$CONFIG_DIR/zivpn.crt"
"$CONFIG_DIR/zivpn.key"
)
echo "Membuat backup ZIP..."
zip -j -P "AriZiVPN-Gacorr123!" "$temp_backup_path" "${files_to_backup[@]}" >/dev/null
if [ $? -ne 0 ]; then
echo "❌ Backup gagal!" | tee -a /var/log/zivpn_backup.log
read -p "Tekan [Enter] untuk kembali ke menu..." && /usr/local/bin/zivpn-manager
fi
echo "Upload backup ke GitHub..."
base64_content=$(base64 -w 0 "$temp_backup_path")
github_response=$(curl -s -X PUT \
-H "Authorization: token ${GITHUB_TOKEN}" \
-H "Content-Type: application/json" \
-d "{\"message\": \"Backup ZIVPN ${VPS_IP} $(date +%Y-%m-%d_%H-%M-%S)\", \"content\": \"${base64_content}\"}" \
"https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/contents/${backup_filename}")
if echo "$github_response" | grep -q '"content":'; then
echo "✔️ Backup berhasil di GitHub" | tee -a /var/log/zivpn_backup.log
github_url="https://github.com/${GITHUB_USER}/${GITHUB_REPO}/blob/main/${backup_filename}"
else
echo "❌ Upload ke GitHub gagal!" | tee -a /var/log/zivpn_backup.log
rm -f "$temp_backup_path"
echo "Response GitHub: $github_response"
read -p "Tekan [Enter] untuk kembali ke menu..." && /usr/local/bin/zivpn-manager
fi
file_name="${backup_filename}"
message="⚠️ Backup ZIVPN VPS ${VPS_IP} Selesai ⚠️
Tanggal  : $(date +"%d %B %Y %H:%M:%S")
Nama file : <code>${backup_filename}</code>"
curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
-d chat_id="${TELEGRAM_CHAT_ID}" \
-d parse_mode="HTML" \
-d text="$message"
rm -f "$temp_backup_path"
clear
echo "⚠️ Backup ZIVPN VPS ${VPS_IP} Selesai ⚠️"
echo "Tanggal  : $(date +"%d %B %Y %H:%M:%S")"
echo "Nama file : ${backup_filename}"
echo "Backup selesai. Notifikasi terkirim." | tee -a /var/log/zivpn_backup.log
read -p "Tekan [Enter] untuk kembali ke menu..." && /usr/local/bin/zivpn-manager
}
function handle_expiry_notification() {
local host="$1"
local ip="$2"
local client="$3"
local isp="$4"
local exp_date="$5"
local message
message=$(cat <<EOF
◇━━━━━━━━━━━━━━◇
⛔SC ZIVPN EXPIRED ⛔
◇━━━━━━━━━━━━━━◇
IP VPS  : ${ip}
HOST  : ${host}
ISP     : ${isp}
CLIENT : ${client}
EXP DATE  : ${exp_date}
◇━━━━━━━━━━━━━━◇
EOF
)
local keyboard
keyboard=$(cat <<EOF
{
"inline_keyboard": [
[
{
"text": "Perpanjang Licence",
"url": "https://t.me/ARI_VPN_STORE"
}
]
]
}
EOF
)
send_telegram_notification "$message" "$keyboard"
}
function handle_renewed_notification() {
local host="$1"
local ip="$2"
local client="$3"
local isp="$4"
local expiry_timestamp="$5"
local current_timestamp
current_timestamp=$(date +%s)
local remaining_seconds=$((expiry_timestamp - current_timestamp))
local remaining_days=$((remaining_seconds / 86400))
local message
message=$(cat <<EOF
◇━━━━━━━━━━━━━━◇
✅RENEW SC ZIVPN✅
◇━━━━━━━━━━━━━━◇
IP VPS  : ${ip}
HOST  : ${host}
ISP     : ${isp}
CLIENT : ${client}
EXP : ${remaining_days} Days
◇━━━━━━━━━━━━━━◇
EOF
)
send_telegram_notification "$message"
}
function handle_api_key_notification() {
local api_key="$1"
local server_ip="$2"
local domain="$3"
local message
message=$(cat <<EOF
🚀 API UDP ZIVPN 🚀
🔑 Auth Key: ${api_key}
🌐 Server IP: ${server_ip}
🌍 Domain: ${domain}
EOF
)
send_telegram_notification "$message"
}
function handle_restore() {
echo "--- Starting Restore Process ---"
GITHUB_USER="arivpnstores"
GITHUB_TOKEN="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"
GITHUB_REPO="backup"
echo "List backup available in GitHub repo..."
local backups_json
backups_json=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
"https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/contents")
local backup_files
backup_files=$(echo "$backups_json" | jq -r '.[].name')
if [ -z "$backup_files" ]; then
echo "No backup files found in GitHub repo."
exit 1
fi
echo ""
read -p "Enter the backup filename you want to restore : " backup_file
if [ -z "$backup_file" ]; then
echo "Backup filename cannot be empty. Aborting."
exit 1
fi
read -p "WARNING: This will overwrite current data. Are you sure? (y/n): " confirm
if [ "$confirm" != "y" ]; then
echo "Restore cancelled."
exit 0
fi
local download_url="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main/${backup_file}"
local temp_restore_path="/tmp/restore_${backup_file}"
echo "Downloading backup file from GitHub..."
curl -s -L -o "$temp_restore_path" "$download_url"
if [ $? -ne 0 ]; then
echo "Failed to download backup file. Aborting."
rm -f "$temp_restore_path"
exit 1
fi
echo "Extracting and restoring data..."
unzip -P "AriZiVPN-Gacorr123!" -o "$temp_restore_path" -d "$CONFIG_DIR"
if [ $? -ne 0 ]; then
echo "Failed to extract backup archive. Aborting."
rm -f "$temp_restore_path"
exit 1
fi
rm -f "$temp_restore_path"
echo "Restarting ZIVPN service to apply changes..."
systemctl restart zivpn.service
echo "✅ Restore complete! Data restored from ${backup_file}."
read -p "Tekan [Enter] untuk kembali ke menu..." && /usr/local/bin/zivpn-manager
}
case "$1" in
backup)
handle_backup
;;
restore)
handle_restore
;;
setup-telegram)
setup_telegram
;;
expiry-notification)
if [ $# -ne 6 ]; then
echo "Usage: $0 expiry-notification <host> <ip> <client> <isp> <exp_date>"
exit 1
fi
handle_expiry_notification "$2" "$3" "$4" "$5" "$6"
;;
renewed-notification)
if [ $# -ne 6 ]; then
echo "Usage: $0 renewed-notification <host> <ip> <client> <isp> <expiry_timestamp>"
exit 1
fi
handle_renewed_notification "$2" "$3" "$4" "$5" "$6"
;;
api-key-notification)
if [ $# -ne 4 ]; then
echo "Usage: $0 api-key-notification <api_key> <server_ip> <domain>"
exit 1
fi
handle_api_key_notification "$2" "$3" "$4"
;;
*)
echo "Usage: $0 {backup|restore|setup-telegram|expiry-notification|renewed-notification|api-key-notification}"
exit 1
;;
esac