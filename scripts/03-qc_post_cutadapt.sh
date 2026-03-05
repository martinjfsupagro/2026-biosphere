#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# QC post-cutadapt : FastQC + MultiQC comparatif (bruts vs trimmés)
# Usage : sbatch 03_qc_post_cutadapt.sh
# ─────────────────────────────────────────────────────────────────────────────

#SBATCH --job-name=qc_post_cutadapt
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=${SLURM_MAIL}
#SBATCH --time=02:00:00
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --account=ondemand@biomics
#SBATCH --qos=cpu-ondemand-long

set -euo pipefail

# ── Environnement ─────────────────────────────────────────────────────────────
source "$WORK/projects/2026-biosphere/config/project.env"
module load bioinfo-ifb fastqc/0.12.1 multiqc/1.29

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
RESULTS_DIR="$PROJECT_DIR/results"
FASTQC_DIR="$RUN_SCRATCH/fastqc"
MULTIQC_DIR="$RUN_SCRATCH/multiqc"
mkdir -p "$FASTQC_DIR" "$MULTIQC_DIR"

# ── 1. FastQC sur les reads trimmés ───────────────────────────────────────────
echo "==> FastQC : $(date)"

mapfile -t FASTQ_FILES < <(find "$RESULTS_DIR" -path "*/cutadapt_*/*.fastq.gz" | sort)

if [[ ${#FASTQ_FILES[@]} -eq 0 ]]; then
    echo "ERREUR : aucun fichier fastq.gz trouvé dans les dossiers cutadapt_* de $RESULTS_DIR"
    exit 1
fi

echo "  ${#FASTQ_FILES[@]} fichier(s) détecté(s) :"
printf '    %s\n' "${FASTQ_FILES[@]}"

fastqc \
    --threads "$SLURM_CPUS_PER_TASK" \
    --outdir  "$FASTQC_DIR" \
    "${FASTQ_FILES[@]}"

echo "==> FastQC terminé : $(date)"

# ── 2. MultiQC comparatif (bruts + trimmés) ───────────────────────────────────
echo "==> MultiQC : $(date)"

# Récupérer le dossier FastQC du QC initial (reads bruts)
QC_INITIAL_DIR=$(find "$RESULTS_DIR" -path "*/qc_fastqc_multiqc_*/fastqc" -type d)

if [[ -z "$QC_INITIAL_DIR" ]]; then
    echo "AVERTISSEMENT : dossier FastQC initial non trouvé, rapport sans comparaison"
    QC_INITIAL_DIR=""
fi

multiqc \
    "$FASTQC_DIR" \
    ${QC_INITIAL_DIR:+"$QC_INITIAL_DIR"} \
    --outdir "$MULTIQC_DIR" \
    --filename "multiqc_report" \
    --dirs-depth 2 \
    --verbose

echo "==> MultiQC terminé : $(date)"

# ─────────────────────────────────────────────────────────────────────────────

# ── Rapatriement des résultats (OBLIGATOIRE) ──────────────────────────────────
rsync -av "$RUN_SCRATCH/" "$RUN_RESULTS/"
echo "✓ Résultats → $RUN_RESULTS"
echo "  Rapport MultiQC : $RUN_RESULTS/multiqc/multiqc_report.html"

_log END