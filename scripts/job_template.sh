#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# DESCRIPTION : [décrire l'étape ici]
# Usage       : sbatch XX_nom_etape.sh
# Entrées     : [ex. résultats de cutadapt_* dans $PROJECT_DIR/results]
# Sorties     : [ex. rapports FastQC + MultiQC]
# ─────────────────────────────────────────────────────────────────────────────

# ── Ressources SLURM ──────────────────────────────────────────────────────────
#SBATCH --job-name=nom_etape           # ← modifier
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=${SLURM_MAIL}
#SBATCH --time=02:00:00               # ← ajuster selon l'étape
#SBATCH --cpus-per-task=8             # ← ajuster selon l'outil
#SBATCH --mem=16G                     # ← ajuster selon l'étape
#SBATCH --account=ondemand@biomics    # ← ou dedicated-cpu@iam / dedicated-cpu@jrl
#SBATCH --qos=cpu-ondemand-long       # ← ondemand-short si < 1h, cpu-ondemand-long sinon

set -euo pipefail

# ── Environnement ─────────────────────────────────────────────────────────────
source "$WORK/projects/2026-biosphere/config/project.env"
module load bioinfo-ifb \
    # ← ajouter les modules nécessaires, ex :
    # fastqc/0.12.1 \
    # multiqc/1.29  \
    # cutadapt/4.x

# ── Répertoires (ne pas modifier) ─────────────────────────────────────────────
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

# Exemples de patterns find selon l'étape :
#   reads bruts          : find "$PROJECT_DIR/data" -maxdepth 1 -name "*.fastq.gz"
#   après cutadapt        : find "$RESULTS_DIR" -path "*/cutadapt_*/*.fastq.gz"
#   dossier fastqc initial: find "$RESULTS_DIR" -path "*/qc_fastqc_multiqc_*/fastqc" -type d

mapfile -t INPUT_FILES < <(find "$RESULTS_DIR" -path "*/etape_precedente_*/*.fastq.gz" | sort)  # ← adapter

if [[ ${#INPUT_FILES[@]} -eq 0 ]]; then
    echo "ERREUR : aucun fichier trouvé"
    exit 1
fi

echo "  ${#INPUT_FILES[@]} fichier(s) détecté(s) :"
printf '    %s\n' "${INPUT_FILES[@]}"

# ── Étape principale ──────────────────────────────────────────────────────────
echo "==> [nom étape] : $(date)"

# Commande principale ici
# ex : fastqc --threads "$SLURM_CPUS_PER_TASK" --outdir "$RUN_SCRATCH" "${INPUT_FILES[@]}"

echo "==> [nom étape] terminé : $(date)"

# ── Rapatriement des résultats (OBLIGATOIRE) ──────────────────────────────────
rsync -av "$RUN_SCRATCH/" "$RUN_RESULTS/"
echo "✓ Résultats → $RUN_RESULTS"

_log END