#!/bin/bash

# Script to pull projects/ocap from open-world-agents repository
# Usage: ./pull.sh [branch] [commit_hash]
# Examples:
#   ./pull.sh                    # Pull from main branch (latest)
#   ./pull.sh main               # Pull from main branch (latest)
#   ./pull.sh develop            # Pull from develop branch (latest)
#   ./pull.sh main abc123        # Pull specific commit from main branch
#   ./pull.sh "" abc123          # Pull specific commit from default branch

set -e  # Exit on any error

# Function to show usage
show_help() {
    echo "Usage: $0 [branch] [commit_hash]"
    echo ""
    echo "Pull projects/ocap and scripts/release from open-world-agents repository"
    echo ""
    echo "Arguments:"
    echo "  branch       Branch to pull from (default: main)"
    echo "  commit_hash  Specific commit hash to checkout (optional)"
    echo ""
    echo "Examples:"
    echo "  $0                    # Pull from main branch (latest)"
    echo "  $0 main               # Pull from main branch (latest)"
    echo "  $0 develop            # Pull from develop branch (latest)"
    echo "  $0 main abc123        # Pull specific commit from main branch"
    echo "  $0 \"\" abc123          # Pull specific commit from default branch"
    echo "  $0 --help             # Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  KEEP_TEMP=1           # Keep temporary directory for debugging"
    echo ""
    echo "Features:"
    echo "  - Automatic removal of existing directories"
    echo "  - Creates pulled_version_info.txt with commit details"
    echo ""
}

# Check for help flag
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_help
    exit 0
fi

# Parse command line arguments
BRANCH="${1:-main}"  # Default to main branch if not specified
COMMIT_HASH="${2:-}" # Optional commit hash

# Configuration
REPO_URL="https://github.com/open-world-agents/open-world-agents"
TEMP_DIR="temp_owa_clone_$(date +%Y%m%d_%H%M%S)_$$"  # Unique temp dir with timestamp and PID
TARGET_DIRS=("projects/ocap" "scripts/release")
PATCH_FILE="patch.patch"

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

print_status "Starting pull process..."

# Display what we're pulling
if [ -n "$COMMIT_HASH" ]; then
    if [ -n "$BRANCH" ] && [ "$BRANCH" != "main" ]; then
        print_status "Target: commit $COMMIT_HASH from branch '$BRANCH'"
    else
        print_status "Target: commit $COMMIT_HASH"
    fi
else
    print_status "Target: latest from branch '$BRANCH'"
fi

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

if [ -n "$COMMIT_HASH" ]; then
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
else
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
fi

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
cat > "$VERSION_FILE" << EOF
# Pulled Version Information
# Generated on: $(date)
# Repository: $REPO_URL

COMMIT_HASH=$ACTUAL_COMMIT
BRANCH=$ACTUAL_BRANCH
COMMIT_DATE=$COMMIT_DATE
COMMIT_MESSAGE=$COMMIT_MESSAGE

# Directories pulled:
$(for dir in "${TARGET_DIRS[@]}"; do echo "# - $dir"; done)

# To reproduce this exact pull:
# ./pull.sh $ACTUAL_BRANCH $ACTUAL_COMMIT
EOF

print_success "Successfully pulled required directories from repository"
print_status "Version info saved to: $VERSION_FILE"

# Show summary of changes
print_status "Summary of changes:"
if [ -n "$COMMIT_HASH" ]; then
    if [ -n "$BRANCH" ] && [ "$BRANCH" != "main" ]; then
        echo "- Pulled directories from $REPO_URL (commit $COMMIT_HASH from branch '$BRANCH'):"
    else
        echo "- Pulled directories from $REPO_URL (commit $COMMIT_HASH):"
    fi
else
    echo "- Pulled latest directories from $REPO_URL (branch '$BRANCH'):"
fi
for TARGET_DIR in "${TARGET_DIRS[@]}"; do
    echo "  - $TARGET_DIR"
done
echo "- Version information saved to $VERSION_FILE"
echo ""
print_status "Actual commit pulled: $ACTUAL_COMMIT"
print_status "Actual branch: $ACTUAL_BRANCH"
print_status "Commit date: $COMMIT_DATE"

print_success "Pull process completed!"
print_status "To apply patches, run: ./patch.sh"