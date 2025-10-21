# Automated Docker Deployment Script


## Features

- **Clones or updates your Git repository automatically**
- **Supports both single-Dockerfile and docker-compose projects**
- **Installs Docker, Docker Compose, and Nginx if missing**
- **Deploys containers and sets up Nginx as a reverse proxy**
- **Works with private repositories using a GitHub Personal Access Token**
- **Logs all operations with timestamps for easy debugging**

***

## Prerequisites

- **Local machine:** `bash`, `ssh`, and (optional) `rsync` installed
- **Remote server:** Ubuntu (or Debian-based), accessible via SSH with key authentication

***

## Usage

1. **Clone this repository** (or copy the script into your project directory).
2. **Make the script executable:**

```bash
chmod +x deploy.sh
```

3. **Run the script:**

```bash
./deploy.sh
```

4. **Follow the prompts** to enter:
    - Git repository URL
    - GitHub Personal Access Token (for private repos)
    - Branch name (default: `main`)
    - SSH username and server IP
    - SSH private key path (default: `~/.ssh/id_rsa`)
    - Application port number

Deployment logs are saved in `deploy_YYYYMMDD_HHMMSS.log` for troubleshooting.

***

## How It Works

1. **Fetches source code** (clone or update).
2. **Detects deployment mode** based on `Dockerfile` or `docker-compose.yml`.
3. **Connects to server** via SSH and installs Docker, Docker Compose, and Nginx if needed.
4. **Transfers code** using `rsync` (or `scp` as a fallback).
5. **Builds and runs containers**.
6. **Configures and reloads Nginx** as a reverse proxy to your application.
7. **Runs health checks** to verify the deployment.

***

## Troubleshooting

- **Check the log file** for errors:

```bash
ls deploy_*.log && tail -n 50 deploy_*.log
```

- **SSH key permissions:**

```bash
chmod 600 ~/.ssh/id_rsa
```

- **Firewall:** Ensure port 80 (HTTP) and your application port are open on the server.
- **Docker group changes:** After installing Docker, log out and back in to apply group membership changes.

***

## Customization

Feel free to adapt the script for your CI/CD pipeline or add environment-specific configurations as needed.

***

## License

MIT License. See `LICENSE` for more details.

***
