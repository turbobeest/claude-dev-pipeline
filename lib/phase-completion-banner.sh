#!/bin/bash
# =============================================================================
# Phase Completion Banner Generator
# =============================================================================
#
# Generates VERY OBVIOUS terminal banners for phase completion.
# Used by PostToolUse hook when manual-mode is enabled.
#
# =============================================================================

generate_phase_completion_banner() {
    local phase_number="$1"
    local phase_name="$2"
    local next_command="$3"
    local next_phase_name="$4"

    echo ""
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║                                                                       ║"
    echo "║                    🎯 PHASE $phase_number COMPLETE 🎯                          ║"
    echo "║                                                                       ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  ✅ Completed: $phase_name"
    echo ""
    echo "  ⏸️  PIPELINE PAUSED - Awaiting Your Command"
    echo ""
    echo "╭───────────────────────────────────────────────────────────────────────╮"
    echo "│                                                                       │"
    echo "│  To proceed to Phase $(($phase_number + 1)): $next_phase_name"
    echo "│                                                                       │"
    echo "│  👉 Type: $next_command"
    echo "│                                                                       │"
    echo "╰───────────────────────────────────────────────────────────────────────╯"
    echo ""
    echo "  📋 Alternative: You can review outputs before proceeding"
    echo "  📊 Monitor: Check .claude/logs/pipeline.log for details"
    echo "  🔍 Status: Run 'jq . .claude/.workflow-state.json' to see full state"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════"
    echo ""
}

# Phase-specific banners
show_phase1_complete() {
    generate_phase_completion_banner \
        "1" \
        "Task Decomposition & Planning" \
        "/generate-specs" \
        "Specification Generation"

    echo "  📝 Phase 1 Outputs:"
    echo "     • tasks.json with full task hierarchy"
    echo "     • Coupling analysis data"
    echo "     • Dependencies mapped"
    echo ""
    echo "  🔍 Review tasks: task-master list"
    echo "  📊 Check coupling: grep -A5 'coupling' .taskmaster/tasks.json"
    echo ""
}

show_phase2_complete() {
    generate_phase_completion_banner \
        "2" \
        "Specification Generation & Test Strategies" \
        "/implement-tdd" \
        "TDD Implementation"

    echo "  📝 Phase 2 Outputs:"
    echo "     • OpenSpec proposals in .openspec/proposals/"
    echo "     • Test strategies in .openspec/test-strategies/"
    echo "     • Batch worktrees created"
    echo ""
    echo "  🔍 Review specs: ls -lh .openspec/proposals/"
    echo "  📊 Check strategies: ls -lh .openspec/test-strategies/"
    echo ""
}

show_phase3_complete() {
    generate_phase_completion_banner \
        "3" \
        "TDD Implementation (RED-GREEN-REFACTOR)" \
        "/validate-integration" \
        "Component Integration Testing"

    echo "  📝 Phase 3 Outputs:"
    echo "     • Implemented features in src/"
    echo "     • Test files in src/__tests__/"
    echo "     • All unit tests passing"
    echo ""
    echo "  🔍 Run tests: npm test"
    echo "  📊 Check coverage: npm test -- --coverage"
    echo "  ✅ Verify no mocks: grep -r 'mock' src/ --exclude-dir=__tests__"
    echo ""
}

show_phase4_complete() {
    generate_phase_completion_banner \
        "4" \
        "Component Integration Testing" \
        "/validate-e2e" \
        "End-to-End Production Validation"

    echo "  📝 Phase 4 Outputs:"
    echo "     • All integration tests passing"
    echo "     • API contracts validated"
    echo "     • Component interactions verified"
    echo ""
    echo "  🔍 Run integration tests: npm run test:integration"
    echo "  📊 Check contracts: openspec validate .openspec/proposals/*.md"
    echo ""
}

show_phase5_complete() {
    echo ""
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║                                                                       ║"
    echo "║                    🎯 PHASE 5 COMPLETE 🎯                             ║"
    echo "║                                                                       ║"
    echo "║                🚦 GO/NO-GO DECISION REQUIRED 🚦                       ║"
    echo "║                                                                       ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  ✅ Completed: End-to-End Production Validation"
    echo ""
    echo "  📊 E2E Test Results:"
    echo "     • All critical workflows tested"
    echo "     • Cross-browser compatibility verified"
    echo "     • Performance benchmarks met"
    echo "     • Security validation complete"
    echo ""
    echo "  ⏸️  PIPELINE PAUSED - MANUAL APPROVAL GATE"
    echo ""
    echo "╭───────────────────────────────────────────────────────────────────────╮"
    echo "│                                                                       │"
    echo "│  🚦 GO/NO-GO DECISION:                                               │"
    echo "│                                                                       │"
    echo "│  Review the test results above and staging environment behavior.     │"
    echo "│                                                                       │"
    echo "│  ✅ If ready for deployment:                                         │"
    echo "│     Type: /deploy                                                     │"
    echo "│                                                                       │"
    echo "│  ❌ If issues found:                                                 │"
    echo "│     Say: \"NO-GO - <reason>\"                                          │"
    echo "│     Fix issues and restart Phase 5 with /validate-e2e               │"
    echo "│                                                                       │"
    echo "╰───────────────────────────────────────────────────────────────────────╯"
    echo ""
    echo "  🔍 Review E2E results: npm run test:e2e -- --reporter=html"
    echo "  📊 Check staging: curl https://staging.example.com/health"
    echo "  📋 Rollback plan: Documented and tested"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════"
    echo ""
}

show_phase6_complete() {
    echo ""
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║                                                                       ║"
    echo "║                  🎉 PHASE 6 COMPLETE 🎉                               ║"
    echo "║                                                                       ║"
    echo "║              🚀 PRODUCTION DEPLOYMENT SUCCESSFUL 🚀                   ║"
    echo "║                                                                       ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  ✅ Deployment Complete:"
    echo "     • Staging deployment: SUCCESS"
    echo "     • Canary deployment: HEALTHY"
    echo "     • Progressive rollout: 100% traffic"
    echo "     • Production validation: PASSED"
    echo ""
    echo "╭───────────────────────────────────────────────────────────────────────╮"
    echo "│                                                                       │"
    echo "│              🎊 PIPELINE COMPLETE 🎊                                  │"
    echo "│                                                                       │"
    echo "│  Your PRD has been transformed into production code!                 │"
    echo "│                                                                       │"
    echo "│  All 6 phases completed successfully:                                │"
    echo "│    ✅ Phase 1: Task Decomposition                                    │"
    echo "│    ✅ Phase 2: Specification Generation                              │"
    echo "│    ✅ Phase 3: TDD Implementation                                    │"
    echo "│    ✅ Phase 4: Integration Testing                                   │"
    echo "│    ✅ Phase 5: E2E Validation                                        │"
    echo "│    ✅ Phase 6: Production Deployment                                 │"
    echo "│                                                                       │"
    echo "╰───────────────────────────────────────────────────────────────────────╯"
    echo ""
    echo "  📊 Next Steps:"
    echo "     • Monitor production metrics and logs"
    echo "     • Set up alerts for anomalies"
    echo "     • Plan next iteration"
    echo "     • Document lessons learned"
    echo ""
    echo "  🔍 Production health: curl https://api.example.com/health"
    echo "  📈 Monitoring: open https://grafana.example.com/d/app-dashboard"
    echo "  📋 Logs: kubectl logs -f deployment/app --namespace=production"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════"
    echo ""
    echo "  Thank you for using Claude Dev Pipeline! 🙏"
    echo ""
}

# Export functions
export -f generate_phase_completion_banner
export -f show_phase1_complete
export -f show_phase2_complete
export -f show_phase3_complete
export -f show_phase4_complete
export -f show_phase5_complete
export -f show_phase6_complete
