#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Cutadapt worker : démultiplexage d'un marqueur sur tous les samples
# Ne pas lancer directement — soumis par 02_cutadapt_launcher.sh via sbatch
# Variables reçues via --export : MARKER, FWD, REV
# ─────────────────────────────────────────────────────────────────────────────

#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=${SLURM_MAIL}
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --account=ondemand@biomics
#SBATCH --qos=cpu-ondemand-long
#SBATCH --time=4:00:00

set -euo pipefail

# ── Environnement ─────────────────────────────────────────────────────────────
source "$WORK/projects/2026-biosphere/config/project.env"
source /home/martinj/bin/etc/profile.d/conda.sh
conda activate /home/martinj/bin/envs/cutadapt5.2

# ── Répertoires (ne pas modifier) ─────────────────────────────────────────────
RUN_ID="${SLURM_JOB_NAME}_${SLURM_JOB_ID}"
RUN_SCRATCH="$SCRATCH_DIR/$RUN_ID"
RUN_RESULTS="$PROJECT_DIR/results/$RUN_ID"
mkdir -p "$RUN_SCRATCH" "$RUN_RESULTS"

# ── Traçabilité (ne pas modifier) ─────────────────────────────────────────────
GIT_HASH=$(git -C "$PROJECT_DIR" rev-parse --short HEAD 2>/dev/null || echo "no-git")
cp "$0" "$RUN_RESULTS/job_script.sh"

_log() { echo "$(date -Iseconds) | $RUN_ID | $1 | $GIT_HASH | $(basename "$0") | ${2:-}" >> "$PROJECT_DIR/runs.log"; }
trap '_log FAIL "exit $?"'   ERR
trap 'mv -f "${SLURM_JOB_NAME}_${SLURM_JOB_ID}".{out,err} "$PROJECT_DIR/logs/" 2>/dev/null || true' EXIT
_log START "marker=$MARKER"

# ─────────────────────────────────────────────────────────────────────────────
# ANALYSE
RAW_DIR="$PROJECT_DIR/data"
mkdir -p "$RUN_SCRATCH/demux"

echo "==> Marqueur : $MARKER"
echo "    FWD : $FWD"
echo "    REV : $REV"
echo ""

N_SAMPLES=0
N_READS_TOTAL=0

# ── Boucle sur tous les samples ───────────────────────────────────────────────
for R1 in "$RAW_DIR"/*_R1_001.fastq.gz; do
    [[ -f "$R1" ]] || { echo "Aucun fichier R1 trouvé dans $RAW_DIR"; exit 1; }

    R2="${R1/_R1_001.fastq.gz/_R2_001.fastq.gz}"
    if [[ ! -f "$R2" ]]; then
        echo "⚠ R2 manquant pour $(basename "$R1"), ignoré"
        continue
    fi

    SAMPLE=$(basename "$R1" _R1_001.fastq.gz)

    cutadapt \
        -g "${MARKER}=${FWD}" \
        -G "${MARKER}=${REV}" \
        --nextseq-trim=20 \
        --pair-filter=both \
        --discard-untrimmed \
        --minimum-length 120 \
        -e 0.1 \
        --cores "$SLURM_CPUS_PER_TASK" \
        -o "$RUN_SCRATCH/demux/${SAMPLE}_${MARKER}_R1.fastq.gz" \
        -p "$RUN_SCRATCH/demux/${SAMPLE}_${MARKER}_R2.fastq.gz" \
        --json "$RUN_SCRATCH/demux/${SAMPLE}_${MARKER}.cutadapt.json" \
        "$R1" "$R2"

    # Compter les reads écrits
    f="$RUN_SCRATCH/demux/${SAMPLE}_${MARKER}_R1.fastq.gz"
    n=0
    [[ -f "$f" ]] && n=$(zcat "$f" | wc -l) && n=$(( n / 4 ))
    printf "  %-40s : %d reads\n" "$SAMPLE" "$n"

    (( N_READS_TOTAL += n )) || true
    (( N_SAMPLES++ ))        || true
done

echo ""
echo "==> $MARKER terminé : $N_SAMPLES samples, $N_READS_TOTAL reads au total"

# ─────────────────────────────────────────────────────────────────────────────

# ── Rapatriement des résultats (OBLIGATOIRE) ──────────────────────────────────
rsync -av "$RUN_SCRATCH/" "$RUN_RESULTS/"
echo "✓ Résultats → $RUN_RESULTS"

_log END "marker=$MARKER samples=$N_SAMPLES reads=$N_READS_TOTAL"