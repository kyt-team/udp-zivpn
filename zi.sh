echo -e "Updating server"
sudo apt-get update && apt-get upgrade -y
systemctl stop zivpn.service
echo -e "Downloading UDP Service"
wget https://github.com/arivpnstores/udp-zivpn/releases/download/zahidbd2/udp-zivpn-linux-amd64 -O /usr/local/bin/zivpn
chmod +x /usr/local/bin/zivpn
mkdir /etc/zivpn
wget https://raw.githubusercontent.com/arivpnstores/udp-zivpn/main/config.json -O /etc/zivpn/config.json
echo "Generating cert files:"
openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=US/ST=California/L=Los Angeles/O=Example Corp/OU=IT Department/CN=zivpn" -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt"
sysctl -w net.core.rmem_max=16777216
sysctl -w net.core.wmem_max=16777216
cat <<EOF > /etc/systemd/system/zivpn.service
[Unit]
Description=zivpn VPN Server
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0
[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true
[Install]
WantedBy=multi-user.target
EOF
echo -e "ZIVPN UDP Passwords -> otomatis pakai 'zi'"
new_config_str="\"config\": [\"zi\"]"
sed -i -E "s/\"config\": ?\[[^]]*\]/${new_config_str}/" /etc/zivpn/config.json
echo "Config berhasil diupdate menjadi: [\"zi\"]"
systemctl enable systemd-networkd-wait-online.service
systemctl daemon-reload
systemctl enable zivpn.service
systemctl restart zivpn.service
iptables -t nat -A PREROUTING -i $(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1) -p udp --dport 6000:19999 -j DNAT --to-destination :5667
ufw allow 6000:19999/udp
ufw allow 5667/udp
rm zi.*
echo -e "ZIVPN UDP Installed"