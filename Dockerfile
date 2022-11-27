ARG BUILD_FROM
FROM alpine:3.16

ARG \
    BUILD_ARCH=amd64 \
    QEMU_CPU \
    SSOCR_VERSION=2.22.1 \
    ARPSCAN_VERSION=1.9.7 \
    LIBCEC_VERSION=6.0.2 \
    PICOTTS_HASH=e3ba46009ee868911fa0b53db672a55f9cc13b1c \
    TELLDUS_COMMIT=2598bbed16ffd701f2a07c99582f057a3decbaf3

# Add Home Assistant wheels repository
ENV WHEELS_LINKS=https://wheels.home-assistant.io/musllinux/

##
# Install component packages
RUN \
    apk add --no-cache \
        bluez \
        bluez-deprecated \
        bluez-libs \
        curl \
        eudev-libs \
        ffmpeg \
        iperf3 \
        git \
        grep \
        libgpiod \
        libjpeg-turbo \
        libpulse \
        libzbar \
        mariadb-connector-c \
        net-tools \
        nmap \
        openssh-client \
        pianobar \
        pulseaudio-alsa \
        py3-pip \
        python3-dev \
        socat

####
## Install pip module for component/homeassistant
COPY requirements.txt /usr/src/
RUN \
    pip3 install --no-cache-dir --no-index --only-binary=:all: --find-links ${WHEELS_LINKS} \
        -r /usr/src/requirements.txt \
    && rm -f /usr/src/requirements.txt

####
## Build library
WORKDIR /usr/src/

# ssocr
RUN \
    apk add --no-cache \
        imlib2 \
    && apk add --no-cache --virtual .build-dependencies \
        build-base \
        imlib2-dev \
    && git clone --depth 1 -b v${SSOCR_VERSION} https://github.com/auerswal/ssocr \
    && cd ssocr \
    && make -j$(nproc) \
    && make install \
    && apk del .build-dependencies \
    && rm -rf /usr/src/ssocr

# arp-scan
RUN \
    apk add --no-cache \
        libpcap \
    && apk add --no-cache --virtual .build-dependencies \
        autoconf \
        automake \
        build-base \
        libpcap-dev \
    && git clone --depth 1 -b ${ARPSCAN_VERSION} https://github.com/royhills/arp-scan \
    && cd arp-scan \
    && autoreconf --install \
    && ./configure \
    && make -j$(nproc) \
    && make install \
    && apk del .build-dependencies \
    && rm -rf /usr/src/arp-scan

# libcec
COPY patches/libcec-fix-null-return.patch /usr/src/
RUN apk add --no-cache \
        eudev-libs \
        p8-platform \
    && apk add --no-cache --virtual .build-dependencies \
        build-base \
        cmake \
        eudev-dev \
        swig \
        p8-platform-dev \
        linux-headers \
    && git clone --depth 1 -b libcec-${LIBCEC_VERSION} https://github.com/Pulse-Eight/libcec \
    && cd libcec \
    && git apply ../libcec-fix-null-return.patch \
    && mkdir build \
    && cd build \
    && cmake -DCMAKE_INSTALL_PREFIX:PATH=/usr/local \
        -DPYTHON_LIBRARY="/usr/lib/libpython3.10.so" \
        -DPYTHON_INCLUDE_DIR="/usr/include/python3.10" \
        -DHAVE_LINUX_API=1 \
        .. \
    && make -j$(nproc) \
    && make install \
    && echo "cec" > "/usr/local/lib/python3.10/site-packages/cec.pth" \
    && apk del .build-dependencies \
    && rm -rf \
        /usr/src/libcec \
        /usr/src/libcec-fix-null-return.patch

# PicoTTS - it has no specific version - commit should be taken from build.json
RUN apk add --no-cache \
        popt \
    && apk add --no-cache --virtual .build-dependencies \
       automake \
       autoconf \
       libtool \
       popt-dev \
       build-base \ 
    && git clone https://github.com/naggety/picotts.git pico \
    && cd pico/pico \
    && git reset --hard ${PICOTTS_HASH} \
    && ./autogen.sh \
    && ./configure \
         --disable-static \
    && make \
    && make install \
    && apk del .build-dependencies \
    && rm -rf /usr/src/pico

# Telldus
COPY patches/telldus-fix-gcc-11-issues.patch /usr/src/
RUN \
    apk add --no-cache \
        confuse \
        libftdi1 \
    && apk add --no-cache --virtual .build-dependencies \
        argp-standalone \
        build-base \
        cmake \
        confuse-dev \
        doxygen \
        libftdi1-dev \
    && ln -s /usr/include/libftdi1/ftdi.h /usr/include/ftdi.h \
    && git clone https://github.com/telldus/telldus \
    && cd telldus \
    && git reset --hard ${TELLDUS_COMMIT} \
    && git apply ../telldus-fix-gcc-11-issues.patch \
    && cd telldus-core \
    && cmake . -DBUILD_LIBTELLDUS-CORE=ON \
        -DBUILD_TDADMIN=OFF -DBUILD_TDTOOL=OFF -DGENERATE_MAN=OFF \
        -DFORCE_COMPILE_FROM_TRUNK=ON -DFTDI_LIBRARY=/usr/lib/libftdi1.so \
    && make -j$(nproc) \
    && make install \
    && apk del .build-dependencies \
    && rm -rf \
        /usr/src/telldus \
        /usr/src/telldus-fix-gcc-11-issues.patch

###
# Base S6-Overlay
COPY rootfs /
