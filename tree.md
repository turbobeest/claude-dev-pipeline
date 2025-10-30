claude-dev-pipeline/
│
├── README.md                                    # Repository overview
├── LICENSE                                      # MIT License  
├── install-pipeline.sh                          # Automated installer
│
├── skills/                                      # ALL 10 WORKFLOW SKILLS
│   │
│   ├── PRD-to-Tasks/                           # ✅ Skill 1: PRD → tasks.json
│   │   ├── SKILL.md                            # EXISTS in project knowledge
│   │   └── examples/
│   │       └── good-prd-parsing.md
│   │
│   ├── Coupling-Analysis/                      # ✅ Skill 2: Coupling analysis  
│   │   ├── SKILL.md                            # EXISTS in project knowledge
│   │   └── examples/
│   │       └── tightly-coupled-examples.md
│   │
│   ├── task-decomposer/                        # 📋 Skill 3: Complexity analysis
│   │   ├── SKILL.md                            # NEED TO EXTRACT
│   │   └── examples/
│   │       └── complexity-examples.md
│   │
│   ├── spec-gen/                               # 📋 Skill 4: OpenSpec generation
│   │   ├── SKILL.md                            # NEED TO EXTRACT
│   │   └── examples/
│   │       └── proposal-examples.md
│   │
│   ├── test-strategy/                          # ✅ Skill 5: Test strategy (60/30/10)
│   │   ├── SKILL.md                            # EXISTS in project knowledge
│   │   └── examples/
│   │       └── test-strategy-examples.md
│   │
│   ├── tdd-implementer/                        # 📋 Skill 6: TDD cycle guidance
│   │   ├── SKILL.md                            # NEED TO EXTRACT
│   │   └── examples/
│   │       └── tdd-cycle-examples.md
│   │
│   ├── integration-validator/                  # ✅ Skill 7: Integration validation
│   │   ├── SKILL.md                            # EXISTS in project knowledge
│   │   └── examples/
│   │       └── integration-examples.md
│   │
│   ├── e2e-validator/                          # 📋 Skill 8: E2E workflow testing
│   │   ├── SKILL.md                            # NEED TO EXTRACT
│   │   └── examples/
│   │       └── e2e-examples.md
│   │
│   ├── deployment-orchestrator/                # 📋 Skill 9: Deployment automation
│   │   ├── SKILL.md                            # NEED TO EXTRACT
│   │   └── examples/
│   │       └── deployment-examples.md
│   │
│   └── pipeline-orchestration/                 # 📋 Skill 10: Master orchestrator
│       ├── SKILL.md                            # NEED TO CREATE
│       └── examples/
│           └── orchestration-examples.md
│
├── hooks/                                       # 3 AUTOMATION HOOKS
│   ├── skill-activation-prompt.sh              # ✅ UserPromptSubmit (CREATED)
│   ├── post-tool-use-tracker.sh                # 📋 PostToolUse (UPDATE NEEDED)
│   ├── pre-implementation-validator.sh         # ✅ PreToolUse/TDD (CREATED)
│   └── README.md                               # Hooks documentation
│
├── config/                                      # CONFIGURATION FILES
│   ├── skill-rules.json                        # 📋 Skill activation (UPDATE NEEDED)
│   ├── settings.json                           # ✅ Claude Code settings (CREATED)
│   └── workflow-state.template.json            # Workflow state template
│
├── docs/                                        # DOCUMENTATION
│   ├── HOOKS-INTEGRATION-GUIDE.md              # ✅ Complete hooks guide (CREATED)
│   ├── PIPELINE-SETUP.md                       # Setup guide
│   ├── DEVELOPMENT-WORKFLOW.md                 # EXISTS in project knowledge
│   ├── TROUBLESHOOTING.md                      # Troubleshooting
│   ├── QUICK-REFERENCE.md                      # ✅ Quick reference (CREATED)
│   └── COMPLETE-SYSTEM-SUMMARY.md              # ✅ System overview (CREATED)
│
├── templates/                                   # PROJECT TEMPLATES
│   ├── PRD-template.md                         # PRD template
│   ├── TASKMASTER_OPENSPEC_MAP-template.md     # Mapping template
│   ├── architecture-template.md                # Architecture template
│   └── phase-prompts/                          # EXISTS in project knowledge
│       ├── phase0-setup.md
│       ├── phase1-decomposition.md
│       ├── phase2-spec-gen.md
│       ├── phase3-implementation.md
│       ├── phase4-integration.md
│       ├── phase5-e2e.md
│       └── phase6-deployment.md
│
├── tests/                                       # TEST SUITE
│   ├── test-skill-activation.sh                # Test skill activation
│   ├── test-hooks.sh                           # Test hooks
│   └── test-full-workflow.sh                   # Integration tests
│
├── .github/
│   └── workflows/
│       └── test-pipeline.yml                   # CI/CD testing
│
└── CONTRIBUTING.md                              # Contribution guidelines