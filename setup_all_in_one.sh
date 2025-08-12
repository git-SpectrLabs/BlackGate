#!/usr/bin/env bash
set -euo pipefail

echo "=== Mullvad WireGuard + nftables killswitch + Tor SOCKS proxy + autopin + status ==="
echo "Target: Raspberry Pi OS Lite (Bookworm) på Raspberry Pi 4"

# ---------- Helpers ----------
need_pkg(){ dpkg -s "$1" >/dev/null 2>&1 || { sudo apt-get update -y; sudo apt-get install -y "$1"; }; }
die(){ echo "[!] $*"; exit 1; }

# ---------- Paket ----------
need_pkg wireguard
need_pkg resolvconf
need_pkg nftables
need_pkg curl
need_pkg jq
need_pkg torsocks
need_pkg tor

# ---------- Hitta/placera wg0.conf ----------
WGCONF="/etc/wireguard/wg0.conf"
CANDIDATES=( "$WGCONF" "/tmp/wg0.conf" "/boot/wg0.conf" "$HOME/wg0.conf" )
if [[ ! -f "$WGCONF" ]]; then
  for c in "${CANDIDATES[@]}"; do
    [[ -f "$c" ]] && { echo "[*] Hittade konfig: $c -> $WGCONF"; sudo mkdir -p /etc/wireguard; sudo mv "$c" "$WGCONF"; break; }
  done
fi
[[ -f "$WGCONF" ]] || die "Hittar inte wg0.conf. Lägg din Mullvadkonfig som /tmp/wg0.conf och kör igen."

sudo chown root:root "$WGCONF"; sudo chmod 600 "$WGCONF"; sudo sed -i 's/\r$//' "$WGCONF"
sudo sed -i '/^PostUp/d;/^PreDown/d' "$WGCONF"

grep -q '^\[Interface\]' "$WGCONF" && grep -q '^\[Peer\]' "$WGCONF" || die "Felaktig wg0.conf (saknar [Interface] eller [Peer])."

# ---------- Endpoint → IPv4 ----------
read EP_HOST_OR_IP EP_PORT < <(sed -n 's/^[[:space:]]*Endpoint[[:space:]]*=[[:space:]]*\([^: ]*\):\([0-9]\+\).*/\1 \2/p' "$WGCONF")
[[ -n "${EP_HOST_OR_IP:-}" && -n "${EP_PORT:-}" ]] || die "Kunde inte läsa Endpoint i wg0.conf."
if [[ "$EP_HOST_OR_IP" =~ [a-zA-Z] ]]; then
  EP_IP=$(getent ahostsv4 "$EP_HOST_OR_IP" | awk '{print $1; exit}')
  [[ -n "${EP_IP:-}" ]] || die "DNS-resolution misslyckades för $EP_HOST_OR_IP"
  sudo sed -i "s|^Endpoint *= *.*|Endpoint = ${EP_IP}:${EP_PORT}|" "$WGCONF"
else
  EP_IP="$EP_HOST_OR_IP"
fi
echo "[*] Endpoint pin: $EP_IP:$EP_PORT"

# ---------- LAN discovery ----------
LAN_IF=$(ip route show default | awk '{print $5; exit}')
LAN_CIDR=$(ip -4 addr show dev "$LAN_IF" | awk '/inet /{print $2; exit}')
[[ -n "${LAN_IF:-}" && -n "${LAN_CIDR:-}" ]] || die "Kunde inte avgöra LAN-interface/CIDR."
echo "[*] LAN_IF=$LAN_IF  LAN_CIDR=$LAN_CIDR"

# ---------- Starta WireGuard ----------
sudo systemctl stop wg-quick@wg0 >/dev/null 2>&1 || true
sudo wg-quick down wg0 >/dev/null 2>&1 || true
if ! sudo wg-quick up wg0; then
  echo "[!] wg-quick up misslyckades. Sista loggrader:"
  sudo journalctl -xeu wg-quick@wg0.service --no-pager | tail -n 120
  exit 1
fi

# ---------- nftables killswitch ----------
NFTCONF="/etc/nftables.conf"
sudo tee "$NFTCONF" >/dev/null <<EOF
#!/usr/sbin/nft -f
flush ruleset
table inet filter {
  chain input {
    type filter hook input priority 0; policy drop;
    ct state established,related accept
    iifname "lo" accept
    ip saddr $LAN_CIDR tcp dport 22 accept
    ip saddr $LAN_CIDR tcp dport 9050 accept
    iifname "wg0" accept
    ip saddr $LAN_CIDR icmp type echo-request accept
  }
  chain forward {
    type filter hook forward priority 0; policy drop;
  }
  chain output {
    type filter hook output priority 0; policy drop;
    ct state established,related accept
    oifname "lo" accept
    oifname "wg0" accept
    ip daddr $EP_IP udp dport $EP_PORT accept
  }
}
EOF

sudo nft -c -f "$NFTCONF"
sudo systemctl enable --now nftables

# ---------- Autostart-ordning ----------
sudo mkdir -p /etc/systemd/system/wg-quick@wg0.service.d
sudo tee /etc/systemd/system/wg-quick@wg0.service.d/override.conf >/dev/null <<'EOF'
[Unit]
After=nftables.service
Wants=nftables.service
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now wg-quick@wg0

# ---------- Auto-pin ----------
sudo tee /usr/local/bin/wg-pin-endpoint.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
WGCONF="/etc/wireguard/wg0.conf"
NFTCONF="/etc/nftables.conf"
read CUR_IP CUR_PORT < <(awk -F '[ =:]+' '/^Endpoint/ {print $3, $4}' "$WGCONF" | head -n1)
[[ -z "${CUR_IP:-}" || -z "${CUR_PORT:-}" ]] && exit 0
if [[ "$CUR_IP" =~ [a-zA-Z] ]]; then NEW_IP=$(getent ahostsv4 "$CUR_IP" | awk '{print $1; exit}'); else NEW_IP="$CUR_IP"; fi
[[ -z "${NEW_IP:-}" ]] && exit 0
CHANGED=0
if [[ "$NEW_IP" != "$CUR_IP" ]]; then sed -i "s|^Endpoint *= *.*|Endpoint = ${NEW_IP}:${CUR_PORT}|" "$WGCONF"; CHANGED=1; fi
if grep -q 'ip daddr ' "$NFTCONF"; then
  NFT_CUR_IP=$(awk '/ip daddr /{for(i=1;i<=NF;i++) if($i=="daddr"){print $(i+1); exit}}' "$NFTCONF" | tr -d ';')
  if [[ -n "$NFT_CUR_IP" && "$NFT_CUR_IP" != "$NEW_IP" ]]; then sed -i "s|ip daddr [0-9.\\]*|ip daddr ${NEW_IP}|g" "$NFTCONF"; systemctl restart nftables || true; CHANGED=1; fi
fi
[[ "$CHANGED" -eq 1 ]] && systemctl restart wg-quick@wg0 || true
EOF
sudo chmod +x /usr/local/bin/wg-pin-endpoint.sh

sudo tee /etc/systemd/system/wg-pin-endpoint.service >/dev/null <<'EOF'
[Unit]
Description=Pin Mullvad endpoint IP and sync nftables
Wants=network-online.target
After=network-online.target
Before=wg-quick@wg0.service
[Service]
Type=oneshot
ExecStart=/usr/local/bin/wg-pin-endpoint.sh
RemainAfterExit=true
[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/wg-pin-endpoint.timer >/dev/null <<'EOF'
[Unit]
Description=Run wg-pin-endpoint every 30 minutes
[Timer]
OnBootSec=2min
OnUnitActiveSec=30min
Unit=wg-pin-endpoint.service
[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now wg-pin-endpoint.service
sudo systemctl enable --now wg-pin-endpoint.timer

# ---------- Tor SOCKS5-proxy ----------
sudo sed -i '/^SocksPort/d;/^ClientOnly/d' /etc/tor/torrc
echo "SocksPort 0.0.0.0:9050" | sudo tee -a /etc/tor/torrc >/dev/null
echo "ClientOnly 1" | sudo tee -a /etc/tor/torrc >/dev/null

sudo mkdir -p /etc/systemd/system/tor.service.d
sudo tee /etc/systemd/system/tor.service.d/override.conf >/dev/null <<'EOF'
[Unit]
After=wg-quick@wg0.service network-online.target
Wants=wg-quick@wg0.service network-online.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now tor

# ---------- vpnstatus ----------
sudo tee /usr/local/bin/vpnstatus >/dev/null <<'EOF'
#!/usr/bin/env bash
echo "=== WireGuard (wg0) ==="
sudo wg show || true
echo
echo "=== nftables (top) ==="
sudo nft list ruleset | head -n 50 || true
echo
echo "=== External IP (via Mullvad) ==="
curl -s https://am.i.mullvad.net/json | jq . || true
echo
echo "=== Tor SOCKS listen ==="
sudo ss -ltnp | grep 9050 || true
EOF
sudo chmod +x /usr/local/bin/vpnstatus

# ---------- Självtest ----------
echo "[*] Mullvad-koll:"
curl -s https://am.i.mullvad.net/json | jq . || true

echo "[*] Killswitch-test (stoppar VPN med wg-quick)…"
sudo wg-quick down wg0
curl -m 5 https://ifconfig.io || echo "[+] BLOCKED (bra!)"
echo "[*] Startar VPN igen…"
sudo wg-quick up wg0
curl -s https://am.i.mullvad.net/json | jq . || true

echo
echo "=== KLART ✅ ==="
echo "Autostartordning: nftables → wg-pin → WireGuard → Tor"
echo "Tor SOCKS5 lyssnar på 0.0.0.0:9050 (öppet för LAN $LAN_CIDR)"
echo "Snabbstatus: kör 'vpnstatus'"
