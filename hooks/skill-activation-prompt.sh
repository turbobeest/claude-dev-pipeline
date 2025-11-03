#!/bin/bash
# =============================================================================
# Skill Activation Hook - Minimal Version with Large PRD Detection
# =============================================================================

# Debug logging
echo "[$(date)] Hook called" >> /tmp/claude-hook-debug.log

# Read input from stdin
INPUT=$(cat 2>/dev/null || echo '{}')

# Extract and lowercase the message
if command -v jq >/dev/null 2>&1; then
    MESSAGE=$(echo "$INPUT" | jq -r '.message // ""' 2>/dev/null | tr '[:upper:]' '[:lower:]')
else
    MESSAGE=""
fi

# Check for "begin automated development" pattern
if echo "$MESSAGE" | grep -qi "begin.*automated.*development\|completed.*prd\|start.*pipeline"; then
    # Check for large PRD files
    for prd_path in "docs/PRD.md" "PRD.md" "docs/prd.md"; do
        if [ -f "$prd_path" ]; then
            file_size=$(wc -c < "$prd_path" 2>/dev/null || echo "0")
            estimated_tokens=$((file_size * 3 / 4))

            if [ "$estimated_tokens" -gt 25000 ]; then
                echo "⚠️ **LARGE PRD DETECTED**"
                echo ""
                echo "The PRD at \`$prd_path\` is approximately $estimated_tokens tokens."
                echo "This exceeds the 25,000 token Read tool limit."
                echo ""
                echo "**CRITICAL:** You MUST use the large-file-reader tool first:"
                echo "\`\`\`bash"
                echo "./.claude/lib/large-file-reader.sh $prd_path"
                echo "\`\`\`"
                echo ""
                echo "**Do NOT:**"
                echo "- Use the Read tool directly on $prd_path"
                echo "- Invoke TaskMaster until AFTER reading the full PRD with large-file-reader"
                echo ""
                echo "**Workflow:**"
                echo "1. Run large-file-reader.sh to read PRD in chunks"
                echo "2. Analyze and understand the full requirements"
                echo "3. THEN invoke TaskMaster to parse and generate tasks"
                echo ""
                echo "---"
                echo ""
                break
            fi
        fi
    done
fi

# Always succeed
exit 0
