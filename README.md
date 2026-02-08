# BirdNET-Pi Docker

Docker image for [BirdNET-Pi](https://github.com/Nachtzuster/BirdNET-Pi)
(the actively maintained fork by Nachtzuster), built daily for arm64
Raspberry Pi deployment.

A GitHub Actions workflow builds the image every day from the upstream
BirdNET-Pi source code, and pushes it to
`ghcr.io/mithro/birdnet-pi` with `:latest` and `:YYYY-MM-DD` date tags.

## Requirements

- Raspberry Pi 4B or any arm64 Linux host (tested on Debian Trixie)
- Docker and Docker Compose
- USB microphone (exposed via `/dev/snd`)

## RPi setup guide

### 1. Install Docker

On Debian-based systems (including Raspberry Pi OS), install Docker from
the distribution repositories:

```bash
sudo apt update
sudo apt install -y docker.io docker-compose
sudo usermod -aG docker $USER
```

Log out and back in for the group change to take effect.

### 2. Configure Docker for systemd containers

BirdNET-Pi uses systemd as PID 1 inside the container. On systems with
cgroup v2 (the default on modern kernels), Docker defaults to private
cgroup namespaces which prevents systemd from starting. You must
configure Docker to use host cgroup namespace mode:

```bash
echo '{"default-cgroupns-mode": "host"}' | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker
```

> **Note:** If you already have a `daemon.json`, merge the
> `"default-cgroupns-mode": "host"` key into your existing configuration
> rather than overwriting it.

> **Why not `cgroupns: host` in docker-compose.yml?** The version of
> docker-compose packaged in Debian (2.26.1) does not support the
> `cgroupns` compose key, so the daemon-level default is required.

### 3. Clone this repo and start the container

```bash
git clone https://github.com/mithro/birdnet-pi-docker.git ~/birdnet
cd ~/birdnet

# Extract the default config file (first time only)
docker compose run --rm --entrypoint cat birdnet-pi \
  /home/birdnet/BirdNET-Pi/birdnet.conf > birdnet.conf

# Start BirdNET-Pi
docker compose up -d
```

The `birdnet.conf` file on the host is bind-mounted into the container,
so your settings survive container recreations (e.g. after image
updates).

Verify the container is running (it should show status `Up`, not
`Exited`):

```bash
docker compose ps
```

### 4. Set up a reverse proxy (optional but recommended)

By default the web UI is only accessible on `localhost:8080`. To expose
it on the network, set up an nginx reverse proxy.

Install nginx:

```bash
sudo apt install -y nginx-light
```

Create a site configuration (replace `HOSTNAME` with your device's
hostname):

```bash
sudo tee /etc/nginx/sites-available/birdnet-pi << 'EOF'
server {
    listen 80;
    server_name HOSTNAME.local
                HOSTNAME.example.com
                ~^.+\.HOSTNAME\.local$
                ~^.+\.HOSTNAME\.example\.com$;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket support (needed for live spectrogram)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}
EOF
```

Enable the site and remove the default:

```bash
sudo ln -sf /etc/nginx/sites-available/birdnet-pi /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

The BirdNET-Pi web UI is now accessible at `http://HOSTNAME/`.

### 5. Configure the ALSA shared-access device

BirdNET-Pi runs two concurrent audio consumers: `arecord` for
recording/analysis and `ffmpeg` for the Icecast livestream. ALSA
hardware devices (`hw:` / `plughw:`) only allow one reader at a time,
so you need an ALSA `dsnoop` plugin to share the microphone.

First, find your USB microphone's ALSA card number:

```bash
docker exec birdnet-pi arecord -l
```

This will output something like:

```
card 3: Device [USB PnP Sound Device], device 0: USB Audio [USB Audio]
```

The included `asoundrc` file configures a `dsnoop` device for card 3.
If your mic is on a different card number, edit `asoundrc` and change
`"hw:3,0"` to match your card.

The `asoundrc` file is bind-mounted into the container at
`/home/birdnet/.asoundrc` (read-only). It defines two virtual devices:

- **`usb_mic_raw`** -- `dsnoop` device that enables shared read access
  to the hardware
- **`usb_mic`** -- `plug` wrapper that handles automatic format
  conversion (e.g. mono mic to stereo when requested by applications)

### 6. Configure BirdNET-Pi

Open the web UI and go to **Tools -> Settings**. Configure at minimum:

- **SITE_NAME** -- a descriptive name for this station
- **LATITUDE** and **LONGITUDE** -- your location (used to filter
  species by range)
- **REC_CARD** -- set to `usb_mic` (the dsnoop device from `asoundrc`)

> **Important:** Do not use `plughw:3,0` or similar hardware device
> names for `REC_CARD`. This will cause "Device or resource busy"
> errors when both recording and livestream try to access the mic
> simultaneously. Always use the `usb_mic` dsnoop device.

After saving settings, the BirdNET-Pi services will restart and begin
recording and analysing audio.

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

## Updating

Pull the latest image and recreate the container:

```bash
cd ~/birdnet
docker compose pull
docker compose up -d
```

Your bird detection data (`./data/`) and configuration (`./birdnet.conf`)
are persisted on the host and survive container recreations.

## Troubleshooting

### Container exits immediately (exit code 255)

Systemd failed to start. Check that:

1. `/etc/docker/daemon.json` contains `{"default-cgroupns-mode": "host"}`
2. Docker was restarted after changing `daemon.json`
3. The container runs with `privileged: true`
4. `/sys/fs/cgroup` is mounted read-write into the container

### No audio / recording fails

Check that:

1. A USB microphone is plugged in and visible with `lsusb`
2. `/dev/snd` devices exist on the host: `ls -la /dev/snd/`
3. `REC_CARD` is set to `usb_mic` (not `default` or a `plughw:` device)
4. The `asoundrc` card number matches your actual mic (`arecord -l`)
5. Test recording from inside the container:
   ```bash
   docker exec birdnet-pi sudo -u birdnet arecord -D usb_mic -d 3 -f S16_LE /tmp/test.wav
   ```

### "Device or resource busy" errors

Both `arecord` (recording) and `ffmpeg` (livestream) need simultaneous
mic access. If `REC_CARD` is set to a raw ALSA device like `plughw:3,0`,
only one process can open it at a time. Set `REC_CARD=usb_mic` to use
the shared dsnoop device configured in `asoundrc`.

### Web UI shows "Welcome to nginx!" instead of BirdNET-Pi

The default nginx site is intercepting requests. Remove it:

```bash
sudo rm /etc/nginx/sites-enabled/default
sudo systemctl reload nginx
```

## Swapping between BirdNET-Go and BirdNET-Pi

If you are running BirdNET-Go on the same host and want to switch:

```bash
# Stop BirdNET-Go (from the BirdNET-Go project directory)
docker compose down

# Start BirdNET-Pi (from this repo's directory)
cd ~/birdnet
docker compose up -d

# To switch back to BirdNET-Go, reverse the process
```

Both projects use `/dev/snd` exclusively, so only one can run at a time.

## License

Apache 2.0 -- see [LICENSE](LICENSE).
