#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# QC initial : FastQC + MultiQC sur les reads bruts paired-end
# Usage : sbatch 01_qc_fastqc_multiqc.sh
# ─────────────────────────────────────────────────────────────────────────────

#SBATCH --job-name=qc_fastqc_multiqc
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=${SLURM_MAIL}
#SBATCH --time=01:00:00
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G

set -euo pipefail

# ── Environnement ─────────────────────────────────────────────────────────────
source "$WORK/projects/2026-biosphere/config/project.env"   # ← ICI : remplacer PROJECT
module load bioinfo-ifb fastqc/0.12.1 multiqc/1.29          # ← décommenter si modules dispo

# ── Répertoires (ne pas modifier) ────────────────────────────────────────────
RUN_ID="${SLURM_JOB_NAME}_${SLURM_JOB_ID}"
RUN_SCRATCH="$SCRATCH_DIR/$RUN_ID"
RUN_RESULTS="$PROJECT_DIR/results/$RUN_ID"
mkdir -p "$RUN_SCRATCH" "$RUN_RESULTS"

# ── Traçabilité (ne pas modifier) ─────────────────────────────────────────────
if ! git -C "$PROJECT_DIR" diff-index --quiet HEAD --; then
    echo "ERREUR : des changements non commités existent dans $PROJECT_DIR"
    echo "Fais un  git add -A && git commit -m 'description'  avant de soumettre."
    exit 1
fi

GIT_HASH=$(git -C "$PROJECT_DIR" rev-parse --short HEAD 2>/dev/null || echo "no-git")
cp "$0" "$RUN_RESULTS/job_script.sh"

_log() { echo "$(date -Iseconds) | $RUN_ID | $1 | $GIT_HASH | $(basename "$0") | ${2:-}" >> "$PROJECT_DIR/runs.log"; }
trap '_log FAIL "exit $?"'   ERR
trap 'mv -f "${SLURM_JOB_NAME}_${SLURM_JOB_ID}".{out,err} "$PROJECT_DIR/logs/" 2>/dev/null || true' EXIT
_log START

# ─────────────────────────────────────────────────────────────────────────────
# ANALYSE
cd "$RUN_SCRATCH"

# ── Paramètres ────────────────────────────────────────────────────────────────
RAW_DIR="$PROJECT_DIR/data"          # ← dossier contenant les fastq.gz
FASTQC_DIR="$RUN_SCRATCH/fastqc"
MULTIQC_DIR="$RUN_SCRATCH/multiqc"
mkdir -p "$FASTQC_DIR" "$MULTIQC_DIR"

# ── 1. FastQC ─────────────────────────────────────────────────────────────────
echo "==> FastQC : $(date)"

# Lister tous les fichiers à analyser
mapfile -t FASTQ_FILES < <(find "$RAW_DIR" -maxdepth 1 \( -name "*.fastq.gz" -o -name "*.fq.gz" \) | sort)

if [[ ${#FASTQ_FILES[@]} -eq 0 ]]; then
    echo "ERREUR : aucun fichier fastq.gz trouvé dans $RAW_DIR"
    exit 1
fi

echo "  ${#FASTQ_FILES[@]} fichier(s) détecté(s) :"
printf '    %s\n' "${FASTQ_FILES[@]}"

fastqc \
    --threads "$SLURM_CPUS_PER_TASK" \
    --outdir  "$FASTQC_DIR" \
    "${FASTQ_FILES[@]}"

echo "==> FastQC terminé : $(date)"

# ── 2. MultiQC ────────────────────────────────────────────────────────────────
echo "==> MultiQC : $(date)"

multiqc \
    "$FASTQC_DIR" \
    --outdir "$MULTIQC_DIR" \
    --filename "multiqc_report" \
    --verbose

echo "==> MultiQC terminé : $(date)"

# ─────────────────────────────────────────────────────────────────────────────

# ── Rapatriement des résultats (OBLIGATOIRE) ──────────────────────────────────
rsync -av "$RUN_SCRATCH/" "$RUN_RESULTS/"
echo "✓ Résultats → $RUN_RESULTS"
echo "  Rapport MultiQC : $RUN_RESULTS/multiqc/multiqc_report.html"

_log END