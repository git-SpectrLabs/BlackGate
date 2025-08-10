# Raspberry Pi: Mullvad WireGuard + Kill Switch + Tor‑proxy (SOCKS5) – Full teknisk dokumentation

## Förutsättningar (hårdvara och rekommendationer)

- Raspberry Pi 4 (rekommenderat för prestanda)
- microSD‑kort (minst 8 GB, gärna 16–32 GB för framtida loggning & funktioner)
- Ethernet‑kabel (stabil anslutning och automatisk IP via DHCP i alla nät)
- Strömadapter (5V 3A för Pi 4)
- En dator för att flasha Raspberry Pi OS Lite till microSD

 **Ethernet rekommenderas** vid första konfigurationen och om enheten ska skickas till någon annan – funkar direkt på valfritt nät via DHCP.

---

## 0. Viktig kontext – hur Pi:n fungerar i detta upplägg

Pi:n är **inte** en gateway/router för hela hemnätet. Den fungerar som en **dedikerad anonymitetsbox** som du **manuellt** skickar trafik igenom via Firefox (eller annan app) med SOCKS5‑proxy mot Pi:n. Den hanterar endast trafik som explicit skickas via den (t.ex. med SOCKS5-proxy i Firefox). Övrig trafik från datorn går som vanligt via din ISP om inte ytterligare routing sätts upp.

- **Utan proxy:** Din trafik går som vanligt via din ISP.
- **Med SOCKS5‑proxy:** All trafik från Firefox går → Pi → Mullvad/Tor → Internet.

### Trafikflödesdiagram (tre lägen)


**1. Ingen proxy (vanlig surf)**  
   ┌────────┐       ┌────────┐
   │ Laptop │──────▶│  ISP   │──────▶ Internet
   └────────┘       └────────┘

**2. Mullvad-läge (VPN only)**
   ┌────────┐       ┌────────────┐      ┌────────┐
   │ Laptop │──────▶│ Raspberry │──────▶│ Mullvad│──────▶ Internet
   │        │       │   Pi (VPN) │       └────────┘
   └────────┘       └────────────┘

**3. Tor över Mullvad (SOCKS5-proxy)**
   ┌────────┐        ┌────────────┐      ┌──────────┐      ┌────────┐
   │ Laptop │──────▶│ Raspberry  │──────▶│  Tor    │──────▶│ Mullvad│──────▶ Internet
   │(SOCKS5)│        │ Pi (Tor)   │      └──────────┘       └────────┘
   └────────┘        └────────────┘


Detta upplägg gör att du kan växla anonymitetsnivå manuellt utan att påverka annan trafik i hemmet.

---

## 1. Förberedelser

1. Flasha Raspberry Pi OS Lite till SD-kort.
2. Aktivera SSH vid flashning (i Pi Imager → Avancerade inställningar).
3. Starta Pi och logga in via:
   ```bash
   ssh <usernamne>@<Pi:ns IP>


## 2. Byt lösenord (rekommenderad sista steg efter allt är klart)

1. SSH in i Raspberry Pi
2. passwd
3. Changing password for <USER>.
4. Current password:
5. New password:
6. Retype new password:
7. The password has been changed.
7.1. ctrl + d för att avbryta förfrågan. 


## 3. Mullvad Wireguard-konfig

1. Hämta konfig från https://mullvad.net:
 - OS: Linux
 - Port: 51820 UDP
2. Döp filen till wg0.conf
3.  Kopiera till Pi:
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

### Teknisk översikt av `setup_all_in_one.sh`
Detta skript automatiserar hela konfigurationen av Raspberry Pi som anonymitetsbox med Mullvad WireGuard och Tor-proxy. I stora drag utför det följande:

1. **Installerar nödvändiga paket**  
   - WireGuard, nftables, Tor, curl, jq m.fl.

2. **Importerar Mullvad-konfiguration**  
   - Flyttar användarens `wg0.conf` till `/etc/wireguard/`.
   - Pinnar VPN-endpoint till dess IP-adress för att undvika DNS-beroende.

3. **Ställer in killswitch** (nftables)  
   - Tillåter endast trafik via WireGuard-tunneln eller LAN.
   - Blockerar all annan utgående trafik vid VPN-avbrott.

4. **Aktiverar Tor-tjänst**  
   - Kör Tor parallellt med VPN.
   - Öppnar SOCKS5-port för anslutningar (9050).

5. **Autostart**  
   - Lägger in WireGuard, nftables och Tor i korrekt startordning vid boot.

6. **Skapar hjälpfunktioner**  
   - `vpnstatus` för snabb statuskoll av VPN, Tor och nätverk.

Skriptet är byggt för att vara **idempotent** – om du kör det igen, kontrollerar det befintliga inställningar innan ändringar görs, vilket minskar risken att låsa ute dig eller skriva över kritiska konfigfiler.




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

## 5.5 Verifiering och tolkning av resultat

Det är viktigt att förstå skillnaden mellan hur tester i terminalen och via webbläsaren beter sig.

### Terminaltester
 - **Direkt Mullvad-test (utan Tor)**:
  ```bash
  curl -s https://am.i.mullvad.net/json | jq .
Om VPN är aktivt: "mullvad_exit_ip": true och "ip": "<Mullvad-IP>".

 - **Tor-test**:
  ```bash
 torsocks curl -s https://check.torproject.org/api/ip
Om Tor fungerar: "IsTor": true.


### Webbläsartester
 - Utan Proxy:
	Öppna https://am.i.mullvad.net → ska visa Mullvad-IP och att VPN är aktiv.
 - Med Tor-Proxy:
	Öppna https://check.torproject.org → ska säga att du använder Tor.
OBS: Mullvads egen sida kommer att säga VPN inte är aktiv, eftersom den ser Tor-exitnoden, inte Mullvad-IP. VPN är dock fortfarande aktiv i bakgrunden och bär Tor-trafiken.


## 6. Firefox-konfig

Tor via Pi:
 - SOCKS Host: <Pi:ns IP>
 - Port: 9050
 - SOCKS v5 
 - "Proxy DNS when using SOCKS v5" (viktigt – se nedan)

Mullvad utan Tor:
 - Inaktivera proxyn.

## 6.1. Varför "Proxy DNS when using SOCKS v5" är kritisk

 - Om avmarkerad: Firefox skickar DNS-slag direkt till din ISP → de ser vilka domäner du besöker (DNS-leak).
 - Om markerad: DNS-slag går genom proxyn (Tor/Mullvad) → din ISP ser bara att du är ansluten till Pi:n.

Endast vid avancerad lokal DNS-konfig på Pi:n är det meningsfullt att stänga av den – annars alltid på.

 - Fördelar: Maximal anonymitet, Tor-nätet skyddar mot spårning, Mullvad skyddar mot att Tor ser din riktiga IP.
Mullvads sida visar inte VPN aktiv i Tor-läge — normalt.


## 7. Felsäkerhetssteg (om du låste ute dig)

 - In i recovery-terminal på Pi och kör:
	sudo nft flush ruleset
	sudo systemctl stop wg-quick@wg0
	sudo systemctl disable wg-quick@wg0
 - Nu är killswitch av.


## 7.5. Ethernet och Wi-Fi i olika nätverk

 - Om Pi är ansluten via Ethernet spelar sparade Wi-Fi-uppgifter ingen roll.
 - Ethernet använder DHCP och fungerar direkt på valfritt nätverk utan ändringar.
 - Första gången i nytt nät → kolla routeradmin eller kör arp-scan för att hitta Pi:ns IP.


## 8. Säkerhetsfilosofi

 - WireGuard: Krypterar all trafik → Mullvad-server.

 - Killswitch: Förhindrar trafik utan VPN.

 - LAN-undantag: Möjliggör SSH/proxy även om VPN faller.

 - Tor: Ger extra anonymitet ovanpå VPN.

 - Endpoint pin: Hindrar DNS-baserade attacker.

 - Autostart: Säkerställer skydd från boot.

 - vpnstatus: Ger realtidsöversikt.


## 9. Lager-för-lager felsökning

1.	LAN → ping 192.168.1.1

2. VPN → curl https://am.i.mullvad.net/json

3. Tor → torsocks curl https://check.torproject.org/api/ip


## 10. Sammanfattning av trafikvägar

 - Firefox utan proxy: Dator → ISP → Internet

 - Firefox med proxy: Dator (SOCKS5) → Pi (Tor) → Mullvad → Internet


## Om allt krånglar – Starta om från noll
*(Återställning genom att re-flasha SD-kortet)*

**När använda detta:**  
- Om du låst ute dig och inte kan nå Pi:n via SSH.  
- Om konfigurationen är så fel att `vpnstatus`, WireGuard eller Tor inte fungerar alls.  
- Om nätverksinställningarna är trasiga och killswitchen blockerar även LAN-åtkomst.

**Steg för att börja om:**
1. Ta ur microSD-kortet ur Pi:n och sätt det i din dator (via adapter om det behövs).
2. Ladda ner **Raspberry Pi Imager**:  
   https://www.raspberrypi.com/software/
3. Välj operativsystem: **Raspberry Pi OS Lite (64-bit)**.
4. Välj ditt SD-kort som mål.
5. Klicka på **kugghjulet** i Imager (avancerade inställningar):  
   - Aktivera SSH  
   - Ange användarnamn/lösenord  
   - Ställ in Wi-Fi (om du ska använda det)  
6. Flasha kortet och vänta tills processen är klar.
7. Sätt tillbaka kortet i Pi:n och starta.
8. Anslut via SSH:
   ```bash
   ssh pi@<Pi:ns IP>
