# Winner's Circle — Guide de déploiement

Application web statique servie par Nginx dans Docker, avec HTTPS automatique via Let's Encrypt (Certbot).

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
w-cercle/
├── Dockerfile                  # Image nginx:alpine + fichier HTML
├── docker-compose.yml          # Services web (Nginx) + certbot
├── deploy.sh                   # Script de déploiement automatisé
├── remixed-daaf7b8c.html       # Application (fichier unique)
└── docs/
    ├── nginx-http.conf         # Config Nginx phase 1 (HTTP)
    └── nginx-https.conf        # Config Nginx phase 2 (HTTPS, template)
```

---

## Déploiement automatisé (recommandé)

Le script `deploy.sh` gère l'intégralité du déploiement en 4 phases.

### 1. Copier le projet sur le serveur

```bash
# Depuis votre machine locale
scp -r /chemin/vers/w-cercle user@ip-serveur:/opt/wcercle
```

Ou via Git si le projet est sur un dépôt :

```bash
git clone https://github.com/votre-compte/w-cercle.git /opt/wcercle
```

### 2. Lancer le script

```bash
cd /opt/wcercle
sudo bash deploy.sh
```

Le script vous demande interactivement :

```
Domaine (ex: wcercle.monsite.com) : wcercle.monsite.com
Email Let's Encrypt (notifications expiration) : votre@email.com
```

### 3. Ce que fait le script automatiquement

| Phase | Action |
|-------|--------|
| **1** | Installe Docker si absent |
| **2** | Build l'image Nginx + démarre le conteneur en HTTP (port 80) |
| **3** | Certbot valide le domaine et obtient le certificat SSL |
| **4** | Bascule Nginx en HTTPS, démarre le renouvellement automatique |
| **5** | Ajoute un cron quotidien pour recharger Nginx après renouvellement |

À la fin, le site est accessible en **https://votre-domaine.com**.

---

## Déploiement manuel étape par étape

Si vous préférez contrôler chaque étape manuellement.

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

Vérification :

```bash
docker --version
docker compose version
```

### Étape 2 — Préparer le projet

```bash
sudo mkdir -p /opt/wcercle
sudo cp -r /chemin/vers/w-cercle/. /opt/wcercle/
cd /opt/wcercle
```

### Étape 3 — Démarrer Nginx en HTTP

```bash
cp docs/nginx-http.conf docs/nginx-active.conf
docker compose build
docker compose up -d web
```

Vérification :

```bash
docker compose ps
curl -I http://votre-domaine.com
# → HTTP/1.1 200 OK
```

### Étape 4 — Obtenir le certificat SSL

```bash
docker compose run --rm certbot certbot certonly \
    --webroot \
    --webroot-path /var/www/certbot \
    --email votre@email.com \
    --agree-tos \
    --no-eff-email \
    -d votre-domaine.com
```

Le certificat est stocké dans le volume Docker `wcercle_certbot_certs`.

### Étape 5 — Activer HTTPS

```bash
# Remplacer DOMAIN par votre domaine dans la config HTTPS
sed "s/DOMAIN/votre-domaine.com/g" docs/nginx-https.conf > docs/nginx-active.conf

# Recharger Nginx
docker compose exec web nginx -s reload
```

Vérification :

```bash
curl -I https://votre-domaine.com
# → HTTP/2 200
```

### Étape 6 — Démarrer le renouvellement automatique

```bash
docker compose up -d certbot
```

Ajouter un cron pour recharger Nginx après chaque renouvellement :

```bash
(crontab -l 2>/dev/null; echo "0 4 * * * cd /opt/wcercle && docker compose exec web nginx -s reload >> /var/log/wcercle-ssl-reload.log 2>&1") | crontab -
```

---

## Mettre à jour le site

Après modification du fichier HTML :

```bash
cd /opt/wcercle

# Mettre à jour les fichiers
cp /chemin/nouveau/fichier.html remixed-daaf7b8c.html

# Rebuild et redémarrage
docker compose build --no-cache
docker compose up -d web
```

---

## Commandes utiles

```bash
# Voir l'état des conteneurs
docker compose ps

# Logs Nginx en direct
docker compose logs -f web

# Logs Certbot
docker compose logs -f certbot

# Arrêter les conteneurs
docker compose down

# Redémarrer
docker compose restart web

# Recharger la config Nginx sans coupure
docker compose exec web nginx -s reload

# Tester le renouvellement SSL (dry-run)
docker compose run --rm certbot certbot renew --dry-run
```

---

## Vérifier le certificat SSL

```bash
# Informations sur le certificat
docker compose run --rm certbot certbot certificates

# Test SSL externe
curl -I https://votre-domaine.com
```

---

## Pare-feu (UFW)

Si UFW est actif sur le serveur :

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw reload
```

---

## Dépannage

**Certbot échoue avec "connection refused" ou "timeout"**
→ Vérifiez que le DNS pointe bien vers l'IP du serveur : `dig votre-domaine.com`
→ Vérifiez que les ports 80/443 sont ouverts dans le pare-feu et chez votre hébergeur.

**Nginx ne démarre pas**
```bash
docker compose logs web
# Vérifier la config active :
cat docs/nginx-active.conf
```

**Certificat expiré**
```bash
docker compose run --rm certbot certbot renew --force-renewal
docker compose exec web nginx -s reload
```

**Repartir de zéro**
```bash
docker compose down -v   # supprime aussi les volumes (certificats compris)
docker compose build --no-cache
# → relancer depuis l'étape 3
```
