#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Template SLURM générique
# 1. cp scripts/job_template.sh scripts/mon_job.sh
# 2. Remplir les sections marquées  ← ICI
# 3. git add -A && git commit -m "description" avant de soumettre
# ─────────────────────────────────────────────────────────────────────────────

#SBATCH --job-name=MON_JOB          # ← ICI
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=${SLURM_MAIL}
#SBATCH --time=01:00:00             # ← ICI  hh:mm:ss
#SBATCH --cpus-per-task=4           # ← ICI
#SBATCH --mem=8G                    # ← ICI
#SBATCH --partition=normal          # ← ICI

set -euo pipefail

# ── Environnement ─────────────────────────────────────────────────────────────
source "$WORK/projects/PROJECT/config/project.env"   # ← ICI : remplacer PROJECT
# module load ...                                     # ← ICI si besoin

# ── Répertoires (ne pas modifier) ────────────────────────────────────────────
RUN_ID="${SLURM_JOB_NAME}_${SLURM_JOB_ID}"
RUN_SCRATCH="$SCRATCH_DIR/$RUN_ID"
RUN_RESULTS="$PROJECT_DIR/results/$RUN_ID"
mkdir -p "$RUN_SCRATCH" "$RUN_RESULTS"

# ── Traçabilité (ne pas modifier) ─────────────────────────────────────────────
# Bloque le job si des changements non commités existent
if ! git -C "$PROJECT_DIR" diff-index --quiet HEAD --; then
    echo "ERREUR : des changements non commités existent dans $PROJECT_DIR"
    echo "Fais un  git add -A && git commit -m 'description'  avant de soumettre."
    exit 1
fi

GIT_HASH=$(git -C "$PROJECT_DIR" rev-parse --short HEAD 2>/dev/null || echo "no-git")
cp "$0" "$RUN_RESULTS/job_script.sh"    # fige le script exact utilisé

_log() { echo "$(date -Iseconds) | $RUN_ID | $1 | $GIT_HASH | $(basename "$0") | ${2:-}" >> "$PROJECT_DIR/runs.log"; }
trap '_log FAIL "exit $?"'   ERR
trap 'mv -f "${SLURM_JOB_NAME}_${SLURM_JOB_ID}".{out,err} "$PROJECT_DIR/logs/" 2>/dev/null || true' EXIT
_log START

# ─────────────────────────────────────────────────────────────────────────────
# TON ANALYSE ICI
# Travailler dans $RUN_SCRATCH (I/O rapide, temporaire)
cd "$RUN_SCRATCH"

# exemple :
# mon_programme \
#     --input  "$PROJECT_DIR/data/input.txt" \
#     --output "$RUN_SCRATCH/output.txt" \
#     --threads "$SLURM_CPUS_PER_TASK"

# ─────────────────────────────────────────────────────────────────────────────

# ── Rapatriement des résultats (OBLIGATOIRE) ──────────────────────────────────
rsync -av "$RUN_SCRATCH/" "$RUN_RESULTS/"
echo "✓ Résultats → $RUN_RESULTS"

_log END
