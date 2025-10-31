# PRD Compliance System

## Overview
The Claude Dev Pipeline now includes a generic PRD compliance validation system that prevents architectural substitutions and ensures implementation matches requirements.

## How It Works

### 1. Requirement Extraction
The system dynamically extracts requirements from ANY PRD by looking for patterns like:
- `MUST use X`
- `REQUIRES Y`
- `DO NOT substitute A with B`
- `CANNOT use Z`

### 2. Dynamic Validation
Instead of hardcoding specific tools (like Netmiko or Neo4j), the system:
- Reads the PRD at runtime
- Extracts actual requirements
- Validates implementation against those specific requirements

### 3. Generic Approach
The validation system works with ANY project because it:
- Doesn't assume specific tools
- Adapts to each PRD's requirements
- Uses pattern matching, not hardcoded checks

## Components

### `hooks/prd-requirement-extractor.sh`
- Extracts requirements from PRD
- Creates `.prd-requirements.json` file
- Runs automatically before validation

### `hooks/implementation-validator.sh`
- Validates implementation against extracted requirements
- Checks for required components
- Ensures forbidden components aren't used
- Creates `.validation-report.json`

### `skills/prd-compliance-validator/`
- Skill that orchestrates compliance checking
- Integrates with pipeline phases
- Signals compliance status

## Usage

### Manual Extraction
```bash
./hooks/prd-requirement-extractor.sh
```

### Manual Validation
```bash
./hooks/implementation-validator.sh
```

### Automatic Integration
The system automatically runs during:
- Phase 3 (Implementation) - Shows requirements
- Phase 4 (Testing) - Validates compliance
- Phase 5 (Deployment) - Final verification

## Example PRD Requirements

### Good PRD Patterns
```markdown
## Requirements
- MUST use PostgreSQL for data persistence
- REQUIRES authentication via OAuth2
- DO NOT use SQLite in production
- CANNOT store passwords in plaintext
```

### Extracted Requirements
```json
{
    "must_use": ["PostgreSQL", "OAuth2"],
    "cannot_use": ["SQLite", "plaintext"],
    "requirements": [
        "PostgreSQL for data persistence",
        "authentication via OAuth2"
    ]
}
```

## Benefits

1. **No Hardcoding**: Works with any project/PRD
2. **Dynamic Adaptation**: Extracts requirements at runtime
3. **Clear Feedback**: Shows what's required/forbidden
4. **Prevents Substitutions**: Catches when requirements aren't met
5. **Generic Validation**: Not tied to specific tools

## Preventing Substitutions

When the system detects a requirement isn't met:
1. Shows clear error message
2. Lists missing components
3. Blocks pipeline progression
4. Provides remediation guidance

## Best Practices

### Writing PRDs
Be explicit about requirements:
- Use "MUST use" for mandatory components
- Use "DO NOT" for forbidden substitutions
- Be specific about technology choices

### During Implementation
1. Run requirement extractor early
2. Check `.prd-requirements.json` 
3. Validate frequently during development
4. Address violations immediately

## Troubleshooting

### No Requirements Extracted
- Check PRD format
- Ensure requirements use clear patterns
- Add explicit "MUST use" statements

### False Positives
- Check implementation file locations
- Verify import statements
- Ensure services are properly named

### Validation Errors
- Review `.validation-report.json`
- Check for typos in component names
- Verify docker-compose.yml includes services