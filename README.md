# Winner's Circle — Guide de déploiement

Application web statique servie par Nginx dans Docker, avec HTTPS automatique via Let's Encrypt (Certbot).

- **Domaine** : winners-circle.vip
- **Serveur** : VPS Debian (vps-254e8651)
- **Destination** : `/opt/wcercle`

---

## Prérequis

- Serveur Debian 11/12 (ou Ubuntu 22.04+)
- Accès root (ou sudo)
- Un nom de domaine pointant vers l'IP du serveur
- Ports **80** et **443** ouverts dans le pare-feu

> **Important :** le DNS doit être propagé avant de lancer le déploiement,
> sinon Certbot échouera à valider le domaine.

---

## Structure du projet

```
w-circle/
├── Dockerfile                  # Image nginx:alpine + fichier HTML
├── docker-compose.yml          # Services web (Nginx) + certbot
├── deploy.sh                   # Script de déploiement automatisé
├── remixed-daaf7b8c.html       # Application (fichier unique)
└── docs/
    ├── nginx-http.conf         # Config Nginx phase 1 (HTTP)
    ├── nginx-https.conf        # Config Nginx phase 2 (HTTPS, template)
    └── nginx-active.conf       # Config active (générée par deploy.sh)
```

---

## Déploiement automatisé (recommandé)

### 1. Cloner le repo sur le VPS

```bash
# Sur le VPS, depuis le home
git clone https://github.com/cendrinozus/w-circle.git ~/w-circle/w-circle
cd ~/w-circle/w-circle
```

### 2. Lancer le script

**Toujours lancer deploy.sh depuis le repo git (`~/w-circle/w-circle`), pas depuis `/opt/wcercle`.**

```bash
cd ~/w-circle/w-circle
sudo bash deploy.sh
```

Le script vous demande interactivement :

```
Domaine (ex: wcercle.monsite.com) : winners-circle.vip
Email Let's Encrypt (notifications expiration) : cendrinozus@gmail.com
```

### 3. Ce que fait le script automatiquement

| Phase | Action |
|-------|--------|
| **1** | Installe Docker si absent |
| **2** | Copie les fichiers vers `/opt/wcercle`, build l'image Nginx |
| **3** | Démarre Nginx en HTTP (port 80), télécharge l'image Certbot |
| **4** | Obtient le certificat SSL via Certbot (webroot) |
| **5** | Bascule Nginx en HTTPS, démarre le renouvellement automatique |

À la fin, le site est accessible en **https://winners-circle.vip**.

---

## Déploiement manuel étape par étape

Si le script échoue à mi-chemin, voici comment reprendre manuellement.

### Étape 1 — Installer Docker

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable --now docker
```

### Étape 2 — Démarrer Nginx en HTTP

```bash
cd /opt/wcercle
cp docs/nginx-http.conf docs/nginx-active.conf
docker compose build
docker compose up -d web
```

### Étape 3 — Obtenir le certificat SSL

> **Note :** si `docker compose run --rm certbot` reste bloqué à "Created" sans produire de sortie,
> utiliser `docker run` directement (plus fiable) :

```bash
docker run --rm \
  -v wcercle_certbot_webroot:/var/www/certbot \
  -v wcercle_certbot_certs:/etc/letsencrypt \
  certbot/certbot certonly \
    --webroot \
    --webroot-path /var/www/certbot \
    --email cendrinozus@gmail.com \
    --agree-tos \
    --no-eff-email \
    -d winners-circle.vip
```

Résultat attendu : `Successfully received certificate.`

### Étape 4 — Activer HTTPS

```bash
cd /opt/wcercle

# Utiliser sudo tee (évite l'erreur "Permission denied")
sed "s/DOMAIN/winners-circle.vip/g" docs/nginx-https.conf | sudo tee docs/nginx-active.conf > /dev/null

# Recharger Nginx
docker compose exec web nginx -s reload
```

Vérification :

```bash
curl -I https://winners-circle.vip
# → HTTP/2 200
```

### Étape 5 — Démarrer le renouvellement automatique

```bash
docker compose up -d certbot
```

---

## Mettre à jour le site

Après modification du fichier HTML, depuis le repo local :

```bash
# Local — commit et push
git add remixed-daaf7b8c.html
git commit -m "update: ..."
git push

# Sur le VPS
cd ~/w-circle/w-circle && git pull
cd /opt/wcercle
docker compose build --no-cache
docker compose up -d web
```

---

## Commandes utiles

```bash
# Depuis /opt/wcercle

# État des conteneurs
docker compose ps

# Logs Nginx en direct
docker compose logs -f web

# Logs Certbot
docker compose logs -f certbot

# Arrêter
docker compose down

# Recharger Nginx sans coupure
docker compose exec web nginx -s reload

# Tester le renouvellement SSL (dry-run)
docker compose run --rm certbot certbot renew --dry-run

# Voir les certificats
docker run --rm -v wcercle_certbot_certs:/etc/letsencrypt certbot/certbot certificates
```

---

## Dépannage

**Certbot bloqué à "Created" sans produire de sortie**
→ Utiliser `docker run` directement (voir Étape 3 du déploiement manuel).

**Permission denied sur docs/nginx-active.conf**
→ Utiliser `sudo tee` au lieu de `>` :
```bash
sed "s/DOMAIN/winners-circle.vip/g" docs/nginx-https.conf | sudo tee docs/nginx-active.conf > /dev/null
```

**Erreur "same file" lors de deploy.sh**
→ Lancer deploy.sh depuis `~/w-circle/w-circle`, jamais depuis `/opt/wcercle`.

**Certbot échoue avec "connection refused" ou "timeout"**
→ Vérifier que Nginx est démarré et que le port 80 est accessible :
```bash
docker compose ps
curl -I http://winners-circle.vip
```

**Nginx ne démarre pas**
```bash
docker compose logs web
cat docs/nginx-active.conf
```

**Certificat expiré**
```bash
docker run --rm \
  -v wcercle_certbot_webroot:/var/www/certbot \
  -v wcercle_certbot_certs:/etc/letsencrypt \
  certbot/certbot renew --force-renewal
docker compose exec web nginx -s reload
```

**Repartir de zéro**
```bash
docker compose down -v   # supprime aussi les volumes (certificats compris)
sudo rm -rf /opt/wcercle
# → relancer depuis ~/w-circle/w-circle avec sudo bash deploy.sh
```
