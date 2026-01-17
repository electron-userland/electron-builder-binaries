#!/usr/bin/env bash
set -euo pipefail

# Configuration
VERSION="${VERSION:-v0.1.6}"
BASE_URL="https://github.com/m3ng9i/ran/releases/download/${VERSION}"

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUTPUT_DIR="$ROOT/out/ran"
TEMP_DIR="$(mktemp -d)"

# File definitions: filename|zip_checksum|binary_name|binary_checksum|dest_dir
FILES=(
    "ran_windows_386.exe.zip|95474d447fb8a63de55b952e4abe3da6d6fc7d20|ran_windows_386.exe|65c88cd1658f1d2a60be875f2aa7609a7cf1d09d|win/ia32"
    "ran_windows_amd64.exe.zip|dd5262d6844c41cc64c84c7ffdcf7847eff4c63e|ran_windows_amd64.exe|d054209941ec434940f10733bf5c3bada3a731bd|win/amd64"
    "ran_linux_386.zip|29f769cb6887bd441804d58b1a3147394bc8451c|ran_linux_386|959b71a61adaab46e11371902f747409747fcfdf|linux/386"
    "ran_linux_amd64.zip|06e9538fc893a06078b80f93a059fad1dea4942e|ran_linux_amd64|c28c7833f40a003e45ea0439a68478fc14dbb789|linux/amd64"
    "ran_linux_arm64.zip|b309b4b52427f80cb550683a106108a2abe74816|ran_linux_arm64|787e03391c17882379d12d878ed95f8147e36c47|linux/arm64"
    "ran_darwin_amd64.zip|c6473bd34f89f69baf43bcf312670abdee057c17|ran_darwin_amd64|1a1528e191363b9bf1487fee7ba0f05a87a08e06|darwin/amd64"
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

# Function to verify SHA1 checksum
verify_checksum() {
    local file="$1"
    local expected="$2"
    
    if command -v sha1sum >/dev/null 2>&1; then
        actual=$(sha1sum "$file" | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        actual=$(shasum -a 1 "$file" | awk '{print $1}')
    else
        echo "❌ Error: No SHA1 utility found (sha1sum or shasum required)"
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
    IFS='|' read -r filename zip_checksum binary_name binary_checksum dest_dir <<< "$entry"
    
    echo ""
    echo "📥 Processing: $filename"
    
    # Download
    download_path="$TEMP_DIR/$filename"
    url="${BASE_URL}/${filename}"
    
    echo "   Downloading from: $url"
    if ! curl -L -f -o "$download_path" "$url" 2>/dev/null; then
        echo "❌ Failed to download $filename"
        continue
    fi
    
    # Verify ZIP checksum
    echo "   Verifying ZIP checksum..."
    if ! verify_checksum "$download_path" "$zip_checksum"; then
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
    if ! verify_checksum "$binary_file" "$binary_checksum"; then
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