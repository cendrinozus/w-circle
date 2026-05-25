FROM nginx:alpine

COPY remixed-daaf7b8c.html /usr/share/nginx/html/index.html

# La config Nginx est montée via volume (docker-compose.yml)
# afin que deploy.sh puisse basculer HTTP → HTTPS sans rebuild

EXPOSE 80 443
