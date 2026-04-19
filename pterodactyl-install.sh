#!/bin/bash
# ============================================================
#  Pterodactyl Panel + Wings Auto-Installer
#  + Node.js Eggs (14–24)
#  OS: Ubuntu 20.04 / 22.04 / Debian 11 / 12
#  Jalankan sebagai root: bash pterodactyl-install.sh
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PANEL_VERSION="1.11.9"
WINGS_VERSION="1.11.13"
NODE_VERSIONS=(14 16 18 20 22 24)

log()    { echo -e "${GREEN}[+]${NC} $1"; }
warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
error()  { echo -e "${RED}[x]${NC} $1"; exit 1; }
header() { echo -e "\n${CYAN}${BOLD}==> $1${NC}"; }

# ── Root check ────────────────────────────────────────────────
[ "$(id -u)" -ne 0 ] && error "Script harus dijalankan sebagai root!"

# ── Detect arch ───────────────────────────────────────────────
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  WINGS_ARCH="amd64" ;;
    aarch64) WINGS_ARCH="arm64" ;;
    *)       error "Arsitektur tidak didukung: $ARCH" ;;
esac

# ── Collect input ─────────────────────────────────────────────
clear
echo -e "${CYAN}${BOLD}"
echo "  ██████╗ ████████╗███████╗██████╗  ██████╗ "
echo "  ██╔══██╗╚══██╔══╝██╔════╝██╔══██╗██╔═══██╗"
echo "  ██████╔╝   ██║   █████╗  ██████╔╝██║   ██║"
echo "  ██╔═══╝    ██║   ██╔══╝  ██╔══██╗██║   ██║"
echo "  ██║        ██║   ███████╗██║  ██║╚██████╔╝"
echo "  ╚═╝        ╚═╝   ╚══════╝╚═╝  ╚═╝ ╚═════╝ "
echo -e "${NC}"
echo -e "  ${BOLD}Panel v${PANEL_VERSION} + Wings v${WINGS_VERSION} + Node.js Eggs 14-24${NC}"
echo "  ─────────────────────────────────────────────"
echo ""

ADMIN_EMAIL="admin@admin.com"
ADMIN_PASS="admin001"
ADMIN_USER="admin"
ADMIN_FIRST="Admin"
ADMIN_LAST="User"
TZ_INPUT="Asia/Jakarta"
LOCATION_NAME="sgp"
NODE_NAME="node-1"
INSTALL_DOCKER="Y"

read -rp "  Domain panel (contoh: panel.domain.com): " FQDN
read -rp "  Domain Wings/node (contoh: node.domain.com): " WINGS_FQDN
read -rp "  IP publik server ini: " SERVER_IP

DB_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 20)
APP_KEY=$(openssl rand -base64 32)

echo ""
echo -e "  ${CYAN}Ringkasan konfigurasi:${NC}"
echo "  ─────────────────────────────────────────────"
echo "  Domain Panel  : https://${FQDN}"
echo "  Domain Wings  : https://${WINGS_FQDN}"
echo "  Server IP     : ${SERVER_IP}"
echo "  ─────────────────────────────────────────────"
echo ""
warn "Tekan ENTER untuk mulai atau Ctrl+C untuk batal."
read -r

# ── System update ─────────────────────────────────────────────
header "Update sistem"
apt-get update -y && apt-get upgrade -y
apt-get install -y curl wget git unzip tar software-properties-common \
    apt-transport-https ca-certificates gnupg lsb-release sudo cron \
    openssl python3

# ── Docker ────────────────────────────────────────────────────
if [[ "${INSTALL_DOCKER,,}" == "y" ]]; then
    header "Install Docker"
    if ! command -v docker &>/dev/null; then
        curl -sSL https://get.docker.com | bash
        systemctl enable --now docker
        log "Docker terinstall"
    else
        log "Docker sudah terinstall, skip."
    fi
fi

# ── PHP 8.1 ───────────────────────────────────────────────────
header "Install PHP 8.1"
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php 2>/dev/null || true
apt-get update -y
apt-get install -y php8.1 php8.1-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip,intl}
log "PHP $(php -r 'echo PHP_VERSION;') terinstall"

# ── MariaDB ───────────────────────────────────────────────────
header "Install MariaDB"
apt-get install -y mariadb-server mariadb-client
systemctl enable --now mariadb

mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS panel CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1';
FLUSH PRIVILEGES;
EOF
log "Database 'panel' dibuat"

# ── Redis ─────────────────────────────────────────────────────
header "Install Redis"
apt-get install -y redis-server
systemctl enable --now redis-server

# ── Nginx ─────────────────────────────────────────────────────
header "Install Nginx"
apt-get install -y nginx
systemctl enable --now nginx

# ── Composer ──────────────────────────────────────────────────
header "Install Composer"
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
log "Composer terinstall"

# ── Download Panel ────────────────────────────────────────────
header "Download Pterodactyl Panel v${PANEL_VERSION}"
mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl
curl -sSLo panel.tar.gz "https://github.com/pterodactyl/panel/releases/download/v${PANEL_VERSION}/panel.tar.gz"
tar -xzvf panel.tar.gz --strip-components=1
rm panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/
log "Panel diekstrak ke /var/www/pterodactyl"

# ── Configure .env ────────────────────────────────────────────
header "Konfigurasi .env"
cp .env.example .env
sed -i "s|APP_URL=.*|APP_URL=https://${FQDN}|g"         .env
sed -i "s|APP_TIMEZONE=.*|APP_TIMEZONE=${TZ_INPUT}|g"   .env
sed -i "s|APP_KEY=.*|APP_KEY=base64:${APP_KEY}|g"       .env
sed -i "s|DB_HOST=.*|DB_HOST=127.0.0.1|g"               .env
sed -i "s|DB_DATABASE=.*|DB_DATABASE=panel|g"           .env
sed -i "s|DB_USERNAME=.*|DB_USERNAME=pterodactyl|g"     .env
sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASS}|g"      .env
sed -i "s|CACHE_DRIVER=.*|CACHE_DRIVER=redis|g"         .env
sed -i "s|SESSION_DRIVER=.*|SESSION_DRIVER=redis|g"     .env
sed -i "s|QUEUE_CONNECTION=.*|QUEUE_CONNECTION=redis|g" .env
sed -i "s|MAIL_FROM=.*|MAIL_FROM=${ADMIN_EMAIL}|g"      .env

# ── Install dependencies ──────────────────────────────────────
header "Install dependencies Composer"
composer install --no-dev --optimize-autoloader --no-interaction

# ── Artisan setup ─────────────────────────────────────────────
header "Setup Laravel"
php artisan key:generate --force
php artisan migrate --seed --force
php artisan p:environment:setup \
    --author="${ADMIN_EMAIL}" \
    --url="https://${FQDN}" \
    --timezone="${TZ_INPUT}" \
    --cache=redis \
    --session=redis \
    --queue=redis \
    --disable-settings-ui=false \
    --force
php artisan p:environment:database \
    --host=127.0.0.1 \
    --port=3306 \
    --database=panel \
    --username=pterodactyl \
    --password="${DB_PASS}" \
    --force

# ── Create admin user ─────────────────────────────────────────
header "Buat akun admin"
php artisan p:user:make \
    --email="${ADMIN_EMAIL}" \
    --username="${ADMIN_USER}" \
    --name-first="${ADMIN_FIRST}" \
    --name-last="${ADMIN_LAST}" \
    --password="${ADMIN_PASS}" \
    --admin=1

# ── Permissions ───────────────────────────────────────────────
chown -R www-data:www-data /var/www/pterodactyl

# ── Queue worker ─────────────────────────────────────────────
header "Setup queue worker"
cat > /etc/systemd/system/pteroq.service <<'SYSTEMD'
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
SYSTEMD

systemctl daemon-reload
systemctl enable --now pteroq

# ── Cron ──────────────────────────────────────────────────────
(crontab -l 2>/dev/null; echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | crontab -

# ── SSL (Panel + Wings) ───────────────────────────────────────
header "Install SSL via Let's Encrypt"
apt-get install -y certbot python3-certbot-nginx

# Stop nginx sementara agar certbot standalone bisa bind port 80
systemctl stop nginx

certbot certonly --standalone -d "${FQDN}" \
    --email "${ADMIN_EMAIL}" --agree-tos --no-eff-email --non-interactive \
    || warn "SSL panel gagal. Pastikan ${FQDN} sudah pointed ke server ini."

certbot certonly --standalone -d "${WINGS_FQDN}" \
    --email "${ADMIN_EMAIL}" --agree-tos --no-eff-email --non-interactive \
    || warn "SSL wings gagal. Pastikan ${WINGS_FQDN} sudah pointed ke server ini."

systemctl start nginx

# ── Nginx: Panel ─────────────────────────────────────────────
header "Konfigurasi Nginx Panel"
cat > /etc/nginx/sites-available/pterodactyl <<NGINX
server {
    listen 80;
    server_name ${FQDN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${FQDN};

    root /var/www/pterodactyl/public;
    index index.php;

    access_log /var/log/nginx/pterodactyl.access.log;
    error_log  /var/log/nginx/pterodactyl.error.log error;

    client_max_body_size 100m;
    client_body_timeout 120s;

    ssl_certificate     /etc/letsencrypt/live/${FQDN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${FQDN}/privkey.pem;
    ssl_session_cache   shared:SSL:10m;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    add_header X-Download-Options noopen;
    add_header X-Permitted-Cross-Domain-Policies none;
    add_header Referrer-Policy same-origin;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht { deny all; }
}
NGINX

# ── Nginx: Wings ─────────────────────────────────────────────
header "Konfigurasi Nginx Wings"
cat > /etc/nginx/sites-available/wings <<NGINX
server {
    listen 80;
    server_name ${WINGS_FQDN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${WINGS_FQDN};

    ssl_certificate     /etc/letsencrypt/live/${WINGS_FQDN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${WINGS_FQDN}/privkey.pem;
    ssl_session_cache   shared:SSL:10m;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    location / {
        proxy_pass         http://127.0.0.1:8080;
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_buffering    off;
    }
}
NGINX

ln -sf /etc/nginx/sites-available/pterodactyl /etc/nginx/sites-enabled/pterodactyl
ln -sf /etc/nginx/sites-available/wings       /etc/nginx/sites-enabled/wings
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl reload nginx

# ════════════════════════════════════════════════════════════════
#  NODE.JS EGGS
# ════════════════════════════════════════════════════════════════
header "Generate Node.js Eggs (14-24)"

EGG_DIR="/var/www/pterodactyl/resources/eggs/nodejs"
mkdir -p "${EGG_DIR}"

install_nodejs_egg() {
    local VER=$1
    local FILE="${EGG_DIR}/egg-node${VER}.json"
    cat > "${FILE}" <<EGGJSON
{
    "\$schema": "https://pterodactyl.io/schema/egg.json",
    "meta": { "version": "PTDL_v2", "update_url": null },
    "exported_at": "$(date -u +%Y-%m-%dT%H:%M:%S+00:00)",
    "name": "Node.js ${VER}",
    "author": "support@pterodactyl.io",
    "uuid": "$(cat /proc/sys/kernel/random/uuid)",
    "description": "Node.js ${VER} runtime environment for JavaScript applications.",
    "features": ["pid_limit"],
    "docker_images": {
        "ghcr.io/pterodactyl/yolks:nodejs_${VER}": "ghcr.io/pterodactyl/yolks:nodejs_${VER}"
    },
    "file_denylist": [],
    "startup": "if [[ -d .git ]] && [[ \$AUTO_UPDATE == \"1\" ]]; then git pull; fi; if [[ ! -z \${NODE_PACKAGES} ]]; then npm install \${NODE_PACKAGES}; fi; if [ -f /home/container/package.json ]; then npm install; fi; \${STARTUP_CMD}",
    "config": {
        "files": "{}",
        "startup": "{\"done\": \"Started\"}",
        "logs": "{}",
        "stop": "^C"
    },
    "scripts": {
        "installation": {
            "script": "#!/bin/bash\r\napt-get update -y\r\napt-get install -y git curl\r\nmkdir -p /mnt/server\r\ncd /mnt/server\r\nif [ ! -z \"\${GIT_ADDRESS}\" ]; then git clone \"\${GIT_ADDRESS}\" .; fi\r\nif [ -f /mnt/server/package.json ]; then npm install; fi",
            "container": "ghcr.io/pterodactyl/installers:alpine",
            "entrypoint": "bash"
        }
    },
    "variables": [
        {
            "name": "Startup Command",
            "description": "Command to run your app (e.g. node index.js)",
            "env_variable": "STARTUP_CMD",
            "default_value": "node index.js",
            "user_viewable": true,
            "user_editable": true,
            "rules": "required|string|max:256",
            "field_type": "text"
        },
        {
            "name": "Git Repository",
            "description": "URL git repo (kosongkan jika tidak pakai)",
            "env_variable": "GIT_ADDRESS",
            "default_value": "",
            "user_viewable": true,
            "user_editable": true,
            "rules": "nullable|string|max:256",
            "field_type": "text"
        },
        {
            "name": "Auto Update",
            "description": "Auto git pull saat start (1=ya, 0=tidak)",
            "env_variable": "AUTO_UPDATE",
            "default_value": "0",
            "user_viewable": true,
            "user_editable": true,
            "rules": "required|boolean",
            "field_type": "text"
        },
        {
            "name": "npm Packages",
            "description": "Package npm tambahan (pisah spasi)",
            "env_variable": "NODE_PACKAGES",
            "default_value": "",
            "user_viewable": true,
            "user_editable": true,
            "rules": "nullable|string|max:512",
            "field_type": "text"
        }
    ]
}
EGGJSON
    log "Egg Node.js ${VER} dibuat"
}

for VER in "${NODE_VERSIONS[@]}"; do
    install_nodejs_egg "${VER}"
done

header "Import eggs ke database"
cd /var/www/pterodactyl
php artisan tinker --no-interaction <<'TINKER'
use Pterodactyl\Models\Nest;
use Pterodactyl\Services\Eggs\Sharing\EggImportService;

$nest = Nest::firstOrCreate(
    ['name' => 'Custom'],
    ['author' => 'admin@example.com', 'description' => 'Custom eggs']
);

$service = app(EggImportService::class);
$dir = base_path('resources/eggs/nodejs');

foreach (glob($dir . '/*.json') as $file) {
    try {
        $service->handle(new \Illuminate\Http\UploadedFile(
            $file, basename($file), 'application/json', null, true
        ), $nest->id);
        echo "Imported: " . basename($file) . "\n";
    } catch (\Exception $e) {
        echo "Skip: " . basename($file) . " - " . $e->getMessage() . "\n";
    }
}
TINKER

# ════════════════════════════════════════════════════════════════
#  INSTALL WINGS
# ════════════════════════════════════════════════════════════════
header "Install Wings v${WINGS_VERSION} (${WINGS_ARCH})"

mkdir -p /etc/pterodactyl
curl -sSLo /usr/local/bin/wings \
    "https://github.com/pterodactyl/wings/releases/download/v${WINGS_VERSION}/wings_linux_${WINGS_ARCH}"
chmod +x /usr/local/bin/wings
log "Wings binary terinstall"

# ── Buat Location & Node via API ─────────────────────────────
header "Buat Location & Node via Panel API"

# Generate API key
API_KEY=$(cd /var/www/pterodactyl && php artisan tinker --no-interaction 2>/dev/null <<APIKEY | tail -1
use Pterodactyl\Models\User;
use Pterodactyl\Models\ApiKey;
\$user = User::where('root_admin', 1)->first();
\$identifier = substr(str_shuffle('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'), 0, 16);
\$token = substr(str_shuffle('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'), 0, 32);
ApiKey::create([
    'user_id' => \$user->id,
    'key_type' => ApiKey::TYPE_APPLICATION,
    'identifier' => \$identifier,
    'token' => encrypt(\$token),
    'memo' => 'auto-installer',
    'allowed_ips' => [],
    'r_servers' => 1, 'r_nodes' => 3, 'r_allocations' => 3,
    'r_users' => 1, 'r_eggs' => 1, 'r_database_hosts' => 0,
    'r_server_databases' => 0, 'r_locations' => 3,
]);
echo \$identifier.\$token;
APIKEY
)

sleep 2

# Buat Location
LOC_JSON=$(curl -s -X POST "https://${FQDN}/api/application/locations" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "{\"short\":\"id-1\",\"long\":\"${LOCATION_NAME}\"}" 2>/dev/null || echo "{}")

LOCATION_ID=$(echo "$LOC_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('attributes',{}).get('id',1))" 2>/dev/null || echo "1")
log "Location dibuat, ID: ${LOCATION_ID}"

# Buat Node
NODE_JSON=$(curl -s -X POST "https://${FQDN}/api/application/nodes" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "{
        \"name\": \"${NODE_NAME}\",
        \"location_id\": ${LOCATION_ID},
        \"fqdn\": \"${WINGS_FQDN}\",
        \"scheme\": \"https\",
        \"memory\": 8192,
        \"memory_overallocate\": 0,
        \"disk\": 50000,
        \"disk_overallocate\": 0,
        \"upload_size\": 100,
        \"daemon_sftp\": 2022,
        \"daemon_listen\": 8080
    }" 2>/dev/null || echo "{}")

NODE_ID=$(echo "$NODE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('attributes',{}).get('id',''))" 2>/dev/null || echo "")

CONFIG_OK=false

if [ -n "$NODE_ID" ] && [ "$NODE_ID" != "None" ] && [ "$NODE_ID" != "" ]; then
    log "Node '${NODE_NAME}' dibuat, ID: ${NODE_ID}"

    # Tambah allocations
    curl -s -X POST "https://${FQDN}/api/application/nodes/${NODE_ID}/allocations" \
        -H "Authorization: Bearer ${API_KEY}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "{\"ip\":\"${SERVER_IP}\",\"ports\":[\"25565-25600\",\"27015-27030\",\"2022\"]}" \
        > /dev/null 2>&1 && log "Allocations ditambahkan" || warn "Gagal tambah allocation, bisa manual di panel."

    # Ambil config Wings
    sleep 1
    WINGS_CONFIG=$(curl -s "https://${FQDN}/api/application/nodes/${NODE_ID}/configuration" \
        -H "Authorization: Bearer ${API_KEY}" \
        -H "Accept: application/json" 2>/dev/null || echo "")

    if [ -n "$WINGS_CONFIG" ] && echo "$WINGS_CONFIG" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        echo "$WINGS_CONFIG" > /etc/pterodactyl/config.yml
        log "config.yml Wings tersimpan di /etc/pterodactyl/config.yml"
        CONFIG_OK=true
    else
        warn "Gagal ambil config Wings otomatis."
    fi
else
    warn "Gagal buat node via API. Buat manual di panel."
fi

# ── Wings systemd ─────────────────────────────────────────────
header "Setup Wings service"
cat > /etc/systemd/system/wings.service <<'WINGS_SVC'
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service network.target
Requires=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
WINGS_SVC

systemctl daemon-reload
systemctl enable wings

if [ "$CONFIG_OK" = true ]; then
    systemctl start wings
    log "Wings service berjalan"
else
    warn "Wings service TIDAK distart — config.yml belum ada."
fi

# ── Final ─────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║             INSTALASI PTERODACTYL SELESAI!                    ║"
echo "╠════════════════════════════════════════════════════════════════╣"
printf "║  Panel URL   : https://%-40s║\n" "${FQDN}"
printf "║  Wings URL   : https://%-40s║\n" "${WINGS_FQDN}"
printf "║  Email       : %-47s║\n" "${ADMIN_EMAIL}"
printf "║  Username    : %-47s║\n" "${ADMIN_USER}"
echo "║  Password    : (yang kamu input tadi)                         ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║  Eggs Node.js  : 14 / 16 / 18 / 20 / 22 / 24                ║"
printf "║  Nest          : %-45s║\n" "Custom"
printf "║  Location      : %-45s║\n" "${LOCATION_NAME}"
printf "║  Node          : %-45s║\n" "${NODE_NAME}"
echo "╠════════════════════════════════════════════════════════════════╣"
if [ "$CONFIG_OK" = true ]; then
echo "║  Wings  : [OK] Running                                        ║"
else
echo "║  Wings  : [!!] Perlu config manual — baca instruksi bawah    ║"
fi
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║  JIKA WINGS BELUM RUNNING:                                    ║"
echo "║  1. Login panel > Admin > Nodes > pilih node kamu            ║"
echo "║  2. Tab 'Configuration' > salin isinya                       ║"
echo "║  3. Paste ke /etc/pterodactyl/config.yml                     ║"
echo "║  4. systemctl start wings                                     ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
warn "Simpan info di atas sekarang!"
