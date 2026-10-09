#!/bin/sh
set -eu

# Download pinned AppImage runtimes and verify SHA256 checksums and GPG signatures.
#
# Requires gpg (or gpg2). Exit codes: 5 = no gpg / bad signing key, 6 = bad signature.
#
# Usage:
#   download-runtime.sh               # download and verify to current directory (default)
#   download-runtime.sh --install-directory /path/to/dir  # download to specified directory
#   download-runtime.sh --print-checksums  # download and print sha256 lines for check-in
#
# The expected checksums live below in the CHECKSUMS variable. Use
# --print-checksums to compute the correct checksums (copy the output into the
# CHECKSUMS block and commit to source control).

# note: "20251108" match checksums hardcoded below
APPIMAGE_TYPE2_RELEASE="${APPIMAGE_TYPE2_RELEASE:-20251108}"

BASE_URL="https://github.com/AppImage/type2-runtime/releases/download/${APPIMAGE_TYPE2_RELEASE}"

FILES="runtime-x86_64:runtime-x64 runtime-i686:runtime-ia32 runtime-aarch64:runtime-arm64 runtime-armhf:runtime-arm32"

# Expected checksums (sha256) for files downloaded above.
# Format: <hex>  <path>
# Replace the <hex> values with concrete sha256 values before committing. Use
# --print-checksums to generate the lines for copy/paste.
CHECKSUMS=$(cat <<'CHECKSUMS'
2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d  runtime-x64
e72ea0b140a0a16e680713238a6f30aad278b62c4ca17919c554864124515498  runtime-ia32
00cbdfcf917cc6c0ff6d3347d59e0ca1f7f45a6df1a428a0d6d8a78664d87444  runtime-arm64
e9060d37577b8a29914ec12d8740add24e19ff29012fb1fa0f60daf62db0688d  runtime-arm32
CHECKSUMS
)

# type2-runtime release signing key, vendored next to this script. Byte-identical to
# the 20251108 release asset signing-pubkey.asc
# (sha256 db8b615eb5bbf5e8418d52906b4a492960926370e2c5041ad6acaccda56ef0c6).
RUNTIME_SIGNING_KEY="${RUNTIME_SIGNING_KEY:-$(cd "$(dirname "$0")" && pwd)/type2-runtime-signing-pubkey.asc}"
# Primary key fingerprint every runtime's detached <asset>.sig must verify against (expires 2034-05-03)
RUNTIME_SIGNING_FINGERPRINT="570C77ACEA40C0F1B758902CBF96CCA56490F695"

usage() {
	echo "Usage: $0 [OPTIONS]"
	echo ""
	echo "Options:"
	echo "  --install-directory DIR  Download files to the specified directory (default: current directory)"
	echo "  --print-checksums        Download files and print sha256 lines suitable for copy/paste into this script's CHECKSUMS block."
	exit 1
}

MODE="verify"
INSTALL_DIR="."

# Parse arguments
while [ "$#" -gt 0 ]; do
	case "$1" in
		--print-checksums)
			MODE="print"
			shift
			;;
		--install-directory)
			if [ "$#" -lt 2 ]; then
				echo "Error: --install-directory requires a directory argument" >&2
				exit 1
			fi
			INSTALL_DIR="$2"
			shift 2
			;;
		*)
			echo "Error: unknown argument: $1" >&2
			usage
			;;
	esac
done

# Create install directory if it doesn't exist
if [ ! -d "$INSTALL_DIR" ]; then
	echo "Creating directory: $INSTALL_DIR" >&2
	mkdir -p "$INSTALL_DIR"
fi

OUT_DIR="${OUT_DIR:-$INSTALL_DIR}"

# Detached signatures are kept next to (not inside) the install directory so they are not bundled
SIG_DIR="${INSTALL_DIR%/}.sigs"

# Helper: compute sha256 of a file in a portable way
sha256_of() {
	file="$1"
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$file" | awk '{print $1}'
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$file" | awk '{print $1}'
	elif command -v openssl >/dev/null 2>&1; then
		openssl dgst -sha256 "$file" | awk '{print $NF}'
	else
		echo "Error: no sha256 checksum program (sha256sum|shasum|openssl) found" >&2
		exit 2
	fi
}

# Helper: locate GnuPG (gpg, then gpg2) and store it in GPG
find_gpg() {
	for candidate in gpg gpg2; do
		if command -v "$candidate" >/dev/null 2>&1; then
			GPG="$candidate"
			return 0
		fi
	done
	echo "Error: gpg or gpg2 is required to verify runtime signatures" >&2
	exit 5
}

# Helper: import the signing key into a temporary GNUPGHOME and assert its fingerprint
setup_gpg() {
	find_gpg
	if [ ! -f "$RUNTIME_SIGNING_KEY" ]; then
		echo "Error: runtime signing key not found: $RUNTIME_SIGNING_KEY" >&2
		exit 5
	fi
	GNUPGHOME="$(mktemp -d)"
	export GNUPGHOME
	trap 'rm -rf "$GNUPGHOME"' EXIT
	chmod 700 "$GNUPGHOME"
	if ! gpg_log="$("$GPG" --batch --no-tty --no-autostart --import "$RUNTIME_SIGNING_KEY" 2>&1)"; then
		echo "$gpg_log" >&2
		echo "Error: failed to import runtime signing key $RUNTIME_SIGNING_KEY" >&2
		exit 5
	fi
	key_fingerprints="$("$GPG" --batch --no-tty --no-autostart --with-colons --fingerprint 2>/dev/null | awk -F: '$1 == "pub" { want = 1; next } $1 == "fpr" && want { print $10; want = 0 }')"
	if [ "$key_fingerprints" != "$RUNTIME_SIGNING_FINGERPRINT" ]; then
		echo "Error: $RUNTIME_SIGNING_KEY is not the pinned runtime signing key" >&2
		echo "  expected: $RUNTIME_SIGNING_FINGERPRINT" >&2
		echo "  found:    $key_fingerprints" >&2
		exit 5
	fi
	echo "Using $GPG with runtime signing key $RUNTIME_SIGNING_FINGERPRINT" >&2
}

# Helper: require a GOODSIG on file $1 (detached signature $2) made by the pinned key
verify_sig() {
	file="$1"
	sig="$2"
	if [ ! -f "$file" ] || [ ! -f "$sig" ]; then
		echo "Missing $file or its signature $sig" >&2
		exit 6
	fi
	gpg_status="$("$GPG" --batch --no-tty --no-autostart --status-fd 1 --verify "$sig" "$file" 2>/dev/null || true)"
	# Last VALIDSIG field is the primary key fingerprint
	signer="$(printf '%s\n' "$gpg_status" | awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { print $NF }')"
	case "$gpg_status" in
		*"[GNUPG:] GOODSIG "*) ;;
		*) signer="" ;;
	esac
	if [ "$signer" != "$RUNTIME_SIGNING_FINGERPRINT" ]; then
		echo "Bad signature for $file" >&2
		printf '%s\n' "$gpg_status" >&2
		exit 6
	fi
	echo "GPG  $file" >&2
}

verify_sigs() {
	for mapping in $FILES; do
		dest=${mapping##*:}
		verify_sig "$INSTALL_DIR/$dest" "$SIG_DIR/$dest.sig"
	done
}

setup_gpg

# Download files
if [ -z "${SKIP_DOWNLOAD-}" ]; then
	mkdir -p "$SIG_DIR"
	for mapping in $FILES; do
		src=${mapping%%:*}
		dest=${mapping##*:}
		dest_path="$INSTALL_DIR/$dest"
		url="$BASE_URL/$src"
		echo "Downloading $url -> $dest_path" >&2
		if ! curl -fsSL "$url" -o "$dest_path"; then
			echo "Failed to download $url" >&2
			exit 2
		fi
		echo "Downloading $url.sig -> $SIG_DIR/$dest.sig" >&2
		if ! curl -fsSL "$url.sig" -o "$SIG_DIR/$dest.sig"; then
			echo "Failed to download $url.sig" >&2
			exit 2
		fi
	done
else
	echo "SKIP_DOWNLOAD is set; skipping downloads" >&2
fi

if [ "$MODE" = "print" ]; then
	# Only print checksums of correctly signed runtimes
	verify_sigs
	# Print computed checksums in the standard format for copy/paste into
	# CHECKSUMS block. Don't modify the script automatically by default.
	for mapping in $FILES; do
		dest=${mapping##*:}
		dest_path="$INSTALL_DIR/$dest"
		if [ ! -f "$dest_path" ]; then
			echo "Missing file $dest_path" >&2
			exit 3
		fi
		echo "$(sha256_of "$dest_path")  $dest"
	done
	exit 0
fi

# Allow injecting checksums via the environment for tests (CHECKSUMS_ENV)
if [ -n "${CHECKSUMS_ENV-}" ]; then
	CHECKSUMS="$CHECKSUMS_ENV"
fi

# Verification mode: verify each downloaded file against CHECKSUMS
failed=0
for mapping in $FILES; do
	dest=${mapping##*:}
	dest_path="$INSTALL_DIR/$dest"
	expected="$(printf '%s\n' "$CHECKSUMS" | awk -v f="$dest" '$2==f{print $1}')"
	if [ -z "$expected" ]; then
		echo "Warning: no expected checksum found for $dest in CHECKSUMS; skipping" >&2
		continue
	fi
	# If expected checksum is a placeholder like <sha256-for-...> then skip too
	case "$expected" in
		"<"*">")
			echo "Warning: placeholder expected checksum for $dest; skipping" >&2
			continue
			;;
	esac
	if [ ! -f "$dest_path" ]; then
		echo "File not found: $dest_path" >&2
		failed=1
		continue
	fi
	computed="$(sha256_of "$dest_path")"
	if [ "$computed" != "$expected" ]; then
		echo "Checksum mismatch for $dest" >&2
		echo "  expected: $expected" >&2
		echo "  computed: $computed" >&2
		failed=1
	else
		echo "OK   $dest_path" >&2
	fi
done

if [ "$failed" -ne 0 ]; then
	echo "Some files failed checksum verification" >&2
	exit 4
fi

verify_sigs

echo "AppImage/type2-runtime release: $APPIMAGE_TYPE2_RELEASE" > "$INSTALL_DIR/VERSION.txt"
echo "GPG signer: $RUNTIME_SIGNING_FINGERPRINT" >> "$INSTALL_DIR/VERSION.txt"
echo "$CHECKSUMS" >> "$INSTALL_DIR/VERSION.txt"
echo "All files verified successfully." >&2

ARCHIVE_NAME="appimage-runtime-$APPIMAGE_TYPE2_RELEASE.tar.gz"
echo "📦 Creating tar.gz bundle: $ARCHIVE_NAME"
(
cd "$INSTALL_DIR/.."
tar czf "$OUT_DIR/$ARCHIVE_NAME" $(basename "$INSTALL_DIR")
)
echo "✅ Done!"
echo "Bundle at: $OUT_DIR/$ARCHIVE_NAME"