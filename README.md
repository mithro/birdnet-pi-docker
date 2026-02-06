# BirdNET-Pi Docker

Docker image for [BirdNET-Pi](https://github.com/Nachtzuster/BirdNET-Pi)
(the actively maintained fork by Nachtzuster), built daily for arm64
Raspberry Pi deployment.

A GitHub Actions workflow builds the image every day from the upstream
BirdNET-Pi source code, and pushes it to
`ghcr.io/mithro/birdnet-pi` with `:latest` and `:YYYY-MM-DD` date tags.

## Requirements

- Raspberry Pi 4B or any arm64 Linux host
- Docker and Docker Compose
- USB microphone (exposed via `/dev/snd`)

## Quick start

BirdNET-Pi uses systemd inside the container, which requires the Docker
daemon to default to host cgroup namespace mode:

```bash
# Configure Docker for systemd containers (one-time setup)
echo '{"default-cgroupns-mode": "host"}' | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker

# Clone this repo
git clone https://github.com/mithro/birdnet-pi-docker.git
cd birdnet-pi-docker

# Start BirdNET-Pi
docker compose up -d

# Access the web UI
# http://localhost:8080
```

After the first start, configure your location and audio device via the
web UI at **Tools -> Settings**.

## Ports

| Host port | Container port | Service                  |
|-----------|----------------|--------------------------|
| 8080      | 80             | Web UI (Caddy)           |
| 8081      | 8081           | Icecast live audio stream|

Both ports are bound to `127.0.0.1` by default (see `docker-compose.yml`).
To expose them on all interfaces, remove the `127.0.0.1:` prefix from the
port mappings.

## Image tags

| Tag            | Description                          |
|----------------|--------------------------------------|
| `latest`       | Most recent successful build         |
| `YYYY-MM-DD`   | Image built on that specific date    |

To pin to a specific build, edit `docker-compose.yml` and change the
image tag:

```yaml
image: ghcr.io/mithro/birdnet-pi:2025-01-15
```

## Swapping between BirdNET-Go and BirdNET-Pi

If you are running BirdNET-Go on the same host and want to switch:

```bash
# Stop BirdNET-Go (from the BirdNET-Go project directory)
docker compose down

# Start BirdNET-Pi (from this repo's directory)
cd /path/to/birdnet-pi-docker
docker compose up -d

# To switch back to BirdNET-Go, reverse the process
```

## License

Apache 2.0 -- see [LICENSE](LICENSE).
