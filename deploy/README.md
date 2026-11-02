# DentHub-Brush web telepítése a metalquo szerverre (aldomain)

Egyetlen kis Node-szolgáltatás (irányítópult + titkosított továbbító). Adatbázis nem kell, nem tárol adatot.
A lenti példákban az aldomain `brush.example.hu`: cseréld a valódira.

## 1. DNS
A domain DNS-kezelőjében vegyél fel egy rekordot az aldomainre:

| Típus | Név | Érték |
|---|---|---|
| A | `brush` | a metalquo szerver IPv4-címe |
| AAAA (ha van IPv6) | `brush` | a szerver IPv6-címe |

## 2. Szerver (egyszer)
Docker-rel (ajánlott):
```bash
sudo apt install docker.io docker-compose-v2 nginx certbot python3-certbot-nginx
sudo usermod -aG docker <deploy-felhasználó>
sudo mkdir -p /opt/denthub-brush && sudo chown <deploy-felhasználó> /opt/denthub-brush
```
Nginx + https:
```bash
sudo cp nginx-denthub-brush.conf /etc/nginx/sites-available/denthub-brush   # írd át benne az aldomaint
sudo ln -s ../sites-available/denthub-brush /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d brush.example.hu
```
(Caddy esetén elég a `Caddyfile`; Docker nélkül a `denthub-brush.service` systemd-egységgel is fut, Node.js 18+ kell.)
Ha a szerveren már fut valami a 8090-es porton, a `docker-compose.yml` mellé tegyél egy `.env` fájlt: `BRUSH_PORT=8091`, és az nginx-konfigban is írd át.

## 3. Automatikus telepítés a GitHubról
1. Készíts egy SSH-kulcspárt csak ehhez: `ssh-keygen -t ed25519 -f denthub-deploy -N ""`.
   A `denthub-deploy.pub` tartalmát tedd a szerveren a deploy-felhasználó `~/.ssh/authorized_keys` fájljába.
2. GitHub → a repó **Settings → Secrets and variables → Actions → New repository secret**:

| Név | Érték |
|---|---|
| `DEPLOY_HOST` | a szerver címe vagy IP-je |
| `DEPLOY_USER` | a deploy-felhasználó |
| `DEPLOY_SSH_KEY` | a `denthub-deploy` (privát kulcs) teljes tartalma |
| `DEPLOY_DOMAIN` | az aldomain, pl. `brush.example.hu` |
| `DEPLOY_PORT` | csak ha az SSH nem a 22-es porton van |
| `DEPLOY_MODE` | `systemd`, ha Docker nélkül fut |

3. **Actions → Deploy web (metalquo) → Run workflow.** Ezután a `main` ágra feltöltött minden webes
   változás magától kikerül. A futás végén a GitHub ellenőrzi, hogy a `https://<aldomain>/healthz` válaszol.

## Ellenőrzés
Nyisd meg a `https://brush.example.hu` címet: QR-kódnak kell megjelennie. A telefonon:
Statisztika → Megnézem a weben → QR-kód beolvasása.
