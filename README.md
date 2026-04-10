# ns-usbloader-docker

## A docker container for ns-usbloader

![NS-USBLoader Docker](https://img.shields.io/github/actions/workflow/status/TimoVerbrugghe/ns-usbloader-docker/ns-usbloader-docker.yaml?branch=main&label=ns-usbloader-docker&logo=githubactions&logoColor=white)

This repository contains a Dockerfile and example Docker Compose configuration to run [ns-usbloader](https://github.com/developersu/ns-usbloader) through a web browser using noVNC.

## Prerequisites

Before running the Docker container, make sure you have the following installed:

- Docker
- Docker Compose

## Usage

1. Clone this repository:

    ```shell
    git clone https://github.com/your-username/ns-usbloader.git
    ```

2. Build the Docker image:

    ```shell
    docker build -t ns-usbloader .
    ```

3. Run the Docker container:

    ```shell
    docker run -d --platform linux/amd64 -p 8080:8080 -p 6042:6042 -v /path/to/nsp/files:/nsp -v /path/to/config:/home/nsusbloader/.java/.userPrefs/NS-USBloader ghcr.io/timoverbrugghe/ns-usbloader
    ```

4. Access ns-usbloader in your web browser:

    ```text
    http://localhost:8080
    ```

## Docker Compose

The repository includes a default Compose file at `docker-compose.yaml` in the project root.

The Compose file uses the latest public release image from GitHub Container Registry and named Docker volumes for NSP data and preferences. Run the following command to start the container:

```shell
docker-compose up -d
```

You can access ns-usbloader in your web browser at `http://localhost:8080`.

On Apple Silicon (ARM64), the compose file explicitly uses `platform: linux/amd64` to avoid JavaFX native library compatibility issues in ns-usbloader.

## Optional runtime hardening

The default `docker-compose.yaml` already includes these runtime hardening settings:

```shell
cap_drop:
  - ALL
security_opt:
  - no-new-privileges:true
```

## Configure ns-usbloader

Before installing games using ns-usbloader, you need to configure the port and IP settings. Follow these steps:

1. Open ns-usbloader in your web browser by accessing `http://localhost:8080`.

2. Navigate to the settings page.

3. Set the port to `6042` and the IP to your host IP address.

4. Save the settings.

Now you can proceed with installing games using ns-usbloader.

## USB Device Support

To use ns-usbloader container with Nintendo Switch USB connectivity (normal mode or RCM), you need to configure udev rules on your **host system** (not in the container).

### Setting up udev rules

Run these commands **once on your machine** (or on each Kubernetes node for cluster deployment):

```bash
# Nintendo Switch normal mode (Goldleaf)
sudo tee /etc/udev/rules.d/99-NS.rules > /dev/null <<EOF
SUBSYSTEM=="usb", ATTRS{idVendor}=="057e", ATTRS{idProduct}=="3000", MODE="0666"
EOF

# RCM/Recovery mode (payload injection)
sudo tee /etc/udev/rules.d/99-NS-RCM.rules > /dev/null <<EOF
SUBSYSTEM=="usb", ATTRS{idVendor}=="0955", ATTRS{idProduct}=="7321", MODE="0666"
EOF

# Reload and apply rules
sudo udevadm control --reload-rules && sudo udevadm trigger
```

### Running with USB support

After applying the udev rules, run the container with USB bus access:

**Docker:**

```bash
docker run -it --rm -p 8080:8080 -p 6042:6042 \
  -v /path/to/nsp/files:/nsp \
  --device /dev/bus/usb \
  ghcr.io/timoverbrugghe/ns-usbloader
```

**Docker Compose:**
Update `docker-compose.yaml` to include USB device access:

```yaml
services:
  ns-usbloader:
    devices:
      - /dev/bus/usb:/dev/bus/usb
```

**Podman:**

```bash
podman run -it --rm -p 8080:8080 -p 6042:6042 \
  -v /path/to/nsp/files:/nsp \
  --device /dev/bus/usb \
  ghcr.io/timoverbrugghe/ns-usbloader
```

**Kubernetes:**
Update your Deployment manifest to mount the USB bus:

```yaml
containers:
  - name: ns-usbloader
    volumeMounts:
      - name: usb-bus
        mountPath: /dev/bus/usb
volumes:
  - name: usb-bus
    hostPath:
      path: /dev/bus/usb
      type: Directory
```

### Note

The container runs as a non-root user (UID 3000) for security. The udev rules with `MODE="0666"` allow the container process to access USB devices without requiring root privilege elevation.
