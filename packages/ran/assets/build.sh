#!/usr/bin/env bash
set -euo pipefail

# Configuration
VERSION="${VERSION:-v0.1.6}"
BASE_URL="https://github.com/m3ng9i/ran/releases/download/${VERSION}"

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUTPUT_DIR="$ROOT/out/ran"
TEMP_DIR="$(mktemp -d)"

# File definitions: filename|zip_sha256|binary_name|binary_sha256|dest_dir
# Re-pin when bumping VERSION:
#   download each zip, sha256sum the zip, unzip, sha256sum the binary
FILES=(
    "ran_windows_386.exe.zip|30da0f781a83553c39b459df4213f0da7922f7a90e0cb3d35b58053c04e8c9d5|ran_windows_386.exe|53b940e4889ef92df5045e4d044967cd7ea708f8530b39ec6663e35586f6cb6e|win/ia32"
    "ran_windows_amd64.exe.zip|f2384a6fbf81eb9801fcf3a683454867a1f93453dd9b0ad5eded11f6f2d2c098|ran_windows_amd64.exe|2efe79bba7db40fa1957b6432abf48c7a6a368c62f0694fe4f173af73a53c30a|win/amd64"
    "ran_linux_386.zip|698717f98824453bf2248f3042108fc0a094007939f4a5aff94ec73f89504398|ran_linux_386|23f6d9842c352a1c07ed73f9246fb085bb24062887845173d0f6782dc58f4ade|linux/386"
    "ran_linux_amd64.zip|d156e085e5d30c5fcffd8b438beceaa63d0e276b158f5612b656f528a093d77d|ran_linux_amd64|a4d117dc3b10e99d0fa61e31b2733223c6b949bc7fa038d6441b299a064b5a36|linux/amd64"
    "ran_linux_arm64.zip|38bfd59d8883752fec15152d3750a9ac85ce0e574c4561a775245f60ae04b093|ran_linux_arm64|e3f99c3c62132e24a699193a6f59ebcc471b2130131a5561514ab44e89007ab4|linux/arm64"
    "ran_darwin_amd64.zip|8ef11da419676003df2eda34adc2b9b635f4f20047f042b254d721e9e1e9d8b5|ran_darwin_amd64|731386ea13fa05bdac642f0159ac5c9aea2fac7670505192c1ec1b0fbcb72349|darwin/amd64"
)

echo "🚀 Starting Ran ${VERSION} download and organization"
echo ""

# Create directory structure
echo "📁 Creating directory structure..."
mkdir -p "$OUTPUT_DIR/win/ia32" "$OUTPUT_DIR/win/amd64" \
         "$OUTPUT_DIR/linux/amd64" "$OUTPUT_DIR/linux/arm64" \
         "$OUTPUT_DIR/linux/386" "$OUTPUT_DIR/darwin/amd64"

# Cleanup function
cleanup() {
    echo "🧹 Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Portable SHA256 verification
verify_sha256() {
    local file="$1" expected="$2" actual
    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$file" | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        actual=$(shasum -a 256 "$file" | awk '{print $1}')
    else
        echo "❌ Error: No SHA256 utility found (sha256sum or shasum required)"
        exit 1
    fi
    if [ "$actual" != "$expected" ]; then
        echo "❌ Checksum mismatch for $file"
        echo "   Expected: $expected"
        echo "   Got:      $actual"
        return 1
    fi
    echo "   ✅ Checksum verified"
    return 0
}

# Download and process each file
for entry in "${FILES[@]}"; do
    # Parse the entry
    IFS='|' read -r filename zip_sha256 binary_name binary_sha256 dest_dir <<< "$entry"

    echo ""
    echo "📥 Processing: $filename"

    # Download
    download_path="$TEMP_DIR/$filename"
    url="${BASE_URL}/${filename}"

    echo "   Downloading from: $url"
    if ! curl -fsSL --retry 3 --retry-delay 2 --max-time 120 -o "$download_path" "$url"; then
        echo "❌ Failed to download $filename"
        continue
    fi

    # Verify ZIP checksum
    echo "   Verifying ZIP checksum..."
    if ! verify_sha256 "$download_path" "$zip_sha256"; then
        echo "❌ Skipping $filename due to checksum mismatch"
        continue
    fi

    # Extract
    extract_dir="$TEMP_DIR/extract_${filename%.*}"
    mkdir -p "$extract_dir"

    echo "   Extracting archive..."
    if ! unzip -q "$download_path" -d "$extract_dir"; then
        echo "❌ Failed to extract $filename"
        continue
    fi

    # Find the binary file (should match the binary_name)
    binary_file="$extract_dir/$binary_name"

    if [ ! -f "$binary_file" ]; then
        echo "❌ Binary file not found: $binary_name"
        continue
    fi

    # Verify binary checksum
    echo "   Verifying binary checksum..."
    if ! verify_sha256 "$binary_file" "$binary_sha256"; then
        echo "❌ Skipping $filename due to binary checksum mismatch"
        continue
    fi

    # Copy to destination and rename to 'ran' or 'ran.exe'
    dest_path="$OUTPUT_DIR/$dest_dir"

    # Determine output filename based on platform
    if [[ "$dest_dir" == win/* ]]; then
        output_name="ran.exe"
    else
        output_name="ran"
    fi

    dest_file="$dest_path/$output_name"

    echo "   Copying to: $dest_path/$output_name"
    cp "$binary_file" "$dest_file"
    chmod +x "$dest_file" 2>/dev/null || true

    echo "   ✅ Successfully processed $filename"
done

# Create VERSION.txt at root
echo "📝 Creating VERSION.txt..."
echo "$VERSION" > "$OUTPUT_DIR/VERSION.txt"

# Download RAN LICENSE
echo "📄 Downloading LICENSE..."
curl -fsSL --retry 3 --retry-delay 2 --max-time 60 \
    "https://raw.githubusercontent.com/m3ng9i/ran/${VERSION}/LICENSE" \
    -o "$OUTPUT_DIR/LICENSE"

# Create final ZIP bundle
ARCHIVE_NAME="ran-${VERSION}-all-platforms.zip"

echo ""
echo "📦 Creating ZIP bundle: $ARCHIVE_NAME"
(
    cd "$OUTPUT_DIR"
    zip -r -9 "$OUTPUT_DIR/$ARCHIVE_NAME" . >/dev/null
)

echo ""
echo "✨ All done!"
echo ""
echo "📂 Organized binaries are in: $OUTPUT_DIR/"
echo "📦 ZIP bundle created: $ARCHIVE_NAME"
echo ""
echo "Directory structure:"
tree "$OUTPUT_DIR" 2>/dev/null || find "$OUTPUT_DIR" -type f

echo ""
echo "🎉 Process completed successfully!"
