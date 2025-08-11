#!/bin/bash

# Script to pull projects/ocap from open-world-agents repository
# Usage: ./pull.sh [version|branch] [commit_hash]
# Examples:
#   ./pull.sh                    # Pull from latest release
#   ./pull.sh v1.2.3             # Pull specific release version
#   ./pull.sh main               # Pull from main branch (latest)
#   ./pull.sh develop            # Pull from develop branch (latest)
#   ./pull.sh main abc123        # Pull specific commit from main branch
#   ./pull.sh "" abc123          # Pull specific commit from default branch

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_help() {
    echo "Usage: $0 [version|branch] [commit_hash]"
    echo ""
    echo "Pull projects/ocap and scripts/release from open-world-agents repository"
    echo ""
    echo "Arguments:"
    echo "  version|branch  Release version (e.g., v1.2.3) or branch name (default: latest release)"
    echo "  commit_hash     Specific commit hash to checkout (optional, overrides version/branch)"
    echo ""
    echo "Examples:"
    echo "  $0                    # Pull from latest release"
    echo "  $0 v1.2.3             # Pull specific release version"
    echo "  $0 main               # Pull from main branch (latest)"
    echo "  $0 develop            # Pull from develop branch (latest)"
    echo "  $0 main abc123        # Pull specific commit from main branch"
    echo "  $0 \"\" abc123          # Pull specific commit from default branch"
    echo "  $0 --help             # Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  KEEP_TEMP=1           # Keep temporary directory for debugging"
    echo "  RELEASE_VERSION=v1.2.3 # Specify release version via environment variable"
    echo ""
    echo "Features:"
    echo "  - Automatic fetching of latest release if no version specified"
    echo "  - Support for specific release versions"
    echo "  - Automatic removal of existing directories"
    echo "  - Creates pulled_version_info.txt with release/commit details"
    echo ""
}

# Check for help flag
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_help
    exit 0
fi

# Function to fetch latest release from GitHub API
fetch_latest_release() {
    local api_url="https://api.github.com/repos/open-world-agents/open-world-agents/releases/latest"

    # Try to fetch release info with curl
    if command -v curl >/dev/null 2>&1; then
        local response=$(curl -s --max-time 10 "$api_url" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$response" ]; then
            # Extract tag_name from JSON response
            local tag_name=$(echo "$response" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
            if [ -n "$tag_name" ]; then
                echo "$tag_name"
                return 0
            fi
        fi
    fi

    # Try with wget if curl failed
    if command -v wget >/dev/null 2>&1; then
        local response=$(wget -qO- --timeout=10 "$api_url" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$response" ]; then
            # Extract tag_name from JSON response
            local tag_name=$(echo "$response" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
            if [ -n "$tag_name" ]; then
                echo "$tag_name"
                return 0
            fi
        fi
    fi

    return 1
}

# Function to check if a string looks like a version tag
is_version_tag() {
    local input="$1"
    # Check if it starts with 'v' followed by digits and dots, or just digits and dots
    if [[ "$input" =~ ^v?[0-9]+(\.[0-9]+)*(-.*)?$ ]]; then
        return 0
    fi
    return 1
}

# Parse command line arguments and environment variables
VERSION_OR_BRANCH="${1:-}"
COMMIT_HASH="${2:-}"

# Check environment variable for release version
if [ -z "$VERSION_OR_BRANCH" ] && [ -n "$RELEASE_VERSION" ]; then
    VERSION_OR_BRANCH="$RELEASE_VERSION"
    print_status "Using release version from environment variable: $RELEASE_VERSION"
fi

# Determine what we're pulling
RELEASE_TAG=""
BRANCH=""
PULL_MODE=""

if [ -n "$COMMIT_HASH" ]; then
    # If commit hash is specified, use it directly
    PULL_MODE="commit"
    BRANCH="${VERSION_OR_BRANCH:-main}"
    print_status "Pull mode: specific commit"
elif [ -z "$VERSION_OR_BRANCH" ]; then
    # No version/branch specified, fetch latest release
    PULL_MODE="latest_release"
    print_status "Fetching latest release information from GitHub API..."
    RELEASE_TAG=$(fetch_latest_release)
    if [ $? -ne 0 ]; then
        print_error "Failed to fetch latest release information from GitHub API"
        print_error "Please check your internet connection or specify a version/branch manually"
        print_warning "Falling back to main branch"
        PULL_MODE="branch"
        BRANCH="main"
    else
        print_success "Latest release found: $RELEASE_TAG"
    fi
elif is_version_tag "$VERSION_OR_BRANCH"; then
    # Version tag specified
    PULL_MODE="release"
    RELEASE_TAG="$VERSION_OR_BRANCH"
    print_status "Pull mode: specific release version ($RELEASE_TAG)"
else
    # Branch name specified
    PULL_MODE="branch"
    BRANCH="$VERSION_OR_BRANCH"
    print_status "Pull mode: branch ($BRANCH)"
fi

# Configuration
REPO_URL="https://github.com/open-world-agents/open-world-agents"
TEMP_DIR="temp_owa_clone_$(date +%Y%m%d_%H%M%S)_$$"  # Unique temp dir with timestamp and PID
TARGET_DIRS=("projects/ocap" "scripts/release")

# Function to cleanup temporary directory
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        # Check if user wants to keep temp directory for debugging
        if [ "$KEEP_TEMP" = "1" ]; then
            print_status "Keeping temporary directory for debugging: $TEMP_DIR"
            return
        fi

        print_status "Cleaning up temporary directory..."

        # Git creates read-only files that need special handling
        if [ -d "$TEMP_DIR/.git" ]; then
            # Make .git directory and all contents writable
            find "$TEMP_DIR" -type d -exec chmod 755 {} \; 2>/dev/null || true
            find "$TEMP_DIR" -type f -exec chmod 644 {} \; 2>/dev/null || true
        fi

        # Force removal with better error handling
        rm -rf "$TEMP_DIR" 2>/dev/null || {
            print_warning "Could not fully clean up temporary directory '$TEMP_DIR'."
            print_status "You can manually remove it with: rm -rf '$TEMP_DIR' or sudo rm -rf '$TEMP_DIR'"
        }
    fi
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Validate commit hash format if provided
if [ -n "$COMMIT_HASH" ]; then
    if ! [[ "$COMMIT_HASH" =~ ^[a-fA-F0-9]{6,40}$ ]]; then
        print_error "Invalid commit hash format: $COMMIT_HASH"
        print_status "Commit hash should be 6-40 hexadecimal characters"
        exit 1
    fi
fi

# Validate release tag format if provided
if [ -n "$RELEASE_TAG" ] && [ "$PULL_MODE" = "release" ]; then
    if [ -z "$RELEASE_TAG" ]; then
        print_error "Invalid release tag: empty"
        exit 1
    fi
fi

print_status "Starting pull process..."

# Display what we're pulling
case "$PULL_MODE" in
    "commit")
        if [ -n "$BRANCH" ] && [ "$BRANCH" != "main" ]; then
            print_status "Target: commit $COMMIT_HASH from branch '$BRANCH'"
        else
            print_status "Target: commit $COMMIT_HASH"
        fi
        ;;
    "latest_release")
        print_status "Target: latest release ($RELEASE_TAG)"
        ;;
    "release")
        print_status "Target: release version $RELEASE_TAG"
        ;;
    "branch")
        print_status "Target: latest from branch '$BRANCH'"
        ;;
esac

# Clean up any existing temporary directory
if [ -d "$TEMP_DIR" ]; then
    print_status "Removing existing temporary directory..."
    rm -rf "$TEMP_DIR"
fi

# Remove existing directories if they exist
for TARGET_DIR in "${TARGET_DIRS[@]}"; do
    if [ -d "$TARGET_DIR" ]; then
        print_warning "Removing existing '$TARGET_DIR'"
        rm -rf "$TARGET_DIR"
    fi
done

# Clone the repository to temporary directory
print_status "Cloning repository from $REPO_URL..."

case "$PULL_MODE" in
    "commit")
        # Clone with full history if we need a specific commit
        print_status "Cloning full repository to access specific commit..."
        if ! git clone "$REPO_URL" "$TEMP_DIR"; then
            print_error "Failed to clone repository!"
            exit 1
        fi

        # Navigate to the cloned directory
        cd "$TEMP_DIR"

        # Checkout the specific branch if provided and different from main
        if [ -n "$BRANCH" ] && [ "$BRANCH" != "main" ]; then
            print_status "Switching to branch '$BRANCH'..."
            if ! git checkout "$BRANCH"; then
                print_error "Failed to checkout branch '$BRANCH'!"
                cd ..
                exit 1
            fi
        fi

        # Checkout the specific commit
        print_status "Checking out commit $COMMIT_HASH..."
        if ! git checkout "$COMMIT_HASH"; then
            print_error "Failed to checkout commit '$COMMIT_HASH'!"
            print_status "Make sure the commit hash exists in the specified branch."
            cd ..
            exit 1
        fi

        # Return to original directory
        cd ..
        ;;
    "latest_release"|"release")
        # Clone with full history to access release tags
        print_status "Cloning full repository to access release tag..."
        if ! git clone "$REPO_URL" "$TEMP_DIR"; then
            print_error "Failed to clone repository!"
            exit 1
        fi

        # Navigate to the cloned directory
        cd "$TEMP_DIR"

        # Checkout the specific release tag
        print_status "Checking out release tag $RELEASE_TAG..."
        if ! git checkout "tags/$RELEASE_TAG"; then
            print_error "Failed to checkout release tag '$RELEASE_TAG'!"
            print_status "Make sure the release tag exists in the repository."
            print_status "Available tags:"
            git tag --list | head -10
            cd ..
            exit 1
        fi

        # Return to original directory
        cd ..
        ;;
    "branch")
        # Use shallow clone for latest commit on branch
        if [ "$BRANCH" = "main" ]; then
            if ! git clone --depth 1 "$REPO_URL" "$TEMP_DIR"; then
                print_error "Failed to clone repository!"
                exit 1
            fi
        else
            if ! git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$TEMP_DIR"; then
                print_error "Failed to clone repository from branch '$BRANCH'!"
                print_status "Make sure the branch exists in the repository."
                exit 1
            fi
        fi
        ;;
esac

# Check if the required directories exist in the cloned repo
for TARGET_DIR in "${TARGET_DIRS[@]}"; do
    if [ ! -d "$TEMP_DIR/$TARGET_DIR" ]; then
        print_error "Directory '$TARGET_DIR' not found in the cloned repository!"
        exit 1
    fi
done

# Get commit information from the cloned repository
cd "$TEMP_DIR"
ACTUAL_COMMIT=$(git rev-parse HEAD)
ACTUAL_BRANCH=$(git branch --show-current 2>/dev/null || git symbolic-ref --short HEAD 2>/dev/null || echo "detached")
COMMIT_DATE=$(git log -1 --format="%ci" HEAD)
COMMIT_MESSAGE=$(git log -1 --format="%s" HEAD)

# Get release tag information if we're on a release
ACTUAL_RELEASE_TAG=""
if [ "$PULL_MODE" = "latest_release" ] || [ "$PULL_MODE" = "release" ]; then
    ACTUAL_RELEASE_TAG="$RELEASE_TAG"
    # Verify we're actually on the tag
    CURRENT_TAG=$(git describe --exact-match --tags HEAD 2>/dev/null || echo "")
    if [ -n "$CURRENT_TAG" ]; then
        ACTUAL_RELEASE_TAG="$CURRENT_TAG"
    fi
fi

cd ..

# Copy the required directories
for TARGET_DIR in "${TARGET_DIRS[@]}"; do
    print_status "Copying $TARGET_DIR directory..."
    mkdir -p "$(dirname "$TARGET_DIR")"
    cp -r "$TEMP_DIR/$TARGET_DIR" "$TARGET_DIR"
done

# Create version info file
VERSION_FILE="pulled_version_info.txt"
print_status "Creating version info file: $VERSION_FILE"

# Create the version info content
VERSION_INFO_CONTENT="# Pulled Version Information
# Generated on: $(date)
# Repository: $REPO_URL
# Pull timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

COMMIT_HASH=$ACTUAL_COMMIT
BRANCH=$ACTUAL_BRANCH
COMMIT_DATE=$COMMIT_DATE
COMMIT_MESSAGE=$COMMIT_MESSAGE"

# Add release tag information if applicable
if [ -n "$ACTUAL_RELEASE_TAG" ]; then
    VERSION_INFO_CONTENT="$VERSION_INFO_CONTENT
RELEASE_TAG=$ACTUAL_RELEASE_TAG
PULL_MODE=$PULL_MODE"
else
    VERSION_INFO_CONTENT="$VERSION_INFO_CONTENT
PULL_MODE=$PULL_MODE"
fi

# Add directories and reproduction instructions
VERSION_INFO_CONTENT="$VERSION_INFO_CONTENT

# Directories pulled:
$(for dir in "${TARGET_DIRS[@]}"; do echo "# - $dir"; done)"

# Add reproduction instructions based on pull mode
case "$PULL_MODE" in
    "latest_release")
        VERSION_INFO_CONTENT="$VERSION_INFO_CONTENT

# To reproduce this exact pull:
# ./pull.sh $ACTUAL_RELEASE_TAG
# or
# ./pull.sh $ACTUAL_BRANCH $ACTUAL_COMMIT"
        ;;
    "release")
        VERSION_INFO_CONTENT="$VERSION_INFO_CONTENT

# To reproduce this exact pull:
# ./pull.sh $ACTUAL_RELEASE_TAG
# or
# ./pull.sh $ACTUAL_BRANCH $ACTUAL_COMMIT"
        ;;
    "commit")
        VERSION_INFO_CONTENT="$VERSION_INFO_CONTENT

# To reproduce this exact pull:
# ./pull.sh $ACTUAL_BRANCH $ACTUAL_COMMIT"
        ;;
    "branch")
        VERSION_INFO_CONTENT="$VERSION_INFO_CONTENT

# To reproduce this exact pull:
# ./pull.sh $ACTUAL_BRANCH $ACTUAL_COMMIT"
        ;;
esac

# Write the version info file
echo "$VERSION_INFO_CONTENT" > "$VERSION_FILE"

print_success "Successfully pulled required directories from repository"
print_status "Version info saved to: $VERSION_FILE"

# Show summary of changes
print_status "Summary of changes:"
case "$PULL_MODE" in
    "latest_release")
        echo "- Pulled directories from $REPO_URL (latest release $ACTUAL_RELEASE_TAG):"
        ;;
    "release")
        echo "- Pulled directories from $REPO_URL (release $ACTUAL_RELEASE_TAG):"
        ;;
    "commit")
        if [ -n "$BRANCH" ] && [ "$BRANCH" != "main" ]; then
            echo "- Pulled directories from $REPO_URL (commit $COMMIT_HASH from branch '$BRANCH'):"
        else
            echo "- Pulled directories from $REPO_URL (commit $COMMIT_HASH):"
        fi
        ;;
    "branch")
        echo "- Pulled latest directories from $REPO_URL (branch '$BRANCH'):"
        ;;
esac

for TARGET_DIR in "${TARGET_DIRS[@]}"; do
    echo "  - $TARGET_DIR"
done
echo "- Version information saved to $VERSION_FILE"
echo ""

# Display detailed information
print_status "Actual commit pulled: $ACTUAL_COMMIT"
print_status "Actual branch: $ACTUAL_BRANCH"
if [ -n "$ACTUAL_RELEASE_TAG" ]; then
    print_status "Release tag: $ACTUAL_RELEASE_TAG"
fi
print_status "Commit date: $COMMIT_DATE"
print_status "Pull mode: $PULL_MODE"

print_success "Pull process completed!"
print_status "To apply patches, run: ./patch.sh"