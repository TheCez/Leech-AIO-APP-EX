# Stage 1 - Build the frontend
FROM node:18-alpine3.18 AS node-build-env
ARG TARGETPLATFORM
ENV TARGETPLATFORM=${TARGETPLATFORM:-linux/amd64}
ARG BUILDPLATFORM
ENV BUILDPLATFORM=${BUILDPLATFORM:-linux/amd64}

#build rdt-client

RUN mkdir /appclient
WORKDIR /appclient

RUN apk add --no-cache git python3 py3-pip make g++

RUN \
   echo "**** Cloning Source Code ****" && \
   git clone https://github.com/rogerfar/rdt-client.git . && \
   cd client && \
   echo "**** Building Code  ****" && \
   npm ci && \
   npx ng build --output-path=out

RUN ls -FCla /appclient/root

# Stage 2 - Build the backend
FROM mcr.microsoft.com/dotnet/sdk:8.0-bookworm-slim-amd64 AS dotnet-build-env
ARG TARGETPLATFORM
ENV TARGETPLATFORM=${TARGETPLATFORM:-linux/amd64}
ARG BUILDPLATFORM
ENV BUILDPLATFORM=${BUILDPLATFORM:-linux/amd64}

RUN mkdir /appserver
WORKDIR /appserver

RUN \
   echo "**** Cloning Source Code ****" && \
   git clone https://github.com/rogerfar/rdt-client.git . && \
   echo "**** Building Source Code for $TARGETPLATFORM on $BUILDPLATFORM ****" && \
   cd server && \
   if [ "$TARGETPLATFORM" = "linux/arm/v7" ] ; then \
      echo "**** Building $TARGETPLATFORM arm v7 version" && \
      dotnet restore --no-cache -r linux-arm RdtClient.sln && dotnet publish --no-restore -r linux-arm -c Release -o out ; \
   elif [ "$TARGETPLATFORM" = "linux/arm/v8" ] ; then \
      echo "**** Building $TARGETPLATFORM arm v8 version" && \
      dotnet restore --no-cache -r linux-arm64 RdtClient.sln && dotnet publish --no-restore -r linux-arm64 -c Release -o out ; \
   else \
      echo "**** Building $TARGETPLATFORM x64 version" && \
      dotnet restore --no-cache RdtClient.sln && dotnet publish --no-restore -c Release -o out ; \
   fi

# Stage 3 - Build runtime image
FROM ghcr.io/linuxserver/baseimage-alpine:3.18
ARG TARGETPLATFORM
ENV TARGETPLATFORM=${TARGETPLATFORM:-linux/amd64}
ARG BUILDPLATFORM
ENV BUILDPLATFORM=${BUILDPLATFORM:-linux/amd64}

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io extended version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="ravensorb"

# set environment variables
ARG DEBIAN_FRONTEND="noninteractive"
ENV XDG_CONFIG_HOME="/config/xdg"
ENV RDTCLIENT_BRANCH="main"

RUN \
    mkdir -p /data/downloads /data/db || true && \
    echo "**** Updating package information ****" && \
    apk update && \
    echo "**** Install pre-reqs ****" && \
    apk add bash icu-libs krb5-libs libgcc libintl libssl1.1 libstdc++ zlib && \
    echo "**** Installing dotnet ****" && \
	mkdir -p /usr/share/dotnet

RUN \
   if [ "$TARGETPLATFORM" = "linux/arm/v7" ] ; then \
      wget https://download.visualstudio.microsoft.com/download/pr/c3bf3103-efdb-42e0-af55-bbf861a4215b/dc22eda8877933b8c6569e3823f18d21/aspnetcore-runtime-8.0.0-linux-musl-arm64.tar.gz && \
      tar zxf aspnetcore-runtime-8.0.0-linux-musl-arm64.tar.gz -C /usr/share/dotnet ; \
   elif [ "$TARGETPLATFORM" = "linux/arm/v8" ] ; then \
      wget https://download.visualstudio.microsoft.com/download/pr/c3bf3103-efdb-42e0-af55-bbf861a4215b/dc22eda8877933b8c6569e3823f18d21/aspnetcore-runtime-8.0.0-linux-musl-arm64.tar.gz && \
      tar zxf aspnetcore-runtime-8.0.0-linux-musl-arm64.tar.gz -C /usr/share/dotnet ; \
   else \
      wget https://download.visualstudio.microsoft.com/download/pr/7aa33fc7-07fe-48c2-8e44-a4bfb4928535/3b96ec50970eee414895ef3a5b188bcd/aspnetcore-runtime-8.0.0-linux-musl-x64.tar.gz && \
      tar zxf aspnetcore-runtime-8.0.0-linux-musl-x64.tar.gz -C /usr/share/dotnet ; \
   fi
	
RUN \
    echo "**** Setting permissions ****" && \
    chown -R abc:abc /data && \
    rm -rf \
        /tmp/* \
        /var/cache/apk/* \
        /var/tmp/* || true

ENV PATH "$PATH:/usr/share/dotnet"

# Copy files for app
WORKDIR /app
COPY --from=dotnet-build-env /appserver/server/out .
COPY --from=node-build-env /appclient/client/out ./wwwroot
COPY --from=node-build-env /appclient/root/ /

# ports and volumes
EXPOSE 6500
VOLUME [ "/data" ]

# Check Status
HEALTHCHECK --interval=30s --timeout=30s --start-period=30s --retries=3 CMD curl --fail http://localhost:6500 || exit 

#rdt-client done

FROM node:lts-alpine as builder

WORKDIR /metube

RUN apk add git && \
    git clone https://github.com/alexta69/metube && \
    mv ./metube/ui/* ./ && \
    npm ci && \
    node_modules/.bin/ng build --configuration production


FROM caddy:2.7.4-builder AS builder-caddy

RUN xcaddy build \
  --with github.com/caddy-dns/cloudflare@bfe272c8525b6dd8248fcdddb460fd6accfc4e84


FROM python:3.8-alpine AS dist

COPY ./content /workdir/

WORKDIR /app

ENV GLOBAL_USER=admin
ENV GLOBAL_PASSWORD=password
ENV CADDY_DOMAIN=http://localhost
ENV CADDY_EMAIL=internal
ENV CADDY_WEB_PORT=8080
ENV GLOBAL_LANGUAGE=en
ENV GLOBAL_PORTAL_PATH=/portal
ENV PATH="/root/.local/bin:$PATH"
ENV XDG_CONFIG_HOME=/mnt/data/config
ENV DOWNLOAD_DIR=/mnt/data/videos
ENV STATE_DIR=/mnt/data/videos/.metube
ENV ARIA2_PORT=61800
ENV FILEBROWSER_PORT=61801
ENV METUBE_PORT=61802
ENV OLIVETIN_PORT=61803
ENV PYLOAD_PORT=61804
ENV QBT_WEBUI_PORT=61805
ENV RCLONE_PORT=61806
ENV RCLONE_WEBDAV_PORT=61807

RUN apk add --no-cache --update curl jq ffmpeg runit tzdata fuse3 p7zip bash findutils \
    && python3 -m pip install --user --no-cache-dir pipx \
    && apk add --no-cache --update --virtual .build-deps git curl-dev gcc g++ libffi-dev musl-dev jpeg-dev \
    && pip install --no-cache-dir pipenv \
    && git clone https://github.com/alexta69/metube \
    && mv ./metube/Pipfile* ./metube/app ./metube/favicon ./ \
    && pipenv install --system --deploy --clear \
    && pip uninstall pipenv -y \
    && pipx install --pip-args='--no-cache-dir' pyload-ng[plugins] \
    && pipx install --pip-args='--no-cache-dir' gallery-dl \
    && apk del .build-deps \
    && wget -O - https://github.com/mayswind/AriaNg/releases/download/1.3.6/AriaNg-1.3.6.zip | busybox unzip -qd /workdir/ariang - \
    && wget -O - https://github.com/rclone/rclone-webui-react/releases/download/v2.0.5/currentbuild.zip | busybox unzip -qd /workdir/rcloneweb - \
    && wget -O - https://github.com/bastienwirtz/homer/releases/latest/download/homer.zip | busybox unzip -qd /workdir/homer - \
    && wget -O - https://github.com/WDaan/VueTorrent/releases/latest/download/vuetorrent.zip | busybox unzip -qd /workdir - \
    && chmod +x /workdir/service/*/run /workdir/service/*/log/run /workdir/aria2/*.sh /workdir/*.sh /workdir/dlpr /workdir/gdlr \
    && /workdir/install.sh \
    && rm -rf metube /workdir/install.sh /tmp/* ${HOME}/.cache /var/cache/apk/* \
    && mv /workdir/ytdlp*.sh /workdir/dlpr /workdir/gdlr /usr/bin/ \
    && ln -s /workdir/service/* /etc/service/

COPY --from=builder /metube/dist/metube /app/ui/dist/metube

COPY --from=builder-caddy /usr/bin/caddy /usr/bin/caddy

VOLUME /mnt/data

ENTRYPOINT ["sh","-c","/workdir/entrypoint.sh"]
