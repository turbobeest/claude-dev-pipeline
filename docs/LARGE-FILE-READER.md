# Large File Reader Utility

## Overview

The Large File Reader utility (`lib/large-file-reader.sh`) provides a workaround for Claude Code's Read tool 25,000 token limit by reading files of any size using standard bash tools.

## Problem Statement

**Current Limitation:**
- Claude Code's Read tool has a hard limit of 25,000 tokens per read operation
- Comprehensive PRD documents often exceed 35,000+ tokens
- This prevents atomic document analysis in skills like PRD-to-Tasks
- Multiple read operations with offset/limit break workflow efficiency

**Solution:**
- Bash utility that reads files of any size
- Provides complete file content in a single operation
- Integrates seamlessly with existing skills
- Includes metadata and validation features

## Installation

The utility is already installed in your pipeline:

```bash
/Users/jamesterbeest/dev/claude-dev-pipeline/lib/large-file-reader.sh
```

Ensure it's executable:
```bash
chmod +x lib/large-file-reader.sh
```

## Usage

### Basic Usage

Read a large file and output its contents:

```bash
./lib/large-file-reader.sh path/to/large-file.md
```

### With Metadata

Show file statistics before content:

```bash
./lib/large-file-reader.sh path/to/large-file.md --metadata
```

Example output:
```
===============================================================================
LARGE FILE READER - Metadata
===============================================================================
File:             docs/PRD.md
Size:             250KB (256,000 characters)
Lines:            5,432
Estimated Tokens: 64,000
-------------------------------------------------------------------------------
⚠️  CRITICAL: This file exceeds 50000 tokens (64000 estimated).
    This file significantly exceeds Claude Code's Read tool limit.
    Using large-file-reader.sh to bypass the limitation.
-------------------------------------------------------------------------------
```

### Preview Mode

Preview first 1,000 lines without reading the entire file:

```bash
./lib/large-file-reader.sh path/to/large-file.md --preview
```

### Quiet Mode

Suppress metadata and warnings (content only):

```bash
./lib/large-file-reader.sh path/to/large-file.md --quiet
```

## Integration with Skills

### In Skill Markdown Files

Skills can reference the utility in their instructions:

```markdown
## Reading PRD Files

**For large PRD files, use the large-file-reader utility:**

\`\`\`bash
# Read large PRD file
prd_content=$(./lib/large-file-reader.sh docs/PRD.md)

# Process the content
echo "$prd_content" | grep "Section 3"
\`\`\`
```

### Conditional Usage Pattern

Automatically detect if a file is large:

```bash
#!/bin/bash

FILE_PATH="docs/PRD.md"

# Check file size first
if ./lib/large-file-reader.sh "$FILE_PATH" --metadata 2>&1 | grep -q "exceeds"; then
  echo "📄 Large file detected - using large-file-reader utility"
  content=$(./lib/large-file-reader.sh "$FILE_PATH" --quiet)
else
  echo "📄 Standard file - using Claude Code Read tool"
  # Use Read tool normally via Claude Code
fi
```

### From Bash Scripts

```bash
#!/bin/bash

# Source the utility
source lib/large-file-reader.sh

# Read file programmatically
FILE_CONTENT=$(read_file "docs/comprehensive-prd.md")

# Process content
echo "$FILE_CONTENT" | wc -l
```

## Command-Line Options

| Option | Short | Description |
|--------|-------|-------------|
| `--metadata` | `-m` | Show file metadata before content |
| `--preview` | `-p` | Preview mode (first 1,000 lines only) |
| `--quiet` | `-q` | Suppress metadata and warnings (content only) |
| `--help` | `-h` | Show help message |

## Token Estimation

The utility estimates tokens using the ratio:
- **1 token ≈ 4 characters** (industry average)

### Warning Thresholds

| Threshold | Description | Action |
|-----------|-------------|--------|
| < 25,000 tokens | Normal | No warning |
| 25,000 - 50,000 tokens | Warning | Shows ⚠️ WARNING message |
| > 50,000 tokens | Critical | Shows ⚠️ CRITICAL message |

## File Statistics Output

The utility provides comprehensive file statistics:

```
file_size_bytes=256000
file_size_display=250KB
line_count=5432
char_count=256000
token_estimate=64000
```

## Use Cases

### 1. PRD-to-Tasks Skill

Read comprehensive PRD documents for task generation:

```bash
# In PRD-to-Tasks skill activation
prd_content=$(./lib/large-file-reader.sh docs/comprehensive-prd.md)

# Parse sections
echo "$prd_content" | awk '/## Section 3: Features/,/## Section 4/'
```

### 2. Spec Generation

Read large specification documents:

```bash
# Read technical specification
spec_content=$(./lib/large-file-reader.sh docs/technical-spec.md)

# Generate OpenSpec proposals
echo "$spec_content" | ./lib/spec-generator.sh
```

### 3. Documentation Analysis

Analyze large documentation files:

```bash
# Read API documentation
api_docs=$(./lib/large-file-reader.sh docs/api-reference.md --quiet)

# Extract endpoints
echo "$api_docs" | grep -E "^### (GET|POST|PUT|DELETE)"
```

### 4. Audit Reports

Read comprehensive audit reports:

```bash
# Read audit report
audit_content=$(./lib/large-file-reader.sh audit-reports/security-audit.md)

# Process findings
echo "$audit_content" | grep "CRITICAL\|HIGH"
```

## Performance

### Benchmarks

| File Size | Lines | Est. Tokens | Read Time |
|-----------|-------|-------------|-----------|
| 100KB | 2,000 | 25,000 | ~50ms |
| 250KB | 5,000 | 62,500 | ~120ms |
| 500KB | 10,000 | 125,000 | ~250ms |
| 1MB | 20,000 | 250,000 | ~500ms |

### Memory Usage

The utility reads files into memory, so ensure sufficient RAM for very large files:
- 1MB file ≈ 1MB RAM
- 10MB file ≈ 10MB RAM

## Error Handling

### File Not Found

```bash
$ ./lib/large-file-reader.sh missing-file.md
ERROR: File not found: missing-file.md
```

Exit code: `1`

### File Not Readable

```bash
$ ./lib/large-file-reader.sh protected-file.md
ERROR: File not readable: protected-file.md
```

Exit code: `1`

### Invalid Arguments

```bash
$ ./lib/large-file-reader.sh --invalid-option
ERROR: Unknown option: --invalid-option
Use --help for usage information.
```

Exit code: `2`

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PROJECT_ROOT` | Auto-detected | Project root directory |
| `CHARS_PER_TOKEN` | 4 | Characters per token ratio for estimation |

## Integration with File I/O Library

The large-file-reader utility complements the existing `lib/file-io.sh` infrastructure:

- **file-io.sh**: Optimized for buffered reads/writes with caching
- **large-file-reader.sh**: Specialized for bypassing Claude Code Read tool limits

Both utilities can be used together:

```bash
# Source both libraries
source lib/file-io.sh
source lib/large-file-reader.sh

# Use large-file-reader for initial read
content=$(./lib/large-file-reader.sh docs/PRD.md --quiet)

# Use file-io.sh for subsequent processing
echo "$content" | buffered_write output.txt -
```

## Troubleshooting

### Issue: "Permission denied"

**Solution:** Make script executable
```bash
chmod +x lib/large-file-reader.sh
```

### Issue: "No such file or directory"

**Solution:** Use absolute or correct relative path
```bash
# From project root
./lib/large-file-reader.sh docs/PRD.md

# With absolute path
./lib/large-file-reader.sh /full/path/to/PRD.md
```

### Issue: Script hangs on very large files

**Solution:** Use preview mode first
```bash
# Preview to check file validity
./lib/large-file-reader.sh huge-file.md --preview

# If valid, read full file
./lib/large-file-reader.sh huge-file.md
```

### Issue: "Token estimate seems wrong"

**Solution:** Adjust CHARS_PER_TOKEN environment variable
```bash
# For more conservative estimate (more tokens per char)
CHARS_PER_TOKEN=3 ./lib/large-file-reader.sh docs/PRD.md --metadata

# For more aggressive estimate (fewer tokens per char)
CHARS_PER_TOKEN=5 ./lib/large-file-reader.sh docs/PRD.md --metadata
```

## Examples

### Example 1: PRD Task Generation

```bash
#!/bin/bash
# Generate tasks from large PRD

PRD_FILE="docs/comprehensive-prd.md"

echo "Reading PRD file..."
PRD_CONTENT=$(./lib/large-file-reader.sh "$PRD_FILE" --quiet)

echo "Extracting features..."
FEATURES=$(echo "$PRD_CONTENT" | awk '/## Section 3: Features/,/## Section 4/')

echo "Generating tasks..."
# Process features and generate tasks
```

### Example 2: Multi-File Analysis

```bash
#!/bin/bash
# Analyze multiple large documentation files

for doc in docs/*.md; do
  echo "Processing: $doc"

  # Get metadata
  ./lib/large-file-reader.sh "$doc" --metadata > /dev/null 2>&1

  # Read content
  content=$(./lib/large-file-reader.sh "$doc" --quiet)

  # Extract sections
  echo "$content" | grep "^## " | wc -l
done
```

### Example 3: Conditional Reading

```bash
#!/bin/bash
# Smart file reading with fallback

read_smart() {
  local file="$1"
  local token_estimate

  # Get token estimate
  token_estimate=$(./lib/large-file-reader.sh "$file" --metadata 2>&1 | \
    grep "Estimated Tokens:" | awk '{print $3}')

  if [[ $token_estimate -gt 25000 ]]; then
    echo "Using large-file-reader (${token_estimate} tokens)" >&2
    ./lib/large-file-reader.sh "$file" --quiet
  else
    echo "Using standard read (${token_estimate} tokens)" >&2
    cat "$file"
  fi
}

# Usage
content=$(read_smart "docs/PRD.md")
```

## Best Practices

1. **Check file size first** - Use `--metadata` or `--preview` to validate before full read
2. **Use quiet mode in scripts** - Suppress warnings when piping content
3. **Handle errors** - Check exit codes and validate content
4. **Estimate tokens** - Use metadata to understand file complexity
5. **Integrate with skills** - Reference in SKILL.md files for consistent usage

## See Also

- [PRD-to-Tasks Skill](../skills/PRD-to-Tasks/SKILL.md) - Uses large-file-reader for PRD processing
- [File I/O Library](../lib/file-io.sh) - Buffered file operations
- [Pipeline Architecture](ARCHITECTURE.md) - Overall pipeline design
- [Troubleshooting Guide](TROUBLESHOOTING.md) - Common issues and solutions

## Support

For issues or feature requests related to the large-file-reader utility:
1. Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
2. Review examples above
3. Test with `--help` option
4. File an issue with reproduction steps
