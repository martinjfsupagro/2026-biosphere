#!/usr/bin/env bash
# Usage : ./check_run.sh qc_fastqc_multiqc_4251346

set -euo pipefail

# ── Arguments ─────────────────────────────────────────────────────────────────
RUN_ID="${1:?Usage: $0 <RUN_ID>}"

source "$WORK/projects/2026-biosphere/config/project.env"   # ← ICI : remplacer PROJECT

RUN_DIR="$PROJECT_DIR/results/$RUN_ID"

if [[ ! -d "$RUN_DIR" ]]; then
    echo "ERREUR : dossier introuvable → $RUN_DIR"
    exit 1
fi

# ── Checks génériques ─────────────────────────────────────────────────────────
printf "Fichiers  : %s\n"  "$(find "$RUN_DIR" -type f | wc -l)"

echo
echo "Derniers fichiers modifiés :"
find "$RUN_DIR" -type f -printf '%TY-%Tm-%Td %TH:%TM  %P\n' | sort | tail -5

echo
echo "Entrée runs.log :"
grep "$RUN_ID" "$PROJECT_DIR/runs.log" 2>/dev/null \
    || echo "  ⚠  Aucune entrée trouvée"

if grep -q "$RUN_ID | END" "$PROJECT_DIR/runs.log" 2>/dev/null; then
    printf '\n  \033[32m✓ Run terminé proprement\033[0m\n'
else
    printf '\n  \033[31m✗ Pas de statut END dans runs.log\033[0m\n'
fi

# ── Checks spécifiques FastQC / MultiQC ───────────────────────────────────────
echo
echo "Rapport MultiQC :"
MULTIQC_REPORT="$RUN_DIR/multiqc/multiqc_report.html"
if [[ -f "$MULTIQC_REPORT" ]]; then
    printf '  \033[32m✓ %s\033[0m\n' "$MULTIQC_REPORT"
else
    printf '  \033[31m✗ multiqc_report.html absent\033[0m\n'
fi

echo
echo "Rapports FastQC :"
NB_FASTQC=$(find "$RUN_DIR/fastqc" -name "*.html" 2>/dev/null | wc -l)
printf "  %s rapport(s) html\n" "$NB_FASTQC"