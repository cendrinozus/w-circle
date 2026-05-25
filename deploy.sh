#!/bin/bash
# deploy.sh — Winner's Circle sur Debian + Docker + Certbot (HTTPS)
# Usage: sudo bash deploy.sh

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="/opt/wcercle"
EMAIL=""
DOMAIN=""

# --- Vérifications ---
if ! command -v apt &>/dev/null; then
    error "Ce script requiert un système Debian/Ubuntu"
fi
if [[ $EUID -ne 0 ]]; then
    error "Exécuter en root : sudo bash deploy.sh"
fi

# --- Saisie du domaine et email ---
echo ""
read -rp "Domaine (ex: wcercle.monsite.com) : " DOMAIN
read -rp "Email Let's Encrypt (notifications expiration) : " EMAIL
[[ -z "$DOMAIN" ]] && error "Domaine requis"
[[ -z "$EMAIL" ]] && error "Email requis"

info "=== Déploiement Winner's Circle — $DOMAIN ==="

# --- Installation Docker ---
if ! command -v docker &>/dev/null; then
    info "Installation de Docker..."
    apt update -qq
    apt install -y -qq ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list
    apt update -qq
    apt install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl enable --now docker
    info "Docker installé ✓"
else
    info "Docker déjà présent : $(docker --version)"
fi

# --- Copie du projet ---
info "Copie des fichiers vers $APP_DIR..."
mkdir -p "$APP_DIR"
cp -r "$SCRIPT_DIR/." "$APP_DIR/"
cd "$APP_DIR"

# ── PHASE 1 : HTTP uniquement ────────────────────────────────────────────────
info "Phase 1 — Démarrage Nginx en HTTP (port 80)..."
cp docs/nginx-http.conf docs/nginx-active.conf

docker compose build --quiet
docker compose up -d web

sleep 3
docker compose ps | grep -q "Up" || error "Nginx n'a pas démarré. Vérifiez : docker compose logs web"
info "Nginx HTTP actif ✓"

# ── PHASE 2 : Obtention du certificat ───────────────────────────────────────
info "Phase 2 — Obtention du certificat Let's Encrypt pour $DOMAIN..."
docker compose run --rm certbot certbot certonly \
    --webroot \
    --webroot-path /var/www/certbot \
    --email "$EMAIL" \
    --agree-tos \
    --no-eff-email \
    -d "$DOMAIN"

info "Certificat obtenu ✓"

# ── PHASE 3 : Nginx HTTPS ────────────────────────────────────────────────────
info "Phase 3 — Activation HTTPS..."
sed "s/DOMAIN/$DOMAIN/g" docs/nginx-https.conf > docs/nginx-active.conf

# Recharger Nginx avec la nouvelle config
docker compose exec web nginx -s reload
info "Nginx HTTPS actif ✓"

# ── PHASE 4 : Renouvellement automatique ────────────────────────────────────
info "Phase 4 — Démarrage du renouvellement automatique..."
docker compose up -d certbot

# Cron hôte : reload Nginx après chaque renouvellement
CRON_JOB="0 4 * * * cd $APP_DIR && docker compose exec web nginx -s reload >> /var/log/wcercle-ssl-reload.log 2>&1"
(crontab -l 2>/dev/null | grep -qF "wcercle") || \
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
info "Cron de reload SSL configuré ✓"

# ── Résumé ───────────────────────────────────────────────────────────────────
info ""
info "=== Déploiement terminé ! ==="
info "Site     : https://$DOMAIN"
info "Conteneurs :"
docker compose ps
info ""
warn "Commandes utiles (depuis $APP_DIR) :"
warn "  Logs Nginx   : docker compose logs -f web"
warn "  Logs Certbot : docker compose logs -f certbot"
warn "  Arrêter      : docker compose down"
warn "  Redéployer   : bash $APP_DIR/deploy.sh"
