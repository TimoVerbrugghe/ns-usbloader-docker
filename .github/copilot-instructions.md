---
applyTo: '**'
---

# NS-USBLoader Docker Container - Copilot Instructions

## Project Overview

This repository provides a production-ready Docker container for [ns-usbloader](https://github.com/developersu/ns-usbloader) v7.3, a Nintendo Switch USB loader and network installer. The container runs ns-usbloader with a graphical interface (Openbox window manager) accessible via noVNC web interface, plus a gRPC file server for network transfers.

**Contact & Repo**: Owner: @TimoVerbrugghe | GitHub: TimoVerbrugghe/ns-usbloader-docker

---

## Architecture & Components

### Core Technologies
- **Base Image**: Debian bookworm-slim (amd64)
- **Java Runtime**: OpenJDK 17 + OpenFX (JavaFX)
- **Display**: Xvfb (X virtual framebuffer) + Openbox (window manager)
- **VNC**: x11vnc + noVNC (web proxy)
- **Process Manager**: Supervisor (supervisord)
- **NS-USBLoader**: JAR v7.3 from official GitHub releases

### Services (managed by supervisord)
1. **X11** (Xvfb) - Virtual display server on :0 (1024x768x24)
2. **Openbox** - Window manager with fullscreen configuration
3. **x11vnc** - VNC server on port 5900
4. **noVNC** - Web-based VNC proxy on port 8080
5. **ns-usbloader** - Main application JAR, listening on port 6042 (gRPC) and VNC

### Key Ports
- **8080** → noVNC web interface
- **5900** → x11vnc VNC backend
- **6042** → ns-usbloader grpc file server

### Key Volumes
- `/nsp` - Game files (NSP/NSZ/XCI files for installation)
- `/home/nsusbloader/.java/.userPrefs/NS-USBloader` - Application preferences

---

## User Model & Security

### Non-Root Execution (Critical)
- **Default UID/GID**: 1000 (build-time configurable via ARG UID/ARG GID)
- **Kubernetes Runtime**: UID 3000, GID 3000 (via securityContext.runAsUser)
- **Security Posture**: 
  - Runs as non-root user `nsusbloader`
  - Capabilities dropped (ALL)
  - No privilege escalation allowed (no-new-privileges=true)
  - read-only filesystem support possible (not implemented)

### Build-Time User Configuration
```dockerfile
ARG UID=1000
ARG GID=1000
```
Allows building with custom IDs: `docker build --build-arg UID=3000 --build-arg GID=3000 .`

### Runtime Permissions
- App home directory (`/home/nsusbloader`) has `chmod -R a+rwX` applied
- Allows any UID (including 3000) to read/write cache, prefs, logs
- No `chown` required at runtime

---

## Environment Configuration (Critical for Functionality)

### Environment Variables Set in Dockerfile
```dockerfile
ENV HOME=$APP_HOME                                    # /home/nsusbloader
ENV XDG_CACHE_HOME=$APP_HOME/.cache                  # For fontconfig, openjfx caching
ENV JAVA_TOOL_OPTIONS="-Duser.home=$APP_HOME -Djava.util.prefs.userRoot=$APP_HOME"
```

### Why These Are Critical

1. **HOME=$APP_HOME** (not /root, not /tmp)
   - Openbox looks for rc.xml at `$HOME/.config/openbox/rc.xml`
   - Without this, fullscreen config fails when running as UID 3000
   - UID 3000 cannot write to /root → permission denied

2. **XDG_CACHE_HOME=$APP_HOME/.cache**
   - Fontconfig tries /root/.fontconfig if not set → fails for UID 3000
   - OpenJFX cache defaults to /tmp/.javafx → contention, permission issues
   - Explicit path ensures writable cache per user

3. **JAVA_TOOL_OPTIONS with userRoot=$APP_HOME**
   - Java preferences (prefs.xml) stored under `.java/.userPrefs/NS-USBloader/`
   - Original setting `userRoot=$APP_HOME/.java/.userPrefs` caused double-nesting bug:
     - App appended `.java/.userPrefs/NS-USBloader` to the userRoot path
     - Resulted in: `.java/.userPrefs/.java/.userPrefs/NS-USBloader/prefs.xml`
   - **FIX**: Set `userRoot=$APP_HOME` only (app appends its own subpath)

### Prerequisites Directory Structure
Created at build time to ensure writable paths exist before app starts:
```dockerfile
mkdir -p $APP_HOME/.cache/fontconfig \
         $APP_HOME/.openjfx/cache \
         $APP_HOME/.config/openbox \
         $APP_HOME/.java/.userPrefs/NS-USBloader
```

---

## Configuration Files (app/config/)

### supervisord.conf
**Purpose**: Process supervisor configuration for all services
- **Logs**: `/tmp/supervisord.log` (writable by all UIDs)
- **PID**: `/tmp/supervisord.pid` (writable by all UIDs)
- **Services**: X11, openbox, x11vnc, novnc, nsusbloader (priority 0-4)
- **Key Setting**: `nodaemon=true` (foreground mode, required for containers)
- **Output**: All stdout/stderr to `/dev/fd/1` (container logging)

### rc.xml
**Purpose**: Openbox window manager configuration
- **Fullscreen**: Set to `yes` (removes decoration, maximizes window)
- **Position**: (0,0) - top-left corner
- **Scope**: All applications (`<application class="*">`)

**Testing**: If fullscreen isn't applied, check:
1. Is HOME set correctly? `echo $HOME` in pod
2. Does file exist? `cat /home/nsusbloader/.config/openbox/rc.xml`
3. Are Openbox logs showing errors? Check supervisord.log

### prefs.xml
**Purpose**: NS-USBLoader application preferences (Java serialized)
**Key Settings** (edit as needed):
```xml
HOSTIP=10.10.10.7         # PC IP address (host running the games)
HOSTPORT=6042             # gRPC port ns-usbloader listens on
NSIP=10.10.10.156         # Nintendo Switch IP (for network mode)
THEME=/res/app_dark.css   # Dark theme
EXPERTMODE=true           # Enable advanced options
NETUSB=NET                # Default to network mode
```

**Deployment Strategies**:
1. **Baked into image** (current): Copied during build, persistent across restarts
2. **Kubernetes ConfigMap**:
   - Mount as read-only subPath: `.java/.userPrefs/NS-USBloader/prefs.xml`
   - App can read but cannot mutate (ConfigMap is read-only)
   - Consider: initContainer + writable volume for persistence if mutations needed

**Java Prefs Gotchas**:
- Prefs stored in binary XML format (not human-readable after app first writes)
- Lock file `.java/.userPrefs/NS-USBloader/.lock` may prevent concurrent access
- If app can't find prefs, check `JAVA_TOOL_OPTIONS userRoot` setting

---

## Kubernetes Deployment Specifics

### Security Context (Required for non-root)
```yaml
securityContext:
  runAsUser: 3000
  runAsGroup: 3000
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
```

### Volumes (Standard Setup)
```yaml
volumeMounts:
  - name: nsp-games
    mountPath: /nsp
  - name: ns-prefs
    mountPath: /home/nsusbloader/.java/.userPrefs/NS-USBloader
    subPath: NS-USBloader

volumes:
  - name: nsp-games
    persistentVolumeClaim:
      claimName: games-roms-pvc
  - name: ns-prefs
    configMap:
      name: ns-usbloader-config
      items:
        - key: prefs.xml
          path: prefs.xml
```

### Startup/Readiness/Liveness Probes
These depend on noVNC being up; use HTTP probes on :8080.

**Example (readiness)**:
```yaml
readinessProbe:
  httpGet:
    path: /
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 10
```

### Known Kubernetes Issues & Solutions

**Issue**: Container shows error "You have been entered as: ?" in ns-usbloader
- **Cause**: Java can't write udev rules or access USB devices (udevd not running in container)
- **Solution**: Apply udev rules on host nodes, see [USB Device Support](#usb-device-support) section

**Issue**: rc.xml not applied (no fullscreen)
- **Cause**: OLD version had HOME=/root; see [Environment Configuration](#environment-configuration-critical-for-functionality)
- **Solution**: Ensure Dockerfile has `ENV HOME=$APP_HOME`

**Issue**: prefs.xml not loaded (empty preferences)
- **Cause**: Java prefs path resolution bug (nested `.java/.userPrefs` subfolder)
- **Solution**: Ensure `JAVA_TOOL_OPTIONS` has `userRoot=$APP_HOME` (NOT `../.java/.userPrefs`)

**Issue**: Permission denied writing supervisord.log or cache
- **Cause**: OLD version used `/tmp` which may have restrictive perms for UID 3000
- **Solution**: Ensure supervisord paths are `/tmp/supervisord.log` and `/tmp/supervisord.pid`

---

## USB Device Support

### How It Works
1. Container **runs as non-root** (UID 3000 in Kubernetes)
2. Host system applies udev rules with `MODE="0666"` (world read/write)
3. Host's udevd applies rules to USB devices before container sees them
4. Container passes USB bus via volume mount: `/dev/bus/usb:/dev/bus/usb`
5. Non-root user can access USB at boot time without running udevd in container

### Host Setup (Required)

**Apply these rules on every host where USB Nintendo Switches will be connected:**

```bash
# Nintendo Switch normal mode (Goldleaf)
sudo tee /etc/udev/rules.d/99-NS.rules > /dev/null <<EOF
SUBSYSTEM=="usb", ATTRS{idVendor}=="057e", ATTRS{idProduct}=="3000", MODE="0666"
EOF

# RCM/Recovery mode (payload injection)
sudo tee /etc/udev/rules.d/99-NS-RCM.rules > /dev/null <<EOF
SUBSYSTEM=="usb", ATTRS{idVendor}=="0955", ATTRS{idProduct}=="7321", MODE="0666"
EOF

# Reload rules
sudo udevadm control --reload-rules && sudo udevadm trigger
```

### Container Deployment (Docker/Podman)
```bash
docker run --device /dev/bus/usb -p 8080:8080 -p 6042:6042 \
  -v /path/to/nsp:/nsp \
  ghcr.io/timoverbrugghe/ns-usbloader
```

### Kubernetes Deployment
```yaml
volumeMounts:
  - name: usb-bus
    mountPath: /dev/bus/usb

volumes:
  - name: usb-bus
    hostPath:
      path: /dev/bus/usb
      type: Directory
```

### Why NOT in Container
- **udevd is a host-level service**: Manages device nodes and permissions on the host filesystem
- **Container-level udevd cannot apply rules**: The container's udevd doesn't control the host's /dev
- **Privilege escalation risk**: Running udevd in container would require root, defeating security posture
- **Design**: Host prepares devices, container consumes them

### USB Device Troubleshooting
- **Error "You have been entered as: ?"**: Likely USB issue, check host udev rules applied
- **Device not detected**: Verify `lsusb` on host shows Switch, then check udev rules
- **Permission denied accessing USB**: Check `MODE="0666"` in rules, not `MODE="0600"`

---

## File Organization

### Root Directory
```
.github/
  copilot-instructions.md    ← This file
app/
  supervisord.conf           ← Supervisor process manager config
  rc.xml                     ← Openbox window manager config
  prefs.xml                  ← NS-USBLoader app preferences
docker-compose.yaml          ← Docker Compose example
Dockerfile                   ← Container definition
README.md                    ← User-facing documentation
```

### Why Organize in app/?
- Clean separation between container definition and application configuration
- Easy to locate and modify config files
- Clear intent: "this is app-level configuration, not build artifacts"

---

## Common Modifications & Extensions

### Changing Preferences
Edit `app/prefs.xml`:
- `HOSTIP`: PC IP address (for network mode)
- `HOSTPORT`: Port ns-usbloader listens on
- `NSIP`: Nintendo Switch IP
- `THEME`: CSS theme path

After editing, rebuild image: `docker build -t ns-usbloader .`

### Changing UID/GID (for non-Kubernetes Docker)
```bash
docker build --build-arg UID=2000 --build-arg GID=2000 -t ns-usbloader:custom .
```

### Adding Custom udev Rules
If targeting other USB devices:
1. Find vendor/product ID: `lsusb | grep <device>`
2. Add rule in `99-*.rules` on host system
3. No container changes needed (rules applied at host level)

### Disabling Fullscreen (temporary testing)
Modify `app/rc.xml`: change `<fullscreen>yes</fullscreen>` to `no`

---

## Troubleshooting Checklist

### Container Won't Start
- [ ] Check Docker logs: `docker logs <container>`
- [ ] Supervisord logs: `docker exec <container> cat /tmp/supervisord.log`
- [ ] Ensure `/nsp` volume accessible: `docker exec <container> ls /nsp`

### noVNC Not Accessible (port 8080)
- [ ] Is novnc process running? `supervisorctl status` in container
- [ ] Port forwarding correct? `docker run -p 8080:8080 ...`
- [ ] Xvfb running? Check X11 process in supervisord.log

### NS-USBLoader Fullscreen Not Applied
- [ ] Check `echo $HOME` in container (should be `/home/nsusbloader`)
- [ ] Verify rc.xml copied: `cat /home/nsusbloader/.config/openbox/rc.xml`
- [ ] Check Openbox logs: `cat /tmp/supervisord.log | grep openbox`

### USB Device Not Detected
- [ ] Host udev rules applied? `cat /etc/udev/rules.d/99-NS.rules`
- [ ] Device connected & recognized? `lsusb | grep 057e` (normal) or `0955` (RCM)
- [ ] Device passed to container? `docker run --device /dev/bus/usb ...`

### Preferences Not Loaded
- [ ] Check Java prefs root: `echo $JAVA_TOOL_OPTIONS` in container
- [ ] Should show: `-Duser.home=/home/nsusbloader -Djava.util.prefs.userRoot=/home/nsusbloader`
- [ ] File exists? `ls /home/nsusbloader/.java/.userPrefs/NS-USBloader/prefs.xml`
- [ ] No double-nested path? `ls -la /home/nsusbloader/.java/.userPrefs/`

---

## Development & Contribution Notes

### Testing Changes Locally
```bash
# Build & test
docker build -t ns-usbloader:test .

# Run with interactive access
docker run -it --rm -p 8080:8080 -p 6042:6042 \
  -v ./Downloads/games:/nsp \
  --device /dev/bus/usb \
  ns-usbloader:test

# Access: http://localhost:8080
```

### Pushing to ghcr.io
```bash
docker tag ns-usbloader:test ghcr.io/timoverbrugghe/ns-usbloader:latest
docker push ghcr.io/timoverbrugghe/ns-usbloader:latest
```

### Updating ns-usbloader JAR Version
1. Check [releases](https://github.com/developersu/ns-usbloader/releases)
2. Update Dockerfile line: `wget ... -O /usr/local/app/ns-usbloader.jar ...`
3. Update README version reference
4. Rebuild & test

---

## Future Work & Known Limitations

- **Read-only filesystem**: Not yet tested with `securityContext.readOnlyRootFilesystem: true`
- **Multi-architecture**: Currently amd64 only; arm64 may need JavaFX compatibility fixes
- **Prefs persistence**: ConfigMap mount is read-only; writing prefs back requires writable volume + init container
- **Log aggregation**: Supervisord logs to `/tmp/supervisord.log`; consider sidecar for Kubernetes
- **Health checks**: Currently basic HTTP probes; could add gRPC probes for port 6042

---

## References & Resources

- **NS-USBLoader GitHub**: https://github.com/developersu/ns-usbloader
- **OpenJFX**: https://openjfx.io/
- **Openbox**: http://openbox.org/
- **noVNC**: https://novnc.com/
- **udev Rules Guide**: https://wiki.debian.org/udev
