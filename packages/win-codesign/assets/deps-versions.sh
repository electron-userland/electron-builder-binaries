#!/usr/bin/env bash
# Pinned versions of the libraries bundled with osslsigncode on macOS and Linux.
# Sourced by build-mac.sh and build-linux-osslsigncode.sh so both platforms ship the same
# OpenSSL / libp11; each value can be overridden from the environment.

# OpenSSL 3.5 is the current LTS line (supported until 2030-04-08). The checksum
# matches the upstream release tarball (also pinned by Homebrew's openssl@3 formula).
# renovate: datasource=github-releases depName=openssl/openssl extractVersion=^openssl-(?<version>.+)$
OPENSSL_VER="${OPENSSL_VER:-3.5.9}"
OPENSSL_SHA256="${OPENSSL_SHA256:-603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a}"
# libp11 provides the pkcs11prov OpenSSL provider used for `-pkcs11module` signing.
# renovate: datasource=github-releases depName=OpenSC/libp11 extractVersion=^libp11-(?<version>.+)$
LIBP11_VER="${LIBP11_VER:-0.4.21}"
LIBP11_SHA256="${LIBP11_SHA256:-efdb523aef8613d447e6a2d38227d4b389866f4bcf4b503130acd7f759490847}"
