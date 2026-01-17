set -exu

# Output changesets release candidates to a temporary file
TMP_JSON=changeset-status.json
pnpm changeset status --output "$TMP_JSON"

# Ensure the file exists and is valid JSON
if [ ! -s "$TMP_JSON" ]; then
    echo '[]' > "$TMP_JSON"
fi

# Extract package names from JSON
PACKAGES=$(jq -r '.releases[].name' "$TMP_JSON" 2>/dev/null || echo '' | sort -u)

# Convert to JSON array for GitHub Actions
if [ -n "$PACKAGES" ]; then
    MATRIX_JSON=$(printf '%s\n' $PACKAGES | jq -R -s -c 'split("\n")[:-1]')
else
    MATRIX_JSON='[]'
fi

# Output for GitHub Actions, or print to console if not in GITHUB_ACTIONS
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf 'matrix=%s\n' "$MATRIX_JSON" >> "$GITHUB_OUTPUT"
else
    echo "$MATRIX_JSON"
fi

# Clean up temp file
rm -f "$TMP_JSON"