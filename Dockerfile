FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive

# Install systemd and minimal prerequisites needed to START the installer
# (the installer itself runs apt install for the rest)
RUN apt-get update && apt-get install -y --no-install-recommends \
    systemd \
    systemd-sysv \
    dbus \
    git \
    curl \
    sudo \
    python3 \
    python3-venv \
    python3-pip \
    jq \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Clean up systemd units that don't make sense in a container
RUN rm -f /etc/systemd/system/*.wants/* \
    /lib/systemd/system/multi-user.target.wants/* \
    /etc/systemd/system/multi-user.target.wants/* \
    /lib/systemd/system/local-fs.target.wants/* \
    /lib/systemd/system/sockets.target.wants/*udev* \
    /lib/systemd/system/sockets.target.wants/*initctl* \
    /lib/systemd/system/sysinit.target.wants/systemd-tmpfiles-setup* \
    /lib/systemd/system/systemd-update-utmp*

# Create birdnet user with passwordless sudo (installer requirement)
RUN useradd -m -s /bin/bash birdnet \
    && echo "birdnet ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/birdnet \
    && chmod 0440 /etc/sudoers.d/birdnet

# Install stub timedatectl that outputs Etc/UTC
# (real timedatectl needs running systemd, but installer calls it during build)
# The stub goes in /usr/local/bin/ which takes PATH precedence over /usr/bin/
RUN printf '#!/bin/sh\necho "Etc/UTC"\n' > /usr/local/bin/timedatectl \
    && chmod +x /usr/local/bin/timedatectl

# Switch to birdnet user for installation
# ENV USER is needed because Docker's USER instruction doesn't set $USER,
# and the BirdNET-Pi config template uses $USER to set BIRDNET_USER
USER birdnet
ENV USER=birdnet
ENV HOME=/home/birdnet
WORKDIR /home/birdnet
RUN git clone --depth=1 https://github.com/Nachtzuster/BirdNET-Pi.git

# Run the installer
WORKDIR /home/birdnet/BirdNET-Pi
RUN bash scripts/install_birdnet.sh

# Remove stub, clean up
USER root
RUN rm -f /usr/local/bin/timedatectl

# Expose web UI (Caddy) and Icecast stream
EXPOSE 80 8081

STOPSIGNAL SIGRTMIN+3
VOLUME ["/sys/fs/cgroup"]
CMD ["/sbin/init"]
