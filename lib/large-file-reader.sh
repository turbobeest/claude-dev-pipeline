#!/bin/bash
# =============================================================================
# Claude Dev Pipeline - Large File Reader for Claude Code Integration
# =============================================================================
#
# This utility provides a workaround for Claude Code's Read tool 25,000 token
# limit by reading large files (e.g., comprehensive PRDs) using standard bash
# tools and outputting the complete content for processing.
#
# Use Case:
#   The PRD-to-Tasks skill and other skills need to read comprehensive PRD
#   documents that often exceed 25,000 tokens (approximately 100,000 characters).
#   This script enables atomic document analysis without chunked reads.
#
# Features:
# - Reads files of any size (no token limit)
# - Outputs complete file content to stdout
# - Validates file existence and readability
# - Provides file metadata (size, line count, estimated tokens)
# - Optional content preview mode
# - Integration with existing file-io.sh infrastructure
#
# Usage:
#   # Direct invocation:
#   ./lib/large-file-reader.sh path/to/large-file.md
#
#   # With metadata:
#   ./lib/large-file-reader.sh path/to/large-file.md --metadata
#
#   # Preview mode (first 1000 lines):
#   ./lib/large-file-reader.sh path/to/large-file.md --preview
#
#   # From skills (in SKILL.md):
#   ```bash
#   content=$(./lib/large-file-reader.sh docs/PRD.md)
#   ```
#
# =============================================================================

set -euo pipefail

# Ensure we're in the project root
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# Source dependencies
source "${PROJECT_ROOT}/lib/logger.sh" 2>/dev/null || true

# =============================================================================
# Configuration
# =============================================================================

# Token estimation (approximate)
# Average: 1 token ≈ 4 characters
CHARS_PER_TOKEN=4
TOKEN_LIMIT_WARNING=25000
TOKEN_LIMIT_CRITICAL=50000

# Preview settings
PREVIEW_LINES=1000

# Output formatting
SHOW_METADATA=false
PREVIEW_MODE=false
QUIET_MODE=false

# =============================================================================
# Helper Functions
# =============================================================================

# Print usage information
usage() {
    cat <<EOF
Usage: $(basename "$0") FILE [OPTIONS]

Read large files that exceed Claude Code's Read tool token limit.

Arguments:
  FILE                  Path to the file to read

Options:
  --metadata, -m        Show file metadata before content
  --preview, -p         Preview mode (first ${PREVIEW_LINES} lines only)
  --quiet, -q           Suppress metadata and warnings (content only)
  --help, -h            Show this help message

Examples:
  # Read entire file
  ./lib/large-file-reader.sh docs/PRD.md

  # Read with metadata header
  ./lib/large-file-reader.sh docs/PRD.md --metadata

  # Preview large file
  ./lib/large-file-reader.sh docs/PRD.md --preview

Environment Variables:
  PROJECT_ROOT          Project root directory (auto-detected)
  CHARS_PER_TOKEN       Characters per token ratio (default: 4)

Exit Codes:
  0     Success
  1     File not found or not readable
  2     Invalid arguments
EOF
}

# Estimate token count from file
estimate_tokens() {
    local file_path="$1"
    local char_count=$(wc -c < "$file_path" | tr -d '[:space:]')
    local token_estimate=$((char_count / CHARS_PER_TOKEN))
    echo "$token_estimate"
}

# Get file statistics
get_file_stats() {
    local file_path="$1"

    local file_size_bytes=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null)
    local file_size_kb=$((file_size_bytes / 1024))
    local file_size_mb=$((file_size_kb / 1024))
    local line_count=$(wc -l < "$file_path" | tr -d '[:space:]')
    local char_count=$(wc -c < "$file_path" | tr -d '[:space:]')
    local token_estimate=$(estimate_tokens "$file_path")

    # Display size in appropriate unit
    local size_display
    if [[ $file_size_mb -gt 0 ]]; then
        size_display="${file_size_mb}MB"
    else
        size_display="${file_size_kb}KB"
    fi

    echo "file_size_bytes=$file_size_bytes"
    echo "file_size_display=$size_display"
    echo "line_count=$line_count"
    echo "char_count=$char_count"
    echo "token_estimate=$token_estimate"
}

# Print metadata header
print_metadata() {
    local file_path="$1"
    local stats="$2"

    local file_size_display=$(echo "$stats" | grep file_size_display | cut -d'=' -f2)
    local line_count=$(echo "$stats" | grep line_count | cut -d'=' -f2)
    local char_count=$(echo "$stats" | grep char_count | cut -d'=' -f2)
    local token_estimate=$(echo "$stats" | grep token_estimate | cut -d'=' -f2)

    cat <<EOF
===============================================================================
LARGE FILE READER - Metadata
===============================================================================
File:             $file_path
Size:             $file_size_display ($char_count characters)
Lines:            $line_count
Estimated Tokens: $token_estimate
-------------------------------------------------------------------------------
EOF

    # Warning messages
    if [[ $token_estimate -gt $TOKEN_LIMIT_CRITICAL ]]; then
        cat <<EOF
⚠️  CRITICAL: This file exceeds ${TOKEN_LIMIT_CRITICAL} tokens (${token_estimate} estimated).
    This file significantly exceeds Claude Code's Read tool limit.
    Using large-file-reader.sh to bypass the limitation.
-------------------------------------------------------------------------------
EOF
    elif [[ $token_estimate -gt $TOKEN_LIMIT_WARNING ]]; then
        cat <<EOF
⚠️  WARNING: This file exceeds ${TOKEN_LIMIT_WARNING} tokens (${token_estimate} estimated).
    This file exceeds Claude Code's Read tool limit.
    Using large-file-reader.sh to bypass the limitation.
-------------------------------------------------------------------------------
EOF
    fi

    if [[ "$PREVIEW_MODE" == "true" ]]; then
        cat <<EOF
📄 PREVIEW MODE: Showing first ${PREVIEW_LINES} lines only.
-------------------------------------------------------------------------------
EOF
    fi

    echo ""
}

# =============================================================================
# Main Functionality
# =============================================================================

# Read and output file content
read_file() {
    local file_path="$1"

    # Validate file exists and is readable
    if [[ ! -f "$file_path" ]]; then
        echo "ERROR: File not found: $file_path" >&2
        return 1
    fi

    if [[ ! -r "$file_path" ]]; then
        echo "ERROR: File not readable: $file_path" >&2
        return 1
    fi

    # Get file statistics
    local stats=$(get_file_stats "$file_path")
    local token_estimate=$(echo "$stats" | grep token_estimate | cut -d'=' -f2)

    # Print metadata if requested
    if [[ "$SHOW_METADATA" == "true" ]] || [[ "$QUIET_MODE" == "false" && $token_estimate -gt $TOKEN_LIMIT_WARNING ]]; then
        print_metadata "$file_path" "$stats" >&2
    fi

    # Log operation (if logger is available)
    if command -v log_info >/dev/null 2>&1; then
        log_info "Reading large file" "file=$file_path" "tokens=$token_estimate" "preview=$PREVIEW_MODE"
    fi

    # Read and output content
    if [[ "$PREVIEW_MODE" == "true" ]]; then
        head -n "$PREVIEW_LINES" "$file_path"
        echo "" >&2
        echo "... [Content truncated - ${PREVIEW_LINES} of $(wc -l < "$file_path" | tr -d '[:space:]') lines shown]" >&2
    else
        cat "$file_path"
    fi

    return 0
}

# =============================================================================
# Argument Parsing
# =============================================================================

# Parse command line arguments
parse_args() {
    local file_path=""

    if [[ $# -eq 0 ]]; then
        usage
        exit 2
    fi

    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                usage
                exit 0
                ;;
            --metadata|-m)
                SHOW_METADATA=true
                shift
                ;;
            --preview|-p)
                PREVIEW_MODE=true
                shift
                ;;
            --quiet|-q)
                QUIET_MODE=true
                shift
                ;;
            -*)
                echo "ERROR: Unknown option: $1" >&2
                echo "Use --help for usage information." >&2
                exit 2
                ;;
            *)
                if [[ -z "$file_path" ]]; then
                    file_path="$1"
                else
                    echo "ERROR: Multiple file paths provided" >&2
                    echo "Use --help for usage information." >&2
                    exit 2
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$file_path" ]]; then
        echo "ERROR: File path required" >&2
        echo "Use --help for usage information." >&2
        exit 2
    fi

    echo "$file_path"
}

# =============================================================================
# Main Entry Point
# =============================================================================

main() {
    # Handle help/usage separately to avoid exit in subshell
    if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
        usage
        exit 0
    fi

    # Parse arguments
    local file_path=$(parse_args "$@")

    # Read and output file
    read_file "$file_path"
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
