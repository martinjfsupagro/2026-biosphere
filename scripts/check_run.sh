#!/usr/bin/env bash
# Vérifie qu'un run s'est bien terminé
# Usage : bash scripts/check_run.sh results/{jobname}_{jobid}

set -euo pipefail
RUN_DIR="${1:?Usage: check_run.sh <run_dir>}"
[[ -d "$RUN_DIR" ]] || { echo "Dossier introuvable : $RUN_DIR"; exit 1; }

PROJECT_DIR="$(cd "$(dirname "$RUN_DIR")/.." && pwd)"
RUN_ID="$(basename "$RUN_DIR")"

echo
echo "=== $RUN_ID ==="
printf "Taille    : %s\n"  "$(du -sh "$RUN_DIR" | cut -f1)"
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
echo
