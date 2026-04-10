FROM debian:bookworm-slim

ARG UID=1000
ARG GID=1000

ENV DEBIAN_FRONTEND=noninteractive
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8
ENV DISPLAY=:0
ENV APP_USER=nsusbloader
ENV APP_HOME=/home/nsusbloader
ENV HOME=$APP_HOME
ENV XDG_CACHE_HOME=$APP_HOME/.cache
ENV JAVA_TOOL_OPTIONS="-Duser.home=$APP_HOME -Djava.util.prefs.userRoot=$APP_HOME"

VOLUME /nsp
VOLUME $APP_HOME/.java/.userPrefs/NS-USBloader

# Install dependencies and prepare runtime paths
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates wget \
    libx11-6 libxxf86vm1 libgl1 \
    xvfb x11vnc openbox \
    python3-xdg \
    supervisor \
    novnc websockify \
    openjdk-17-jdk \
    openjfx \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid $GID $APP_USER \
    && useradd --system --create-home --home-dir $APP_HOME --gid $GID --uid $UID $APP_USER \
    && mkdir -p $APP_HOME/.cache/fontconfig $APP_HOME/.openjfx/cache $APP_HOME/.config/openbox $APP_HOME/.java/.userPrefs/NS-USBloader /usr/local/app /nsp /tmp/.X11-unix \
    && chmod 1777 /tmp/.X11-unix \
    && wget -q https://github.com/developersu/ns-usbloader/releases/download/v7.3/ns-usbloader-7.3.jar -O /usr/local/app/ns-usbloader.jar \
    && chown -R $APP_USER:$APP_USER $APP_HOME /usr/local/app /nsp

COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY rc.xml $APP_HOME/.config/openbox/rc.xml
COPY prefs.xml $APP_HOME/.java/.userPrefs/NS-USBloader/prefs.xml
COPY 99-NS.rules /etc/udev/rules.d/99-NS.rules
COPY 99-NS-RCM.rules /etc/udev/rules.d/99-NS-RCM.rules

# Ensure copied config files are owned by non-root runtime user
RUN chown -R $APP_USER:$APP_USER $APP_HOME \
    && chmod -R a+rwX $APP_HOME \
    && ln -sfn /usr/share/novnc/vnc.html /usr/share/novnc/index.html

WORKDIR /usr/local/app/

EXPOSE 8080
EXPOSE 6042

USER $APP_USER

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
