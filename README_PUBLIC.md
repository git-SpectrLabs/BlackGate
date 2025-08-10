
---

### **README_PUBLIC.md** (uppdaterad communityversion)

```markdown
# Raspberry Pi: Mullvad WireGuard + Kill Switch + Tor-proxy (SOCKS5)

## Vad du får
- Mullvad WireGuard-VPN
- Killswitch som stoppar trafik vid VPN-bortfall
- LAN-undantag så SSH fungerar alltid
- Tor-proxy ovanpå VPN
- Autostart vid boot
- `vpnstatus` för snabb kontroll

## Viktigt – Hur denna Pi fungerar
Pi:n är **inte** en router för hela ditt hemnätverk.  
Den är en **anonymitetsbox** som du manuellt skickar trafik igenom med Firefox SOCKS5-proxy. Plug-and-Play anonyma sessioner.

- **Utan proxy**: Vanlig internetanslutning.  
- **Med proxy**: Firefox → Pi → Mullvad/Tor → Internet.

### Trafikflödesdiagram:
**1. Ingen proxy (vanlig surf)**  

  ┌────────┐      ┌────────┐
   │ Laptop │──────▶│  ISP   │──────▶ Internet
  └────────┘      └────────┘

**2. Tor över Mullvad (SOCKS5-proxy)**

   ┌────────┐       ┌────────────┐      ┌──────────┐       ┌────────┐
   │ Laptop  │──────▶│Raspberry  │──────▶│  Tor   │──────▶│ Mullvad│──────▶ Internet
   │ (SOCKS5)│       │Pi (Tor)   │      └──────────┘       └────────┘
   └────────┘       └────────────┘


---

## 1. Förberedelser
1. Flasha Raspberry Pi OS Lite.
2. Aktivera SSH vid flashning.
3. Starta Pi och logga in via:
   ```bash
   ssh <username>@<Pi:ns IP>


## 2. Byt lösenord (rekommenderad sista steg efter allt är klart)
1. SSH in i Raspberry Pi
2. passwd
3. Changing password for <USER>.
4. Current password:
5. New password:
6. Retype new password:
7. The password has been changed.
7.1. ctrl + d för att avbryta förfrågan. 


## 3. Mullvad WireGuard-konfig
1. Hämta konfig från https://mullvad.net
	- OS: Linux
	- Port: 51820 UDP
2. Döp filen till wg0.conf
3. Kopiera till Pi:
	scp wg0.conf <username>@<Pi:ns IP>:/tmp/wg0.conf


## 4. Installation

1. Kör:
	chmod +x setup_all_in_one.sh
	./setup_all_in_one.sh
2. Skriptet:

 - Installerar nödvändiga paket
 - Lägger Mullvad-konfig i /etc/wireguard
 - Pin:ar endpoint-IP och uppdaterar nftables-regler
 - Aktiverar WireGuard, nftables, Tor i rätt ordning
 - Skapar vpnstatus-kommando


## 5. Tester
5.1. Kontrollera Mullvad:
	curl -s https://am.i.mullvad.net/json | jq .
5.2. Kontrollera killswitch:
	sudo wg-quick down wg0
	curl -m 5 https://ifconfig.io || echo "[+] BLOCKED"
	sudo wg-quick up wg0
5.3. Kontrollera Tor:
	torsocks curl -s https://check.torproject.org/api/ip
5.4. Snabbstatus:
	vpnstatus

## 5.5. Verifiering och tolkning av resultat

Det är viktigt att förstå skillnaden mellan hur tester i terminalen och via webbläsaren beter sig.

## Terminaltester
 - **Direkt Mullvad-test (utan Tor)**:
 ````bash
 curl -s https://am.i.mullvad.net/json | jq .
 
 Om VPN är aktivt: "mullvad_exit_ip": true och "ip": "<Mullvad-P>".

 - Tor-test:
 ¨¨¨¨bash
 torsocks curl -s https://check.torproject.org/api/ip

 Om Tor fungerar: "IsTor": true.

## Webbläsartester
 - Utan Proxy: 
 Öppna https://am.i.mullvad.net → ska visa Mullvad-IP och att VPN är aktiv. 
 - Med Tor-Proxy:
 Öppna https://check.torproject.org → ska säga att du använder Tor.
 OBS: Mullvads egen sida kommer här säga att VPN inte är aktiv, eftersom den ser Tor-exitnoden, inte Mullvad-IP. VPN är dock fortfarande aktiv i bakgrunden och bär Tor-trafiken.  


## 6. Firefox-konfig
Tor via Pi:
 - SOCKS Host: <Pi:ns IP>
 - Port: 9050
 - SOCKS v5 
 - "Proxy DNS when using SOCKS v5" 
Mullvad utan Tor:
 - Inaktivera proxyn.


## 7. Första gången du ansluter hemma
 - Om Pi är kopplad via Ethernet fungerar den direkt på valritt nät utan att du ändrar något (vår rekommendation).
 - Hitta Pi:ns IP i din router elelr med t.ex. appen "Fing" på mobilen.
 - Anslut via SSH med: 
 ¨¨¨¨bash
 ssh <username>@<Pi:ns IP>


## 8. Klart!
 Nu har du:
 - VPN och TOR via din Pi
 - Skydd mot läckor
 



