#!/bin/bash
################################################################################
# Extension Download Script
#
# Purpose: Download VSCode extensions from VS Marketplace or Open VSX
# Usage: ./download-extensions.sh [extension-list-file]
#
# Format: publisher.extension[@version][@target-platform]
# Examples:
#   ms-python.python                    # Latest version
#   ms-python.python@2024.0.0           # Specific version
#   ms-python.python@2024.0.0@linux-x64 # Specific version and platform
#   ms-python.python@@linux-x64         # Latest version for specific platform
################################################################################

set -e

DOWNLOAD_DIR="./extensions"
EXTENSION_LIST="${1:-extensions.txt}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=================================================="
echo "VSCode Extension Downloader"
echo "=================================================="
echo ""

# Check if extension list exists
if [ ! -f "$EXTENSION_LIST" ]; then
    echo -e "${RED}Error: Extension list file not found: $EXTENSION_LIST${NC}"
    echo ""
    echo "Please create a file with extension IDs (one per line)."
    echo "Format: publisher.extension[@version][@target-platform]"
    echo ""
    echo "Example extensions.txt:"
    echo "  ms-python.python                    # Latest version"
    echo "  ms-python.python@2024.0.0           # Specific version"
    echo "  dbaeumer.vscode-eslint@2.4.4        # Specific version"
    echo "  ms-python.python@2024.0.0@linux-x64 # Version + platform"
    exit 1
fi

# Create download directory
mkdir -p "$DOWNLOAD_DIR"

# Install ovsx CLI if not available
if ! command -v ovsx &> /dev/null; then
    echo -e "${YELLOW}Installing ovsx CLI...${NC}"
    npm install -g ovsx
fi

# Counter for statistics
TOTAL=0
SUCCESS=0
FAILED=0

echo "Reading extensions from: $EXTENSION_LIST"
echo "Download directory: $DOWNLOAD_DIR"
echo ""

# Function to parse extension specification
parse_extension_spec() {
    local spec="$1"
    local extension_id version target_platform

    # Split by @ to get parts
    IFS='@' read -ra PARTS <<< "$spec"

    extension_id="${PARTS[0]}"
    version="${PARTS[1]:-latest}"
    target_platform="${PARTS[2]:-}"

    # If version is empty but target is specified, version should be latest
    if [ -z "$version" ] && [ -n "$target_platform" ]; then
        version="latest"
    fi

    echo "$extension_id|$version|$target_platform"
}

# Download each extension
while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    TOTAL=$((TOTAL + 1))

    # Parse extension specification
    IFS='|' read -r extension version target <<< "$(parse_extension_spec "$line")"

    echo -e "${YELLOW}[$TOTAL] Processing: $extension${NC}"
    [ "$version" != "latest" ] && echo -e "    ${BLUE}Version: $version${NC}"
    [ -n "$target" ] && echo -e "    ${BLUE}Platform: $target${NC}"

    # Extract publisher and name
    PUBLISHER=$(echo "$extension" | cut -d'.' -f1)
    NAME=$(echo "$extension" | cut -d'.' -f2-)

    # Create subdirectory for this extension
    EXT_DIR="$DOWNLOAD_DIR/$PUBLISHER/$NAME"
    if [ "$version" != "latest" ]; then
        EXT_DIR="$EXT_DIR/$version"
    fi
    if [ -n "$target" ]; then
        EXT_DIR="$EXT_DIR/$target"
    fi
    mkdir -p "$EXT_DIR"

    # Build ovsx command arguments
    OVSX_ARGS="$extension"
    [ "$version" != "latest" ] && OVSX_ARGS="$OVSX_ARGS --version $version"
    [ -n "$target" ] && OVSX_ARGS="$OVSX_ARGS --target $target"

    # Try downloading from Open VSX first
    echo "  Attempting download from Open VSX..."
    if ovsx get $OVSX_ARGS -o "$EXT_DIR" 2>/dev/null; then
        echo -e "  ${GREEN}✓ Downloaded from Open VSX${NC}"

        # Also download metadata
        ovsx get $OVSX_ARGS --metadata -o "$EXT_DIR/metadata.json" 2>/dev/null || true

        SUCCESS=$((SUCCESS + 1))
    else
        # Fallback: try downloading from VS Marketplace
        echo "  Open VSX failed, trying VS Marketplace..."

        # Build VS Marketplace URL
        if [ "$version" = "latest" ]; then
            VERSION_PATH="latest"
        else
            VERSION_PATH="$version"
        fi

        # VS Marketplace API URL
        VSIX_URL="https://${PUBLISHER}.gallery.vsassets.io/_apis/public/gallery/publisher/${PUBLISHER}/extension/${NAME}/${VERSION_PATH}/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage"

        # Construct output filename
        OUTPUT_FILE="$EXT_DIR/${extension}"
        [ "$version" != "latest" ] && OUTPUT_FILE="${OUTPUT_FILE}-${version}"
        [ -n "$target" ] && OUTPUT_FILE="${OUTPUT_FILE}@${target}"
        OUTPUT_FILE="${OUTPUT_FILE}.vsix"

        if curl -L -f "$VSIX_URL" -o "$OUTPUT_FILE" 2>/dev/null; then
            echo -e "  ${GREEN}✓ Downloaded from VS Marketplace${NC}"
            SUCCESS=$((SUCCESS + 1))
        else
            echo -e "  ${RED}✗ Failed to download${NC}"
            FAILED=$((FAILED + 1))
            # Create error marker file
            cat > "$EXT_DIR/ERROR.txt" <<EOF
Failed to download from both Open VSX and VS Marketplace
Extension: $extension
Version: $version
Target: ${target:-any}
Timestamp: $(date)
EOF
        fi
    fi

    echo ""
done < "$EXTENSION_LIST"

# Summary
echo "=================================================="
echo "Download Summary"
echo "=================================================="
echo "Total extensions: $TOTAL"
echo -e "${GREEN}Successfully downloaded: $SUCCESS${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo ""
echo "Extensions saved to: $DOWNLOAD_DIR"
echo ""

if [ $FAILED -gt 0 ]; then
    echo -e "${YELLOW}Warning: Some extensions failed to download.${NC}"
    echo "Check the ERROR.txt files in the extension directories."
    exit 1
fi

echo -e "${GREEN}All extensions downloaded successfully!${NC}"
echo ""
echo "Next steps:"
echo "  1. Copy the '$DOWNLOAD_DIR' directory to USB drive"
echo "  2. Transfer to offline environment"
echo "  3. Run ./upload-extensions.sh to publish to your OpenVSX instance"
