#!/bin/bash
################################################################################
# Extension Download Script with Dependency Resolution
#
# Purpose: Download VSCode extensions with all dependencies
# Usage: ./download-extensions-with-deps.sh [extension-list-file]
#
# Features:
#   - Automatic dependency resolution
#   - Download both pre-release and stable versions
#   - Platform-specific versions
################################################################################

set -e

DOWNLOAD_DIR="./extensions"
EXTENSION_LIST="${1:-extensions.txt}"
DOWNLOADED_FILE="./downloaded_extensions.log"
DEPENDENCY_FILE="./dependencies.txt"

# Platform selection ("win32-x64" or "universal")
PLATFORM_MODE="${PLATFORM_MODE:-win32-x64}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "=================================================="
echo "VSCode Extension Downloader with Dependencies"
echo "=================================================="
echo ""

# Check if extension list exists
if [ ! -f "$EXTENSION_LIST" ]; then
    echo -e "${RED}Error: Extension list file not found: $EXTENSION_LIST${NC}"
    exit 1
fi

# Create download directory
mkdir -p "$DOWNLOAD_DIR"

# Determine default platforms
DEFAULT_PLATFORMS=()
case "$PLATFORM_MODE" in
    win32-x64)
        DEFAULT_PLATFORMS=("win32-x64")
        ;;
    universal)
        DEFAULT_PLATFORMS=("")
        ;;
    *)
        echo -e "${RED}Error: Invalid PLATFORM_MODE '$PLATFORM_MODE' (use 'win32-x64' or 'universal')${NC}"
        exit 1
        ;;
esac

# Install required tools
if ! command -v ovsx &> /dev/null; then
    echo -e "${YELLOW}Installing ovsx CLI...${NC}"
    npm install -g ovsx
fi

if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}Installing jq for JSON parsing...${NC}"
    sudo apt-get update && sudo apt-get install -y jq
fi

# Initialize tracking files
> "$DOWNLOADED_FILE"
> "$DEPENDENCY_FILE"

# Counter for statistics
TOTAL=0
SUCCESS=0
FAILED=0
DEPS_FOUND=0

# Function to parse extension specification
parse_extension_spec() {
    local spec="$1"
    local extension_id version target_platform

    IFS='@' read -ra PARTS <<< "$spec"
    extension_id="${PARTS[0]}"
    version="${PARTS[1]:-latest}"
    target_platform="${PARTS[2]:-}"

    if [ -z "$version" ] && [ -n "$target_platform" ]; then
        version="latest"
    fi

    echo "$extension_id|$version|$target_platform"
}

# Function to check if extension was already downloaded
is_downloaded() {
    local ext_id="$1"
    local version="$2"
    grep -q "^${ext_id}@${version}$" "$DOWNLOADED_FILE" 2>/dev/null
}

# Function to mark extension as downloaded
mark_downloaded() {
    local ext_id="$1"
    local version="$2"
    echo "${ext_id}@${version}" >> "$DOWNLOADED_FILE"
}

# Function to get extension metadata
get_extension_metadata() {
    local ext_id="$1"
    local version="$2"

    if [ "$version" = "latest" ]; then
        ovsx get "$ext_id" --metadata 2>/dev/null
    else
        ovsx get "$ext_id" --version "$version" --metadata 2>/dev/null
    fi
}

# Function to extract dependencies from metadata
extract_dependencies() {
    local metadata="$1"

    # Extract extensionDependencies and extensionPack
    echo "$metadata" | jq -r '
        (.extensionDependencies // []) + (.extensionPack // []) |
        .[] | select(. != null and . != "")
    ' 2>/dev/null | sort -u
}

# Function to find latest stable version from VS Marketplace
find_stable_version_vscode() {
    local ext_id="$1"

    # VS Marketplace API only returns versions in small batches
    # We'll check multiple pages to find stable version
    local max_attempts=5  # Check up to 5 pages (roughly 50+ versions)

    for page in $(seq 1 $max_attempts); do
        local query_result=$(curl -s -X POST 'https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery' \
          -H 'Content-Type: application/json' \
          -H 'Accept: application/json;api-version=3.0-preview.1' \
          -d "{
            \"filters\": [{
              \"criteria\": [{\"filterType\": 7, \"value\": \"$ext_id\"}],
              \"pageNumber\": $page,
              \"pageSize\": 50
            }],
            \"flags\": 914
          }" 2>/dev/null)

        # Check if we got results
        if [ -z "$query_result" ]; then
            continue
        fi

        # Find first version without PreRelease property set to true
        local stable_ver=$(echo "$query_result" | jq -r '
            .results[0].extensions[0].versions[]? |
            select(
              [.properties[]? | select(.key == "Microsoft.VisualStudio.Code.PreRelease" and .value == "true")] | length == 0
            ) |
            .version
        ' 2>/dev/null | head -1)

        if [ -n "$stable_ver" ] && [ "$stable_ver" != "null" ]; then
            echo "$stable_ver"
            return 0
        fi
    done

    return 1
}

# Function to find latest stable version from Open VSX (fast version - only check 20)
find_stable_version_openvsx() {
    local ext_id="$1"
    local publisher=$(echo "$ext_id" | cut -d'.' -f1)
    local name=$(echo "$ext_id" | cut -d'.' -f2-)

    local api_url="https://open-vsx.org/api/${publisher}/${name}"
    local ext_info=$(curl -s "$api_url" 2>/dev/null)

    if [ -z "$ext_info" ]; then
        return 1
    fi

    # Get versions in reverse order (newest first), excluding aliases
    local all_versions=$(echo "$ext_info" | jq -r '.allVersions | keys | reverse | .[] | select(. != "latest" and . != "pre-release")' 2>/dev/null)

    if [ -z "$all_versions" ]; then
        return 1
    fi

    # Only check first 20 versions for speed
    local max_checks=20
    local count=0

    while IFS= read -r ver; do
        [ -z "$ver" ] && continue
        [ $count -ge $max_checks ] && break

        local ver_info=$(curl -s "${api_url}/${ver}" 2>/dev/null)
        local is_prerelease=$(echo "$ver_info" | jq -r '.preRelease // false' 2>/dev/null)

        if [ "$is_prerelease" = "false" ]; then
            echo "$ver"
            return 0
        fi

        count=$((count + 1))
    done <<< "$all_versions"

    return 1
}

# Function to download extension with both versions
download_extension() {
    local line="$1"
    local download_prerelease="${2:-true}"

    IFS='|' read -r extension version target <<< "$(parse_extension_spec "$line")"

    # Skip if already downloaded
    if is_downloaded "$extension" "$version"; then
        echo -e "  ${CYAN}↺ Already downloaded, skipping${NC}"
        return 0
    fi

    TOTAL=$((TOTAL + 1))

    echo -e "${YELLOW}[$TOTAL] Processing: $extension${NC}"
    [ "$version" != "latest" ] && echo -e "    ${BLUE}Version: $version${NC}"
    [ -n "$target" ] && echo -e "    ${BLUE}Platform: $target${NC}"

    PUBLISHER=$(echo "$extension" | cut -d'.' -f1)
    NAME=$(echo "$extension" | cut -d'.' -f2-)

    # Determine actual version
    local actual_version="$version"
    if [ "$version" = "latest" ]; then
        # Get latest version from metadata
        local metadata=$(get_extension_metadata "$extension" "latest")
        if [ -n "$metadata" ]; then
            actual_version=$(echo "$metadata" | jq -r '.version // "latest"')
            echo -e "    ${BLUE}Latest version: $actual_version${NC}"
        fi
    fi

    # Determine platforms to download
    local platforms=()
    if [ -n "$target" ]; then
        # If platform specified, use only that
        platforms=("$target")
    else
        # Default platform set (win32-x64 or universal)
        platforms=("${DEFAULT_PLATFORMS[@]}")
    fi

    # Pre-search for stable version once (shared across all platforms)
    local stable_version_found=""
    local stable_version_checked=false

    # Download versions based on request
    local stable_downloaded=false
    local prerelease_downloaded=false
    local any_success=false

    for platform in "${platforms[@]}"; do
        local platform_label=""
        [ -n "$platform" ] && platform_label=" ($platform)"

        # If a specific version is requested, download it once per platform
        if [ "$version" != "latest" ]; then
            echo -e "  ${CYAN}→ Downloading${platform_label}...${NC}"
            if download_single_version "$extension" "$version" "$platform" "false" "true" "$version"; then
                any_success=true
            fi
            continue
        fi

        # Try stable version first (skip if already failed on first platform)
        if [ "$stable_version_checked" = "false" ] || [ -n "$stable_version_found" ]; then
            echo -e "  ${CYAN}→ Downloading${platform_label}...${NC}"
            if download_single_version "$extension" "$version" "$platform" "false" "$stable_version_checked" "$stable_version_found"; then
                stable_downloaded=true
                any_success=true

                # Cache the result after first attempt
                if [ "$stable_version_checked" = "false" ]; then
                    stable_version_checked=true
                    local meta_file="$DOWNLOAD_DIR/$PUBLISHER/$NAME"
                    [ "$version" != "latest" ] && meta_file="$meta_file/$version"
                    [ -n "$platform" ] && meta_file="$meta_file/$platform"
                    meta_file="$meta_file/stable/metadata.json"
                    if [ -f "$meta_file" ]; then
                        stable_version_found=$(jq -r '.version // ""' "$meta_file" 2>/dev/null || echo "")
                    fi
                fi
            elif [ "$stable_version_checked" = "false" ]; then
                stable_version_checked=true
            fi
        fi
    done

    # Check if we should also download latest (pre-release) version
    if [ "$download_prerelease" = "true" ] && [ "$version" = "latest" ]; then
        local should_download_latest=false
        if [ "$stable_downloaded" = "false" ] && [ "$stable_version_checked" = "true" ] && [ -z "$stable_version_found" ]; then
            # No stable version exists at all
            echo -e "  ${YELLOW}→ No stable version available, downloading latest version...${NC}"
            should_download_latest=true
        elif [ "$stable_downloaded" = "true" ] && [ -n "$stable_version_found" ]; then
            # We downloaded a stable version, check if there's a newer pre-release
            # Get the actual latest version number
            local latest_version=$(curl -s "https://marketplace.visualstudio.com/items?itemName=$extension" | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4 2>/dev/null || echo "")
            if [ -z "$latest_version" ]; then
                # Try API approach
                latest_version=$(curl -s -X POST 'https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery' \
                  -H 'Content-Type: application/json' \
                  -H 'Accept: application/json;api-version=3.0-preview.1' \
                  -d "{\"filters\":[{\"criteria\":[{\"filterType\":7,\"value\":\"$extension\"}],\"pageSize\":1}],\"flags\":914}" 2>/dev/null | \
                  jq -r '.results[0].extensions[0].versions[0].version' 2>/dev/null || echo "")
            fi

            if [ -n "$latest_version" ] && [ "$latest_version" != "$stable_version_found" ]; then
                echo -e "  ${BLUE}→ Found newer pre-release version: $latest_version (stable: $stable_version_found)${NC}"
                should_download_latest=true
            fi
        fi

        if [ "$should_download_latest" = "true" ]; then
            for platform in "${platforms[@]}"; do
                local platform_label=""
                [ -n "$platform" ] && platform_label=" ($platform)"

                echo -e "  ${CYAN}→ Downloading latest${platform_label}...${NC}"
                if download_single_version "$extension" "$version" "$platform" "true" "true" ""; then
                    any_success=true
                fi
            done
        fi
    fi

    if [ "$any_success" = "false" ]; then
        FAILED=$((FAILED + 1))
        return 1
    fi

    # Count as success if any platform succeeded
    SUCCESS=$((SUCCESS + 1))

    # Mark as downloaded
    mark_downloaded "$extension" "$actual_version"

    # Get metadata and extract dependencies
    echo -e "  ${CYAN}→ Checking dependencies...${NC}"

    # Try to get metadata from downloaded files
    local metadata=""
    local metadata_file=""

    # Search for any metadata.json in the extension directory
    for platform in "" "linux-x64" "win32-x64"; do
        for release_type in "pre-release" "stable"; do
            local search_dir="$DOWNLOAD_DIR/$PUBLISHER/$NAME"
            [ "$version" != "latest" ] && search_dir="$search_dir/$version"
            [ -n "$platform" ] && search_dir="$search_dir/$platform"
            search_dir="$search_dir/$release_type"

            if [ -f "$search_dir/metadata.json" ]; then
                metadata_file="$search_dir/metadata.json"
                metadata=$(cat "$metadata_file")
                break 2
            fi
        done
    done

    if [ -n "$metadata" ]; then
        local deps=$(extract_dependencies "$metadata")

        if [ -n "$deps" ]; then
            local dep_count=$(echo "$deps" | wc -l)
            echo -e "  ${GREEN}✓ Found $dep_count dependencies${NC}"

            # Add to dependency file for later processing
            while IFS= read -r dep; do
                if ! grep -q "^${dep}$" "$DEPENDENCY_FILE" 2>/dev/null && \
                   ! grep -q "^${dep}@" "$DOWNLOADED_FILE" 2>/dev/null; then
                    echo "$dep" >> "$DEPENDENCY_FILE"
                    echo -e "    ${BLUE}+ $dep${NC}"
                    DEPS_FOUND=$((DEPS_FOUND + 1))
                fi
            done <<< "$deps"
        else
            echo -e "  ${GREEN}✓ No dependencies${NC}"
        fi
    fi

    echo ""
    return 0
}

# Function to download a single version
download_single_version() {
    local extension="$1"
    local version="$2"
    local target="$3"
    local prerelease="$4"
    local stable_checked="${5:-false}"  # Has stable version search been done?
    local stable_found="${6:-}"          # Cached stable version result

    local PUBLISHER=$(echo "$extension" | cut -d'.' -f1)
    local NAME=$(echo "$extension" | cut -d'.' -f2-)

    # Build directory path
    local EXT_DIR="$DOWNLOAD_DIR/$PUBLISHER/$NAME"
    [ "$version" != "latest" ] && EXT_DIR="$EXT_DIR/$version"
    [ -n "$target" ] && EXT_DIR="$EXT_DIR/$target"

    # Separate stable and pre-release versions
    if [ "$prerelease" = "true" ]; then
        EXT_DIR="$EXT_DIR/pre-release"
    else
        EXT_DIR="$EXT_DIR/stable"
    fi

    mkdir -p "$EXT_DIR"

    # Determine download version based on whether we want stable or pre-release
    local download_version="$version"
    if [ "$version" = "latest" ]; then
        if [ "$prerelease" = "false" ]; then
            # For stable versions, find the latest stable version explicitly
            # Use cached stable version search result if available
            if [ "$stable_checked" = "true" ]; then
                if [ -n "$stable_found" ]; then
                    download_version="$stable_found"
                else
                    # Already checked and no stable version found
                    return 1
                fi
            else
                # First time checking - do the search
                echo -e "    ${CYAN}Searching for stable version...${NC}"

                # Try VS Marketplace first (faster)
                local stable_ver=$(find_stable_version_vscode "$extension")

                # If not found in VS Marketplace and not an MS extension, try Open VSX
                if [ -z "$stable_ver" ] && [[ ! "$extension" =~ ^ms- ]]; then
                    stable_ver=$(find_stable_version_openvsx "$extension")
                fi

                if [ -n "$stable_ver" ]; then
                    download_version="$stable_ver"
                    echo -e "    ${BLUE}Found stable version: $stable_ver${NC}"
                else
                    echo -e "    ${YELLOW}No stable version found, skipping stable download${NC}"
                    return 1
                fi
            fi
        else
            # For pre-release, just use "latest" which downloads the most recent version
            download_version="latest"
        fi
    fi

    local downloaded_from_vs=false

    # Try VS Marketplace first (more reliable and up-to-date)
    local VERSION_PATH="${download_version}"
    [ "$VERSION_PATH" = "latest" ] && VERSION_PATH="latest"

    local VSIX_URL="https://${PUBLISHER}.gallery.vsassets.io/_apis/public/gallery/publisher/${PUBLISHER}/extension/${NAME}/${VERSION_PATH}/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage"
    if [ -n "$target" ]; then
        VSIX_URL="${VSIX_URL}?targetPlatform=${target}"
    fi

    local OUTPUT_FILE="$EXT_DIR/${extension}"
    [ "$download_version" != "latest" ] && OUTPUT_FILE="${OUTPUT_FILE}-${download_version}"
    [ -n "$target" ] && OUTPUT_FILE="${OUTPUT_FILE}@${target}"
    OUTPUT_FILE="${OUTPUT_FILE}.vsix"

    echo -e "    ${CYAN}Downloading from VS Marketplace...${NC}"
    if curl -# -L -f "$VSIX_URL" -o "$OUTPUT_FILE"; then
        downloaded_from_vs=true
        local file_size=$(du -h "$OUTPUT_FILE" | cut -f1)

            # Try to download metadata from Open VSX or VS Marketplace API
            local metadata_file="$EXT_DIR/metadata.json"
            if ! ovsx get $extension $([ "$download_version" != "latest" ] && echo "-v $download_version") --metadata -o "$metadata_file" 2>/dev/null; then
                # Get detailed metadata from VS Marketplace API with comprehensive flags
                # flags: 950 = 1+2+4+16+128+256+512 (versions+files+categories+properties+assetUri+statistics+latestOnly)
                local vs_metadata=$(curl -s -X POST 'https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery' \
                  -H 'Content-Type: application/json' \
                  -H 'Accept: application/json;api-version=3.0-preview.1' \
                  -d "{
                    \"filters\": [{
                      \"criteria\": [{\"filterType\": 7, \"value\": \"$extension\"}],
                      \"pageSize\": 1
                    }],
                    \"flags\": 950
                  }" 2>/dev/null)

                # Extract extension info
                local display_name=$(echo "$vs_metadata" | jq -r '.results[0].extensions[0].displayName // ""' 2>/dev/null || echo "")
                local description=$(echo "$vs_metadata" | jq -r '.results[0].extensions[0].shortDescription // ""' 2>/dev/null || echo "")
                local publisher_id=$(echo "$vs_metadata" | jq -r '.results[0].extensions[0].publisher.publisherId // ""' 2>/dev/null || echo "")
                local publisher_display=$(echo "$vs_metadata" | jq -r '.results[0].extensions[0].publisher.displayName // ""' 2>/dev/null || echo "")
                local publisher_verified=$(echo "$vs_metadata" | jq -r '.results[0].extensions[0].publisher.flags // ""' 2>/dev/null | grep -q "verified" && echo "true" || echo "false")
                local publisher_domain=$(echo "$vs_metadata" | jq -r '.results[0].extensions[0].publisher.domain // ""' 2>/dev/null || echo "")
                local categories=$(echo "$vs_metadata" | jq -c '.results[0].extensions[0].categories // []' 2>/dev/null || echo "[]")
                local tags=$(echo "$vs_metadata" | jq -c '.results[0].extensions[0].tags // []' 2>/dev/null || echo "[]")
                local published_date=$(echo "$vs_metadata" | jq -r '.results[0].extensions[0].publishedDate // ""' 2>/dev/null || echo "")
                local last_updated=$(echo "$vs_metadata" | jq -r '.results[0].extensions[0].lastUpdated // ""' 2>/dev/null || echo "")

                # Extract version properties
                local ext_deps=$(echo "$vs_metadata" | jq -r '.results[0].extensions[0].versions[0].properties[]? | select(.key == "Microsoft.VisualStudio.Code.ExtensionDependencies") | .value' 2>/dev/null || echo "")
                local ext_pack=$(echo "$vs_metadata" | jq -r '.results[0].extensions[0].versions[0].properties[]? | select(.key == "Microsoft.VisualStudio.Code.ExtensionPack") | .value' 2>/dev/null || echo "")
                local engine=$(echo "$vs_metadata" | jq -r '.results[0].extensions[0].versions[0].properties[]? | select(.key == "Microsoft.VisualStudio.Code.Engine") | .value' 2>/dev/null || echo "")

                # Extract file URLs
                local icon_url=$(echo "$vs_metadata" | jq -r '.results[0].extensions[0].versions[0].files[]? | select(.assetType == "Microsoft.VisualStudio.Services.Icons.Default") | .source' 2>/dev/null || echo "")
                local readme_url=$(echo "$vs_metadata" | jq -r '.results[0].extensions[0].versions[0].files[]? | select(.assetType == "Microsoft.VisualStudio.Services.Content.Details") | .source' 2>/dev/null || echo "")
                local changelog_url=$(echo "$vs_metadata" | jq -r '.results[0].extensions[0].versions[0].files[]? | select(.assetType == "Microsoft.VisualStudio.Services.Content.Changelog") | .source' 2>/dev/null || echo "")
                local license_url=$(echo "$vs_metadata" | jq -r '.results[0].extensions[0].versions[0].files[]? | select(.assetType == "Microsoft.VisualStudio.Services.Content.License") | .source' 2>/dev/null || echo "")
                local manifest_url=$(echo "$vs_metadata" | jq -r '.results[0].extensions[0].versions[0].files[]? | select(.assetType == "Microsoft.VisualStudio.Code.Manifest") | .source' 2>/dev/null || echo "")

                # Extract statistics
                local downloads=$(echo "$vs_metadata" | jq -r '.results[0].extensions[0].statistics[]? | select(.statisticName == "install") | .value' 2>/dev/null || echo "0")
                local rating=$(echo "$vs_metadata" | jq -r '.results[0].extensions[0].statistics[]? | select(.statisticName == "averagerating") | .value' 2>/dev/null || echo "0")

                # Determine if this is a pre-release version
                local is_prerelease="false"
                [ "$prerelease" = "true" ] && is_prerelease="true"

                # Create comprehensive metadata JSON (similar to Open VSX format)
                cat > "$metadata_file" <<EOF
{
  "namespace": "$PUBLISHER",
  "name": "$NAME",
  "version": "$download_version",
  "displayName": "$display_name",
  "description": "$description",
  "publishedBy": {
    "loginName": "$PUBLISHER",
    "fullName": "$publisher_display",
    "homepage": "$publisher_domain",
    "provider": "vscode-marketplace"
  },
  "verified": $publisher_verified,
  "categories": $categories,
  "tags": $tags,
  "files": {
    "icon": "$icon_url",
    "readme": "$readme_url",
    "changelog": "$changelog_url",
    "license": "$license_url",
    "manifest": "$manifest_url",
    "download": "https://${PUBLISHER}.gallery.vsassets.io/_apis/public/gallery/publisher/${PUBLISHER}/extension/${NAME}/${download_version}/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage"
  },
  "engines": {
    "vscode": "$engine"
  },
  "timestamp": "$last_updated",
  "publishedDate": "$published_date",
  "downloads": $downloads,
  "averageRating": $rating,
  "preRelease": $is_prerelease,
  "extensionDependencies": $(echo "$ext_deps" | jq -R 'split(",") | map(select(. != ""))' 2>/dev/null || echo "[]"),
  "extensionPack": $(echo "$ext_pack" | jq -R 'split(",") | map(select(. != ""))' 2>/dev/null || echo "[]")
}
EOF
            fi

        local version_label="stable"
        [ "$prerelease" = "true" ] && version_label="latest"
        echo -e "    ${GREEN}✓ Downloaded $version_label from VS Marketplace ($file_size)${NC}"
        return 0
    fi

    # Fallback to Open VSX if VS Marketplace failed or for pre-release versions
    if [ "$downloaded_from_vs" = "false" ]; then
        local OVSX_CMD="ovsx get $extension"
        [ "$download_version" != "latest" ] && OVSX_CMD="$OVSX_CMD -v $download_version"
        [ -n "$target" ] && OVSX_CMD="$OVSX_CMD -t $target"
        # Note: ovsx CLI doesn't support --pre-release flag, it downloads latest version

        if (cd "$EXT_DIR" && eval $OVSX_CMD 2>&1 | grep -E "Downloading|Downloaded" || true); then
        # Find the downloaded file
        local downloaded_file=$(find "$EXT_DIR" -name "*.vsix" -type f -mmin -1 | head -1)
        if [ -n "$downloaded_file" ]; then
            # Get file size
            local file_size=$(du -h "$downloaded_file" | cut -f1)

            # Download metadata to check if it's actually pre-release
            local metadata_file="$EXT_DIR/metadata.json"
            (cd "$EXT_DIR" && ovsx get $extension $([ "$download_version" != "latest" ] && echo "-v $download_version") $([ "$prerelease" = "true" ] && echo "--pre-release") --metadata -o metadata.json 2>/dev/null) || true

            # Check if the downloaded version is pre-release
            local is_prerelease="false"
            if [ -f "$metadata_file" ]; then
                is_prerelease=$(jq -r '.preRelease // false' "$metadata_file" 2>/dev/null || echo "false")
            fi

            # Determine correct target directory based on actual pre-release status
            if [ "$is_prerelease" = "true" ]; then
                # This is a pre-release version
                if [ "$prerelease" = "false" ]; then
                    # We wanted stable but got pre-release - no stable version available
                    echo -e "    ${YELLOW}⚠ Only pre-release version available, skipping stable${NC}"
                    rm -f "$downloaded_file" "$metadata_file"
                    return 1
                fi
            else
                # This is a stable version
                if [ "$prerelease" = "true" ]; then
                    # We wanted pre-release but got stable - no pre-release version available
                    echo -e "    ${YELLOW}⚠ No pre-release version available, skipping${NC}"
                    rm -f "$downloaded_file" "$metadata_file"
                    return 1
                fi
            fi

            local version_label="stable"
            [ "$is_prerelease" = "true" ] && version_label="pre-release"
            echo -e "    ${GREEN}✓ Downloaded $version_label from Open VSX ($file_size)${NC}"

            return 0
        fi
        fi
    fi

    return 1
}

echo "Reading extensions from: $EXTENSION_LIST"
echo "Download directory: $DOWNLOAD_DIR"
echo ""
echo "Phase 1: Downloading requested extensions"
echo "=================================================="

# Download requested extensions
while IFS= read -r line || [ -n "$line" ]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    download_extension "$line" "true"
done < "$EXTENSION_LIST"

# Download dependencies
if [ -s "$DEPENDENCY_FILE" ]; then
    echo ""
    echo "Phase 2: Downloading dependencies"
    echo "=================================================="

    ITERATION=1
    while [ -s "$DEPENDENCY_FILE" ]; do
        echo ""
        echo "Iteration $ITERATION:"

        # Create temp file for new dependencies
        TEMP_DEPS=$(mktemp)
        mv "$DEPENDENCY_FILE" "$TEMP_DEPS"
        > "$DEPENDENCY_FILE"

        while IFS= read -r dep; do
            download_extension "$dep" "false"  # Don't download pre-release for deps
        done < "$TEMP_DEPS"

        rm "$TEMP_DEPS"

        # Break if no new dependencies found
        if [ ! -s "$DEPENDENCY_FILE" ]; then
            break
        fi

        ITERATION=$((ITERATION + 1))

        # Safety limit
        if [ $ITERATION -gt 10 ]; then
            echo -e "${YELLOW}Warning: Reached maximum dependency depth${NC}"
            break
        fi
    done
fi

# Summary
echo ""
echo "=================================================="
echo "Download Summary"
echo "=================================================="
echo "Total extensions processed: $TOTAL"
echo -e "${GREEN}Successfully downloaded: $SUCCESS${NC}"
echo -e "${BLUE}Dependencies found: $DEPS_FOUND${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo ""
echo "Extensions saved to: $DOWNLOAD_DIR"
echo ""

if [ $FAILED -gt 0 ]; then
    echo -e "${YELLOW}Warning: Some extensions failed to download.${NC}"
    exit 1
fi

echo -e "${GREEN}All extensions and dependencies downloaded successfully!${NC}"
echo ""
echo "Next steps:"
echo "  1. Copy the '$DOWNLOAD_DIR' directory to USB"
echo "  2. Transfer to offline environment"
echo "  3. Run ./upload-extensions.sh to publish"

# Cleanup
rm -f "$DOWNLOADED_FILE" "$DEPENDENCY_FILE"
