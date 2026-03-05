#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Lanceur cutadapt : soumet un job SLURM par marqueur
# Usage : bash scripts/02-cutadapt_launcher.sh
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

source "$WORK/projects/2026-biosphere/config/project.env"

PRIMERS_FILE="$PROJECT_DIR/config/primers.tsv"
WORKER="$PROJECT_DIR/scripts/02-cutadapt_worker.sh"

# ── Vérifications ─────────────────────────────────────────────────────────────
[[ -f "$PRIMERS_FILE" ]] || { echo "ERREUR : $PRIMERS_FILE introuvable"; exit 1; }
[[ -f "$WORKER" ]]       || { echo "ERREUR : $WORKER introuvable";       exit 1; }

if ! git -C "$PROJECT_DIR" diff-index --quiet HEAD --; then
    echo "ERREUR : des changements non commités existent dans $PROJECT_DIR"
    echo "Fais un  git add -A && git commit -m 'description'  avant de soumettre."
    exit 1
fi

# ── Boucle sur les marqueurs ───────────────────────────────────────────────────
N_JOBS=0

while IFS=$'\t' read -r marker fwd rev; do
    [[ "$marker" =~ ^# ]] && continue
    [[ -z "$marker"    ]] && continue

    sbatch \
        --job-name="cutadapt_${marker}" \
        --export=ALL,MARKER="$marker",FWD="$fwd",REV="$rev" \
        "$WORKER"

    echo "→ soumis : $marker"
    (( N_JOBS++ )) || true
done < "$PRIMERS_FILE"

echo ""
echo "✓ $N_JOBS job(s) soumis"