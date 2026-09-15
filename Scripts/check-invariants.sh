#!/usr/bin/env bash
# Repository-wide invariants from CLAUDE.md and docs/ARCHITECTURE.md §14.
# FermanCore's token-level determinism rules live in InvariantTests; this script covers what spans packages.
set -euo pipefail

cd "$(dirname "$0")/.."

failures=0
fail() {
    echo "✗ $*"
    failures=$((failures + 1))
}

# Prints "path:line:module" for every import statement in the Swift files under the given roots.
imports_in() {
    find "$@" -type f -name '*.swift' \
        -not -path '*/.build/*' -not -path '*/DerivedData/*' -not -path '*/.swiftpm/*' -print0 2>/dev/null |
        LC_ALL=C sort -z |
        xargs -0 -r perl -ne '
            if (/^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|package|internal|private|fileprivate)\s+)?import\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?(\w+)/) {
                print "$ARGV:$.:$1\n";
            }
            close ARGV if eof;
        '
}

# 1. Pure packages import only Foundation, plus FermanCore for the packages built on it (CLAUDE.md rule 1).
for package in FermanCore FermanContent FermanReplay; do
    sources="Packages/$package/Sources"
    [ -d "$sources" ] || continue
    while IFS=: read -r path line module; do
        case "$package:$module" in
            *:Foundation | FermanContent:FermanCore | FermanReplay:FermanCore) ;;
            *) fail "$path:$line imports $module, which $package must not depend on" ;;
        esac
    done < <(imports_in "$sources")
done

# 2. FoundationModels only in its compiler file and that file's tests (CLAUDE.md rule 3).
while IFS=: read -r path line module; do
    [ "$module" = "FoundationModels" ] || continue
    case "$path" in
        ./Packages/FermanAI/Sources/FermanAI/FoundationModelsCompiler.swift) ;;
        ./Packages/FermanAI/Tests/FermanAITests/FoundationModelsCompilerTests.swift) ;;
        *) fail "$path:$line imports FoundationModels outside FoundationModelsCompiler.swift" ;;
    esac
done < <(imports_in .)

# 3. GameplayKit only in FermanAI's EnemyAI folder (CLAUDE.md rule 5, D6).
while IFS=: read -r path line module; do
    [ "$module" = "GameplayKit" ] || continue
    case "$path" in
        ./Packages/FermanAI/Sources/FermanAI/EnemyAI/*) ;;
        ./Packages/FermanAI/Tests/FermanAITests/EnemyAI/*) ;;
        *) fail "$path:$line imports GameplayKit outside FermanAI/EnemyAI" ;;
    esac
done < <(imports_in .)

# 4. No package dependencies before Phase 5 (CLAUDE.md rule 6).
while IFS= read -r resolved; do
    if grep -q '"identity"' "$resolved"; then
        fail "$resolved pins package dependencies; Package.resolved must stay empty until Phase 5"
    fi
done < <(find . -name Package.resolved -not -path '*/.build/*' -not -path '*/DerivedData/*' 2>/dev/null)

# 5. Banned words in user-facing strings (CLAUDE.md rule 7).
catalogs=$(find . -name '*.xcstrings' -not -path '*/.build/*' -not -path '*/DerivedData/*' 2>/dev/null || true)
if [ -n "$catalogs" ]; then
    if ! command -v python3 >/dev/null 2>&1; then
        fail "python3 is required to scan String Catalogs"
    else
        # shellcheck disable=SC2086
        if ! python3 - $catalogs <<'PYTHON'
import json
import re
import sys

prefixes = ["kod", "derle", "fonksiyon", "debug", "script", "algoritma", "programla", "çalıştır"]
patterns = [re.compile(r"(?<!\w)(" + "|".join(prefixes) + r")", re.IGNORECASE),
            re.compile(r"(?<!\w)(if|else)(?!\w)", re.IGNORECASE),
            re.compile(r"kural\s+motoru", re.IGNORECASE)]
found = False

def texts(node):
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "comment":
                continue
            if key == "value" and isinstance(value, str):
                yield value
            else:
                yield from texts(value)
    elif isinstance(node, list):
        for item in node:
            yield from texts(item)

for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as handle:
        catalog = json.load(handle)
    for key, entry in catalog.get("strings", {}).items():
        for text in [key, *texts(entry)]:
            for pattern in patterns:
                match = pattern.search(text)
                if match:
                    print(f"✗ {path}: '{text}' contains banned word '{match.group(0)}'")
                    found = True
sys.exit(1 if found else 0)
PYTHON
        then
            failures=$((failures + 1))
        fi
    fi
fi

if [ "$failures" -gt 0 ]; then
    echo "check-invariants: $failures violation(s)"
    exit 1
fi
echo "check-invariants: all invariants hold"
