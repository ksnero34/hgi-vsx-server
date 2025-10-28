#!/bin/bash
################################################################################
# Extension Upload Script
#
# Purpose: Upload extensions to OpenVSX registry (offline environment)
# Usage: ./upload-extensions.sh [extensions-directory]
#
# Prerequisites:
#   1. OpenVSX instance running
#   2. Personal Access Token (PAT) created
#   3. Extensions downloaded using download-extensions.sh
################################################################################

set -e

EXTENSIONS_DIR="${1:-./extensions}"
REGISTRY_URL="${OVSX_REGISTRY_URL:-http://vsx.hgi.com:28080}"
PAT="${OVSX_PAT}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=================================================="
echo "OpenVSX Extension Publisher"
echo "=================================================="
echo ""
echo "Registry URL: $REGISTRY_URL"
echo "Extensions directory: $EXTENSIONS_DIR"
echo ""

# Check if extensions directory exists
if [ ! -d "$EXTENSIONS_DIR" ]; then
    echo -e "${RED}Error: Extensions directory not found: $EXTENSIONS_DIR${NC}"
    echo ""
    echo "Please specify the directory containing downloaded extensions."
    echo "Usage: $0 <extensions-directory>"
    exit 1
fi

# Check for PAT
if [ -z "$PAT" ]; then
    echo -e "${YELLOW}No Personal Access Token (PAT) found.${NC}"
    echo ""
    echo "Please create a PAT first:"
    echo "  1. Log in to $REGISTRY_URL"
    echo "  2. Go to User Settings > Access Tokens"
    echo "  3. Create a new token"
    echo ""
    read -p "Enter your Personal Access Token: " PAT
    export OVSX_PAT="$PAT"
fi

# Install ovsx CLI if not available in Docker context
# (This assumes we're running in a container or have Node.js available)
if ! command -v ovsx &> /dev/null; then
    echo -e "${YELLOW}Installing ovsx CLI...${NC}"
    if command -v npm &> /dev/null; then
        npm install -g ovsx
    else
        echo -e "${RED}Error: npm not found. Cannot install ovsx CLI.${NC}"
        echo "Please install Node.js or run this script in the CLI container."
        exit 1
    fi
fi

# Counter for statistics
TOTAL=0
SUCCESS=0
FAILED=0
SKIPPED=0

# Create namespaces and publish extensions
echo "Scanning for extensions..."
echo ""

# Build a list of unique extension versions to upload
# Group by publisher/extension/version/release-type and prefer universal over platform-specific
declare -A extension_files

while IFS= read -r vsix_file; do
    # Extract extension info from path
    RELATIVE_PATH="${vsix_file#$EXTENSIONS_DIR/}"
    PUBLISHER=$(echo "$RELATIVE_PATH" | cut -d'/' -f1)
    EXTENSION=$(echo "$RELATIVE_PATH" | cut -d'/' -f2)

    # Determine version and release type from path
    # Path patterns:
    # extensions/publisher/extension/version/stable/file.vsix (universal)
    # extensions/publisher/extension/version/platform/stable/file.vsix (platform-specific)
    # extensions/publisher/extension/stable/file.vsix (universal, latest)
    # extensions/publisher/extension/platform/stable/file.vsix (platform-specific, latest)

    FILENAME=$(basename "$vsix_file")
    DIR_PATH=$(dirname "$vsix_file")
    RELEASE_TYPE=$(basename "$DIR_PATH")  # stable or pre-release

    # Check if this is platform-specific or universal
    PARENT_DIR=$(dirname "$DIR_PATH")
    PARENT_NAME=$(basename "$PARENT_DIR")

    if [[ "$PARENT_NAME" =~ ^(linux-x64|win32-x64|darwin-x64|alpine-x64|web)$ ]]; then
        # Platform-specific
        PLATFORM="$PARENT_NAME"
        VERSION_DIR=$(dirname "$PARENT_DIR")
    else
        # Universal
        PLATFORM="universal"
        VERSION_DIR="$PARENT_DIR"
    fi

    # Create unique key for this extension version
    KEY="$PUBLISHER/$EXTENSION/$VERSION_DIR/$RELEASE_TYPE"

    # Prefer universal over platform-specific
    if [ -z "${extension_files[$KEY]}" ] || [ "$PLATFORM" = "universal" ]; then
        extension_files[$KEY]="$vsix_file|$PUBLISHER|$EXTENSION|$PLATFORM"
    fi
done < <(find "$EXTENSIONS_DIR" -name "*.vsix" -type f | sort)

# Now publish the selected extensions
for KEY in "${!extension_files[@]}"; do
    TOTAL=$((TOTAL + 1))

    IFS='|' read -r vsix_file PUBLISHER EXTENSION PLATFORM <<< "${extension_files[$KEY]}"

    echo -e "${BLUE}[$TOTAL] Processing: $PUBLISHER.$EXTENSION${NC}"
    echo "  File: $(basename "$vsix_file")"
    echo "  Type: $PLATFORM"

    # Create namespace if it doesn't exist
    echo "  Checking namespace: $PUBLISHER"
    if ovsx create-namespace "$PUBLISHER" -p "$PAT" -r "$REGISTRY_URL" 2>&1 | grep -q "already exists\|created successfully\|Created namespace"; then
        echo "  ✓ Namespace ready"
    else
        echo -e "  ${YELLOW}! Namespace may already exist or couldn't be created (continuing...)${NC}"
    fi

    # Publish extension
    echo "  Publishing extension..."
    ovsx publish "$vsix_file" -p "$PAT" -r "$REGISTRY_URL" --skip-duplicate 2>&1 | tee /tmp/publish_output.txt
    EXIT_CODE=${PIPESTATUS[0]}

    if grep -q "Unknown publisher\|ERROR\|Failed" /tmp/publish_output.txt; then
        echo -e "  ${RED}✗ Failed to publish${NC}"
        FAILED=$((FAILED + 1))

        # Log error
        DIR_PATH=$(dirname "$vsix_file")
        ERROR_LOG="$DIR_PATH/upload-error.log"
        echo "Failed at $(date)" >> "$ERROR_LOG"
        cat /tmp/publish_output.txt >> "$ERROR_LOG" 2>&1 || true
    elif grep -q "already published" /tmp/publish_output.txt; then
        echo -e "  ${YELLOW}⊘ Already published (skipped)${NC}"
        SKIPPED=$((SKIPPED + 1))
    elif grep -q "Published\|🚀" /tmp/publish_output.txt && [ $EXIT_CODE -eq 0 ]; then
        echo -e "  ${GREEN}✓ Successfully published${NC}"
        SUCCESS=$((SUCCESS + 1))
    else
        echo -e "  ${YELLOW}? Unknown result${NC}"
        FAILED=$((FAILED + 1))

        # Log error
        DIR_PATH=$(dirname "$vsix_file")
        ERROR_LOG="$DIR_PATH/upload-error.log"
        echo "Unknown result at $(date)" >> "$ERROR_LOG"
        cat /tmp/publish_output.txt >> "$ERROR_LOG" 2>&1 || true
    fi

    echo ""
done

# Summary
echo "=================================================="
echo "Upload Summary"
echo "=================================================="
echo "Total extensions: $TOTAL"
echo -e "${GREEN}Successfully published: $SUCCESS${NC}"
echo -e "${YELLOW}Skipped (already exists): $SKIPPED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo ""

if [ $FAILED -gt 0 ]; then
    echo -e "${YELLOW}Warning: Some extensions failed to publish.${NC}"
    echo "Check the upload-error.log files in the extension directories."
    exit 1
fi

echo -e "${GREEN}All extensions processed successfully!${NC}"
echo ""
echo "Your OpenVSX registry is now ready with the published extensions."
echo "Access it at: $REGISTRY_URL"
