#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="./deploy_$(date +%Y%m%d_%H%M%S).log"

log()    { echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"; }
error()  { log "ERROR: $*"; exit 1; }

read -p "Git Repository URL: " GIT_REPO
[ -z "$GIT_REPO" ] && error "Repository URL required"
read -sp "Personal Access Token: " GIT_TOKEN; echo
[ -z "$GIT_TOKEN" ] && error "Token required"
read -p "Branch [main]: " GIT_BRANCH
GIT_BRANCH="${GIT_BRANCH:-main}"
read -p "SSH Username: " SSH_USER
[ -z "$SSH_USER" ] && error "SSH username required"
read -p "Server IP: " SERVER_IP
[ -z "$SERVER_IP" ] && error "Server IP required"
read -p "SSH Key Path [~/.ssh/id_rsa]: " SSH_KEY
SSH_KEY="${SSH_KEY:-~/.ssh/id_rsa}"; SSH_KEY="${SSH_KEY/#\~/$HOME}"
[ ! -f "$SSH_KEY" ] && error "SSH key not found: $SSH_KEY"
read -p "Application Port: " APP_PORT
[[ ! "$APP_PORT" =~ ^[0-9]+$ ]] && error "Invalid port number"

PROJECT_NAME=$(basename "$GIT_REPO" .git)
PROJECT_DIR="./$PROJECT_NAME"
REMOTE_DIR="/opt/deployments/$PROJECT_NAME"

AUTH_URL="${GIT_REPO/https:\/\//https:\/\/$GIT_TOKEN@}"

if [ -d "$PROJECT_DIR/.git" ]; then
    cd "$PROJECT_DIR"
    git fetch origin && git checkout "$GIT_BRANCH" && git pull origin "$GIT_BRANCH" || error "Failed to update repo"
    cd ..
    log "Repo updated"
else
    git clone -b "$GIT_BRANCH" "$AUTH_URL" "$PROJECT_DIR" || error "Failed to clone repo"
    log "Repo cloned"
fi

if [ -f "$PROJECT_DIR/docker-compose.yml" ] || [ -f "$PROJECT_DIR/docker-compose.yaml" ]; then
    DEPLOY_MODE="compose"
elif [ -f "$PROJECT_DIR/Dockerfile" ]; then
    DEPLOY_MODE="dockerfile"
else
    error "No Dockerfile or docker-compose.yml found"
fi

ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" "echo Connected" &>/dev/null \
    || error "SSH connection failed"

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" bash << EOF
set -e
sudo apt-get update -y
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sudo sh /tmp/get-docker.sh
    sudo usermod -aG docker \$USER
    rm /tmp/get-docker.sh
fi
if ! command -v docker-compose &>/dev/null; then
    sudo apt-get install -y docker-compose-plugin || \
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose || true
fi
if ! command -v nginx &>/dev/null; then
    sudo apt-get install -y nginx
fi
sudo systemctl enable docker nginx
sudo systemctl start docker nginx
sudo mkdir -p $REMOTE_DIR
sudo chown -R \$USER:\$USER $REMOTE_DIR
EOF

if command -v rsync &>/dev/null; then
    rsync -avz --delete -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
        --exclude '.git' --exclude 'node_modules' --exclude '__pycache__' \
        "$PROJECT_DIR/" "$SSH_USER@$SERVER_IP:$REMOTE_DIR/"
else
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -r "$PROJECT_DIR/"* "$SSH_USER@$SERVER_IP:$REMOTE_DIR/"
fi

if [ "$DEPLOY_MODE" = "compose" ]; then
    ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" "
        cd $REMOTE_DIR
        docker-compose down 2>/dev/null || docker compose down 2>/dev/null || true
        docker-compose build 2>&1 || docker compose build 2>&1
        docker-compose up -d 2>&1 || docker compose up -d 2>&1
    "
else
    ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" "
        cd $REMOTE_DIR
        docker ps -a --filter name=$PROJECT_NAME -q | xargs -r docker rm -f 2>/dev/null || true
        docker build -t $PROJECT_NAME:latest .
        docker run -d --name $PROJECT_NAME -p $APP_PORT:$APP_PORT --restart unless-stopped $PROJECT_NAME:latest
    "
fi

ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" bash << EOF
set -e
sudo tee /etc/nginx/sites-available/$PROJECT_NAME > /dev/null << NGINX
server {
    listen 80;
    server_name $SERVER_IP _;
    location / { proxy_pass http://localhost:$APP_PORT; proxy_set_header Host \$host; }
}
NGINX
sudo ln -sf /etc/nginx/sites-available/$PROJECT_NAME /etc/nginx/sites-enabled/$PROJECT_NAME
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
EOF

ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" "docker ps --filter name=$PROJECT_NAME"
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" "curl -s -o /dev/null -w 'App: %{http_code}\\n' http://localhost:$APP_PORT || true"
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" "curl -s -o /dev/null -w 'Nginx: %{http_code}\\n' http://localhost:80 || true"

log "Deployment complete. App at http://$SERVER_IP"
