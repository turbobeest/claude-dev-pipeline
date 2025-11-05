#!/bin/bash
# =============================================================================
# Modified inject_next_activation Function for Manual Mode
# =============================================================================
#
# This is a replacement for the inject_next_activation function in
# post-tool-use-tracker.sh that shows OBVIOUS banners instead of auto-injecting
# codewords when manual mode is enabled.
#
# To apply: Source this file in post-tool-use-tracker.sh AFTER the original
# inject_next_activation function definition.
#
# =============================================================================

# Load banner functions
BANNER_LIB="${CLAUDE_WORKING_DIR:-.}/.claude/lib/phase-completion-banner.sh"
if [ -f "$BANNER_LIB" ]; then
    source "$BANNER_LIB"
fi

# Modified inject_next_activation function
inject_next_activation() {
    local signal="$1"

    # Input validation
    if [ -z "$signal" ]; then
        audit_log "ERROR" "inject_next_activation: missing signal parameter"
        return 1
    fi

    # Sanitize signal
    signal=$(sanitize_string "$signal" 100)

    # Check if skill rules file exists and is readable
    if [ ! -r "$SKILL_RULES" ]; then
        audit_log "ERROR" "Skill rules file not readable: $SKILL_RULES"
        return 1
    fi

    # Check if this signal triggers a transition
    local transition
    transition=$(timeout 10s jq -r --arg signal "$signal" '.phase_transitions[$signal] // empty' "$SKILL_RULES" 2>/dev/null || echo "")

    if [ -n "$transition" ]; then
        # Validate transition JSON
        if ! echo "$transition" | jq empty 2>/dev/null; then
            audit_log "WARN" "Invalid transition JSON for signal: $signal"
            return 1
        fi

        local auto_trigger next_activation slash_command banner_message
        auto_trigger=$(echo "$transition" | jq -r '.auto_trigger // false' 2>/dev/null)
        next_activation=$(echo "$transition" | jq -r '.next_activation // ""' 2>/dev/null | head -c 100)
        slash_command=$(echo "$transition" | jq -r '.slash_command // ""' 2>/dev/null | head -c 50)
        banner_message=$(echo "$transition" | jq -r '.banner_message // ""' 2>/dev/null | head -c 200)

        # Sanitize outputs
        next_activation=$(sanitize_string "$next_activation" 100)
        slash_command=$(sanitize_string "$slash_command" 50)

        # MANUAL MODE: Show obvious banner instead of auto-injecting
        if [ "$auto_trigger" = "false" ] && [ -n "$next_activation" ]; then

            # Determine which phase banner to show
            case "$signal" in
                "PHASE1_COMPLETE")
                    if type show_phase1_complete &>/dev/null; then
                        show_phase1_complete
                    else
                        # Fallback if banner lib not loaded
                        echo ""
                        echo "═══════════════════════════════════════════════════════════"
                        echo "  🎯 PHASE 1 COMPLETE - AWAITING YOUR COMMAND"
                        echo "═══════════════════════════════════════════════════════════"
                        echo ""
                        echo "  ✅ Task Decomposition & Planning finished"
                        echo ""
                        echo "  👉 To proceed to Phase 2, type: $slash_command"
                        echo ""
                        echo "═══════════════════════════════════════════════════════════"
                        echo ""
                    fi
                    ;;

                "TEST_STRATEGY_COMPLETE"|"PHASE2_COMPLETE")
                    if type show_phase2_complete &>/dev/null; then
                        show_phase2_complete
                    else
                        echo ""
                        echo "═══════════════════════════════════════════════════════════"
                        echo "  🎯 PHASE 2 COMPLETE - AWAITING YOUR COMMAND"
                        echo "═══════════════════════════════════════════════════════════"
                        echo ""
                        echo "  ✅ Specification Generation & Test Strategies finished"
                        echo ""
                        echo "  👉 To proceed to Phase 3, type: $slash_command"
                        echo ""
                        echo "═══════════════════════════════════════════════════════════"
                        echo ""
                    fi
                    ;;

                "PHASE3_COMPLETE")
                    if type show_phase3_complete &>/dev/null; then
                        show_phase3_complete
                    else
                        echo ""
                        echo "═══════════════════════════════════════════════════════════"
                        echo "  🎯 PHASE 3 COMPLETE - AWAITING YOUR COMMAND"
                        echo "═══════════════════════════════════════════════════════════"
                        echo ""
                        echo "  ✅ TDD Implementation finished"
                        echo ""
                        echo "  👉 To proceed to Phase 4, type: $slash_command"
                        echo ""
                        echo "═══════════════════════════════════════════════════════════"
                        echo ""
                    fi
                    ;;

                "PHASE4_COMPLETE")
                    if type show_phase4_complete &>/dev/null; then
                        show_phase4_complete
                    else
                        echo ""
                        echo "═══════════════════════════════════════════════════════════"
                        echo "  🎯 PHASE 4 COMPLETE - AWAITING YOUR COMMAND"
                        echo "═══════════════════════════════════════════════════════════"
                        echo ""
                        echo "  ✅ Component Integration Testing finished"
                        echo ""
                        echo "  👉 To proceed to Phase 5, type: $slash_command"
                        echo ""
                        echo "═══════════════════════════════════════════════════════════"
                        echo ""
                    fi
                    ;;

                "PHASE5_COMPLETE")
                    if type show_phase5_complete &>/dev/null; then
                        show_phase5_complete
                    else
                        echo ""
                        echo "═══════════════════════════════════════════════════════════"
                        echo "  🎯 PHASE 5 COMPLETE - GO/NO-GO DECISION REQUIRED"
                        echo "═══════════════════════════════════════════════════════════"
                        echo ""
                        echo "  ✅ E2E Production Validation finished"
                        echo ""
                        echo "  🚦 GO/NO-GO: Review results above"
                        echo ""
                        echo "  👉 If ready for deployment, type: $slash_command"
                        echo "  👉 If issues found, say: NO-GO - <reason>"
                        echo ""
                        echo "═══════════════════════════════════════════════════════════"
                        echo ""
                    fi
                    ;;

                "PHASE6_COMPLETE")
                    if type show_phase6_complete &>/dev/null; then
                        show_phase6_complete
                    else
                        echo ""
                        echo "═══════════════════════════════════════════════════════════"
                        echo "  🎉 PHASE 6 COMPLETE - PIPELINE FINISHED 🎉"
                        echo "═══════════════════════════════════════════════════════════"
                        echo ""
                        echo "  ✅ Production Deployment successful!"
                        echo ""
                        echo "  Your PRD is now production code!"
                        echo ""
                        echo "═══════════════════════════════════════════════════════════"
                        echo ""
                    fi
                    ;;

                *)
                    # Generic banner for other signals
                    echo ""
                    echo "═══════════════════════════════════════════════════════════"
                    echo "  ⏸️  MANUAL GATE: $signal"
                    echo "═══════════════════════════════════════════════════════════"
                    echo ""
                    if [ -n "$banner_message" ]; then
                        echo "  📋 $banner_message"
                        echo ""
                    fi
                    if [ -n "$slash_command" ]; then
                        echo "  👉 To proceed, type: $slash_command"
                    else
                        echo "  👉 Next skill: $next_activation"
                    fi
                    echo ""
                    echo "═══════════════════════════════════════════════════════════"
                    echo ""
                    ;;
            esac

            audit_log "INFO" "Manual gate: $signal (requires $slash_command)"

        # AUTO MODE: Inject codeword automatically
        elif [ "$auto_trigger" = "true" ] && [ -n "$next_activation" ]; then
            local delay
            delay=$(echo "$transition" | jq -r '.delay_seconds // 2' 2>/dev/null)

            # Validate delay
            if ! [[ "$delay" =~ ^[0-9]+$ ]] || [ "$delay" -gt 30 ]; then
                delay=2
            fi

            echo ""
            echo "🚀 **AUTOMATIC PHASE TRANSITION**"
            echo ""
            echo "[SIGNAL:$signal]"
            echo ""

            # Safe sleep
            if [ "$delay" -gt 0 ] && [ "$delay" -le 30 ]; then
                sleep "$delay"
            fi

            echo "[ACTIVATE:$next_activation]"
            echo ""

            # Get skill name
            local skill_name
            skill_name=$(timeout 5s jq -r --arg code "$next_activation" \
                '.skills[] | select(.activation_code == $code) | .skill' "$SKILL_RULES" 2>/dev/null || echo "Unknown")
            skill_name=$(sanitize_string "$skill_name" 100)

            echo "**Next Phase:** $skill_name"
            echo "**Reason:** Automatic transition from $signal"
            echo ""

            audit_log "INFO" "Auto-transition: $signal -> $next_activation ($skill_name)"
        fi
    fi

    return 0
}

# Export the function so it overrides the original
export -f inject_next_activation
