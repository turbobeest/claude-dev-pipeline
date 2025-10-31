#!/bin/bash
# =============================================================================
# Pre-Code Generation Directive Hook
# Injects anti-mock directives before any code generation
# =============================================================================

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(pwd)"

# Colors
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Check if we're about to generate code
if [[ "${CLAUDE_PHASE:-}" == "PHASE3" ]] || [[ "${CLAUDE_PHASE:-}" == "implementation" ]]; then
    echo ""
    echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}${BOLD}  CRITICAL DIRECTIVE: NO MOCK IMPLEMENTATIONS${NC}"
    echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}MANDATORY REQUIREMENTS:${NC}"
    echo ""
    echo "1. ${BOLD}NO MOCK IMPLEMENTATIONS${NC}"
    echo "   • Do NOT create mock services or simulated deployments"
    echo "   • Do NOT return hardcoded 'success' responses"
    echo "   • Do NOT create placeholder implementations"
    echo ""
    echo "2. ${BOLD}REAL IMPLEMENTATIONS ONLY${NC}"
    echo "   • If you cannot implement something, FAIL with clear error"
    echo "   • Use actual libraries and connections"
    echo "   • Connect to real services (database, API, etc.)"
    echo ""
    echo "3. ${BOLD}FAIL FAST PRINCIPLE${NC}"
    echo "   • If a requirement cannot be met, stop and report"
    echo "   • Do NOT create workarounds or simulations"
    echo "   • Better to fail honestly than succeed falsely"
    echo ""
    echo "4. ${BOLD}EXCEPTIONS FOR TEST CODE${NC}"
    echo "   • Mock data is OK in test files (*_test.py, *.test.js)"
    echo "   • Test fixtures and stubs are allowed in /tests directory"
    echo "   • Unit test mocks are acceptable"
    echo ""
    echo -e "${RED}Examples of FORBIDDEN code:${NC}"
    echo '```python'
    echo '# ❌ FORBIDDEN: Mock implementation'
    echo 'def deploy_to_device(config):'
    echo '    # Simulating deployment'
    echo '    print("Pretending to deploy...")'
    echo '    return {"status": "success"}  # Fake response'
    echo ''
    echo '# ❌ FORBIDDEN: Placeholder service'
    echo 'class MockSSHConnection:'
    echo '    def connect(self):'
    echo '        return True  # Not really connecting'
    echo '```'
    echo ""
    echo -e "${YELLOW}Examples of REQUIRED code:${NC}"
    echo '```python'
    echo '# ✅ CORRECT: Real implementation or explicit failure'
    echo 'def deploy_to_device(config):'
    echo '    try:'
    echo '        ssh = paramiko.SSHClient()  # Real library'
    echo '        ssh.connect(config["host"])  # Real connection'
    echo '        # ... actual implementation'
    echo '    except Exception as e:'
    echo '        raise ConnectionError(f"Cannot connect: {e}")'
    echo ''
    echo '# ✅ CORRECT: Fail if not implementable'
    echo 'def complex_feature():'
    echo '    raise NotImplementedError("This feature requires X library")'
    echo '```'
    echo ""
    echo -e "${RED}${BOLD}Remember: It's better to fail honestly than to create mock code!${NC}"
    echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
    echo ""
fi

# Export directive as environment variable for skills to read
export NO_MOCK_CODE="true"
export FAIL_ON_UNIMPLEMENTABLE="true"

# Create a directive file that skills can check
cat > "${PROJECT_ROOT}/.no-mock-directive" << EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "directive": "NO_MOCK_IMPLEMENTATIONS",
    "rules": [
        "No mock services in operational code",
        "No simulated deployments",
        "No hardcoded success responses",
        "No placeholder implementations",
        "Fail explicitly if cannot implement",
        "Real connections only",
        "Test mocks allowed in test files only"
    ],
    "enforcement": "strict"
}
EOF

exit 0