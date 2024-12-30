# docker build -t ipxe:latest . && docker save ipxe:latest | tar --ignore-command-error --strip-components=2 --to-command='tar -vxf -' -xf -

FROM alpine:3.21 AS build

## Install build-dependencies.
RUN apk --no-cache add \
      bash \
      binutils \
      coreutils \
      gawk \
      gcc \
      git \
      make \
      mtools \
      musl-dev \
      openssl \
      patch \
      perl \
      sed \
      syslinux \
      wget \
      xorriso \
      xz-dev

## Set shell.
SHELL ["/bin/bash", "-o", "pipefail", "-xec"]

## iPXE version.
ARG IPXE_BRANCH="master"
## Ref: https://launchpad.net/ubuntu/+source/ipxe/1.21.1+git-20220113.fbbdc3926-0ubuntu2
ARG IPXE_COMMIT_HASH="fbbdc3926"

## Checkout specified iPXE version.
RUN git clone --branch "${IPXE_BRANCH}" --single-branch "git://git.ipxe.org/ipxe.git" /ipxe.git/
RUN git -C /ipxe.git reset --hard "${IPXE_COMMIT_HASH}"

## Tune iPXE config options.
RUN sed -Ei "s/^#undef([ \t]*DOWNLOAD_PROTO_(FTP)[ \t]*)/#define\1/" \
  /ipxe.git/src/config/general.h
RUN sed -Ei "s/^\/\/#undef([ \t]*SANBOOT_PROTO_(HTTP|ISCSI)[ \t]*)/#define\1/" \
  /ipxe.git/src/config/general.h
RUN sed -Ei "s/^\/\/(#define[ \t]*(CONSOLE|IMAGE_MEM|IPSTAT|LOTEST|NEIGHBOUR|NSLOOKUP|NTP|PARAM|PCI|PING|POWEROFF|REBOOT|TIME)_CMD)/\1/" \
  /ipxe.git/src/config/general.h

## Apply patches.
COPY patches/0003-Inhibit-linker-warnings-about-an-implied-executable-.patch /tmp/0003.patch
COPY patches/0004-Fix-building-with-newer-binutils.patch /tmp/0004.patch
COPY patches/0005-strip-802.1Q-VLAN-0-priority-tags.patch /tmp/0005.patch
RUN patch -d /ipxe.git -p1 < /tmp/0003.patch
RUN patch -d /ipxe.git -p1 < /tmp/0004.patch
RUN patch -d /ipxe.git -p1 < /tmp/0005.patch

## Destination folder for compiled files.
WORKDIR /ipxe/

## Compile specified build targets.
## https://ipxe.org/appnote/buildtargets
## https://ipxe.org/embed
RUN make EXTRA_CFLAGS="-fcommon" -C /ipxe.git/src/ \
    NO_WERROR=1 \
    bin-i386-efi/ipxe.usb \
    bin-i386-pcbios/ipxe.hd \
    bin-i386-pcbios/ipxe.dsk \
    bin-i386-pcbios/ipxe.pdsk \
    bin-i386-pcbios/ipxe.iso \
    bin-x86_64-efi/ipxe.usb \
    bin-x86_64-pcbios/ipxe.hd \
    bin-x86_64-pcbios/ipxe.dsk \
    bin-x86_64-pcbios/ipxe.pdsk \
    bin-x86_64-pcbios/ipxe.iso
RUN \
    mkdir -p i386 x86_64 && \
    cp -v /ipxe.git/src/bin-i386-efi/ipxe.usb i386/ && \
    cp -v /ipxe.git/src/bin-i386-pcbios/ipxe.{hd,dsk,pdsk,iso} i386/ && \
    cp -v /ipxe.git/src/bin-x86_64-efi/ipxe.usb x86_64/ && \
    cp -v /ipxe.git/src/bin-x86_64-pcbios/ipxe.{hd,dsk,pdsk,iso} x86_64/

## Create image from scratch.
FROM scratch

## Copy the previously compiled iPXE files.
COPY --from=build /ipxe/ /ipxe/
