#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# DADA2 LEP — Launcher
# Usage : bash scripts/04-dada2_LEP_launcher.sh
#
# Architecture :
#   Job 1 (plaques 1-5) → Job 2 (plaque 6, charge err model de job 1)
#                       ↘               ↙
#                         Job 3 (final)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

source "$WORK/projects/2026-biosphere/config/project.env"

SCRIPTS_DIR="$PROJECT_DIR/scripts"

# ── Git check ─────────────────────────────────────────────────────────────────
if ! git -C "$PROJECT_DIR" diff-index --quiet HEAD --; then
    echo "ERREUR : des changements non commités existent dans $PROJECT_DIR"
    echo "Fais un  git add -A && git commit -m 'description'  avant de soumettre."
    exit 1
fi

# ── Dossier partagé entre jobs (chemin fixe, connu à l'avance) ───────────────
SHARED_DIR="$PROJECT_DIR/results/dada2_LEP_shared"
mkdir -p "$SHARED_DIR"
echo "Dossier partagé : $SHARED_DIR"
echo ""

echo "=== Pipeline DADA2 — marqueur LEP ==="
echo ""

# ── Job 1 : plaques 1-5 ───────────────────────────────────────────────────────
JID1=$(sbatch --parsable \
    --job-name="dada2_LEP_p1-5" \
    --export=ALL,SHARED_DIR="$SHARED_DIR" \
    "$SCRIPTS_DIR/04-dada2_LEP_p1-5_worker.sh")
echo "→ Job 1 soumis (plaques 1-5) : $JID1"

# ── Job 2 : plaque 6 (attend job 1 pour le modèle d'erreur) ──────────────────
JID2=$(sbatch --parsable \
    --dependency=afterok:"$JID1" \
    --job-name="dada2_LEP_p6" \
    --export=ALL,SHARED_DIR="$SHARED_DIR" \
    "$SCRIPTS_DIR/04-dada2_LEP_p6_worker.sh")
echo "→ Job 2 soumis (plaque 6)    : $JID2 (attend $JID1)"

# ── Job 3 : final (attend job 1 ET job 2) ────────────────────────────────────
JID3=$(sbatch --parsable \
    --dependency=afterok:"${JID1}:${JID2}" \
    --job-name="dada2_LEP_final" \
    --export=ALL,SHARED_DIR="$SHARED_DIR" \
    "$SCRIPTS_DIR/04-dada2_LEP_final_worker.sh")
echo "→ Job 3 soumis (final)       : $JID3 (attend $JID1 et $JID2)"

echo ""
echo "✓ Pipeline LEP soumis."
echo ""
echo "  Job1 (P1-5) ──→ Job2 (P6) ──┐"
echo "       └─────────────────────→ Job3 (final)"
echo ""
echo "Suivi :"
echo "  squeue -u \$USER --format='%.10i %.25j %.8T %.10M %R'"
echo "  tail -f $PROJECT_DIR/runs.log"