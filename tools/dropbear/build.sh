#!/bin/sh
# Reproducible build of a fully static dropbearmulti for an ARMv7 Kindle.
# Host needs Docker with QEMU binfmt for linux/arm/v7 (Docker Desktop has it).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
VER=2026.94
SHA=e098034a843699200c8c977a991fff73159735bf795d5f72ef672c41a6b1ae81
TB=dropbear-$VER.tar.bz2
IMAGE=${IMAGE:-alpine:3.22}
cd "$HERE"
[ -f "src/$TB" ] || { mkdir -p src; curl -fsSL -o "src/$TB" "https://matt.ucc.asn.au/dropbear/releases/$TB"; }
echo "$SHA  src/$TB" | shasum -a 256 -c -
mkdir -p out
docker run --rm --platform linux/arm/v7 -v "$HERE":/w -e VER="$VER" "$IMAGE" sh -euc '
  apk add --no-cache build-base linux-headers file >/dev/null
  mkdir -p /build && cd /build
  tar -xjf /w/src/dropbear-$VER.tar.bz2 && cd dropbear-$VER
  cp /w/localoptions.h .
  # Kernel 3.0 has no getrandom(2) (added in 3.17): force it off so seeding reads /dev/urandom.
  ac_cv_func_getrandom=no ./configure --enable-static --disable-zlib \
      --disable-lastlog --disable-utmp --disable-utmpx --disable-wtmp --disable-wtmpx \
      --disable-pututline --disable-pututxline > /w/out/configure.log 2>&1
  grep -n "getrandom" /w/out/configure.log || true
  grep -n "GETRANDOM" config.h > /w/out/getrandom-check.txt || true
  cat /w/out/getrandom-check.txt
  make -j"$(nproc)" PROGRAMS="dropbear dropbearkey scp" MULTI=1 STATIC=1 > /w/out/make.log 2>&1 || { tail -n 40 /w/out/make.log; exit 1; }
  cp dropbearmulti /w/out/dropbearmulti.unstripped
  strip dropbearmulti
  cp dropbearmulti /w/out/dropbearmulti
  file /w/out/dropbearmulti
'
