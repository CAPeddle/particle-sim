#!/usr/bin/env bash
# .github/hooks/scripts/quality-gate.sh
#
# Copilot agentStop hook — runs clang-format AND clang-tidy on every C++ file
# modified during the agent session.
#
# Receives agent event JSON via stdin (ignored — we check git state directly).
# Exits non-zero if any violation is found.
#
# Requirements:
#   - clang-format in PATH
#   - clang-tidy in PATH
#   - compile_commands.json produced by CMake build (CMAKE_EXPORT_COMPILE_COMMANDS=ON)
#
# CUDA Notes:
#   - clang-format runs on .cu files (formatting supported)
#   - clang-tidy SKIPS .cu files (limited CUDA support)

set -euo pipefail

BUILD_DIR="build"   # Directory containing compile_commands.json

# --- Styling helpers ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
NC='\033[0m'

echo ""
echo -e "${CYAN}=== Quality Gate (agentStop) ===${NC}"

# --- Collect modified C++ files ---
# Include CUDA files for format, but track separately for tidy
FORMAT_EXTENSIONS=("cpp" "cc" "h" "hpp" "hxx" "cxx" "cu" "cuh")
TIDY_EXTENSIONS=("cpp" "cc" "h" "hpp" "hxx" "cxx")

format_files=()
tidy_files=()

while IFS= read -r f; do
    ext="${f##*.}"
    if [[ -f "$f" ]]; then
        for e in "${FORMAT_EXTENSIONS[@]}"; do
            if [[ "$ext" == "$e" ]]; then
                format_files+=("$f")
                break
            fi
        done
        for e in "${TIDY_EXTENSIONS[@]}"; do
            if [[ "$ext" == "$e" ]]; then
                tidy_files+=("$f")
                break
            fi
        done
    fi
done < <({ git diff --name-only 2>/dev/null; git diff --cached --name-only 2>/dev/null; } | sort -u)

if [[ ${#format_files[@]} -eq 0 ]]; then
    echo -e "${GRAY}No modified C++ files found — nothing to check.${NC}"
    exit 0
fi

echo -e "${GRAY}Checking ${#format_files[@]} file(s) for format, ${#tidy_files[@]} for tidy...${NC}"

overall_failures=0

# =========================================================
# Gate 1: clang-format (includes CUDA files)
# =========================================================
if ! command -v clang-format &>/dev/null; then
    echo -e "${YELLOW}WARNING: clang-format not found in PATH — skipping format check.${NC}"
else
    echo ""
    echo -e "${GRAY}--- clang-format ---${NC}"
    format_failures=0
    for f in "${format_files[@]}"; do
        if ! clang-format --dry-run --Werror --style=file:.clang-format "$f" &>/dev/null; then
            echo -e "   ${RED}❌ $f${NC}"
            format_failures=$((format_failures + 1))
            overall_failures=$((overall_failures + 1))
        fi
    done
    if [[ $format_failures -eq 0 ]]; then
        echo -e "${GREEN}✅ clang-format: all ${#format_files[@]} file(s) compliant.${NC}"
    else
        echo -e "${YELLOW}Fix: clang-format -i --style=file:.clang-format <file>${NC}"
    fi
fi

# =========================================================
# Gate 2: clang-tidy (skips CUDA files)
# =========================================================
if [[ ${#tidy_files[@]} -eq 0 ]]; then
    echo -e "${GRAY}No non-CUDA C++ files to check with clang-tidy.${NC}"
elif ! command -v clang-tidy &>/dev/null; then
    echo -e "${YELLOW}WARNING: clang-tidy not found in PATH — skipping tidy check.${NC}"
elif [[ ! -f "$BUILD_DIR/compile_commands.json" ]]; then
    echo -e "${YELLOW}WARNING: compile_commands.json not found at $BUILD_DIR/compile_commands.json${NC}"
    echo -e "${YELLOW}         Build the project first (CMAKE_EXPORT_COMPILE_COMMANDS=ON), then re-run.${NC}"
else
    echo ""
    echo -e "${GRAY}--- clang-tidy (skipping .cu/.cuh files) ---${NC}"
    tidy_failures=0
    for f in "${tidy_files[@]}"; do
        if ! clang-tidy -p "$BUILD_DIR" "$f" &>/dev/null; then
            echo -e "   ${RED}❌ $f${NC}"
            clang-tidy -p "$BUILD_DIR" "$f" 2>&1 | head -40
            tidy_failures=$((tidy_failures + 1))
            overall_failures=$((overall_failures + 1))
        fi
    done
    if [[ $tidy_failures -eq 0 ]]; then
        echo -e "${GREEN}✅ clang-tidy: all ${#tidy_files[@]} file(s) clean.${NC}"
    else
        echo -e "${YELLOW}Fix the findings. Add // NOLINT(check-name): reason only for confirmed false positives.${NC}"
    fi
fi

# =========================================================
# Summary
# =========================================================
echo ""
if [[ $overall_failures -eq 0 ]]; then
    echo -e "${GREEN}✅ Quality gate PASSED.${NC}"
    exit 0
else
    echo -e "${RED}❌ Quality gate FAILED — violations found in modified files.${NC}"
    exit 1
fi
