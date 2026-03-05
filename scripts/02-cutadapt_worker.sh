#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Cutadapt worker : démultiplexage par marqueur pour un sample
# Ne pas lancer directement — soumis par 02-cutadapt_launcher.sh via sbatch
# Variables reçues via --export : SAMPLE, R1, R2, MARKERS_STR, FWDS_STR, REVS_STR
# ─────────────────────────────────────────────────────────────────────────────

#SBATCH --job-name=cutadapt_%j
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=${SLURM_MAIL}
#SBATCH --time=02:00:00
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G

set -euo pipefail

# ── Environnement ─────────────────────────────────────────────────────────────
source "$WORK/projects/2026-biosphere/config/project.env"
source /home/martinj/bin/etc/profile.d/conda.sh
conda activate /home/martinj/bin/envs/cutadapt5.2

# ── Répertoires (ne pas modifier) ────────────────────────────────────────────
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
_log START "sample=$SAMPLE"

# ─────────────────────────────────────────────────────────────────────────────
# ANALYSE
cd "$RUN_SCRATCH"

# ── Désérialisation des primers ───────────────────────────────────────────────
IFS=',' read -ra MARKERS <<< "$MARKERS_STR"
IFS=',' read -ra FWDS    <<< "$FWDS_STR"
IFS=',' read -ra REVS    <<< "$REVS_STR"

# ── Fonction reverse complement ───────────────────────────────────────────────
revcomp() {
    echo "$1" \
      | tr 'ACGTacgtRYSWKMBDHVNryswkmbdhvn' \
           'TGCAtgcaYRWSMKVHDBNyrwsmkvhdbn' \
      | rev
}

# ── Construction des arguments cutadapt ──────────────────────────────────────
# Linked adapters : -g "MARKER=^FWD...REV_RC" ancre le primer en 5' de R1
#                   -G "MARKER=^REV...FWD_RC" ancre le primer en 5' de R2
# Tout ce qui est en dehors de l'insert (primers inclus) est supprimé
CUTADAPT_ARGS=()
for i in "${!MARKERS[@]}"; do
    marker="${MARKERS[$i]}"
    fwd="${FWDS[$i]}"
    rev="${REVS[$i]}"
    fwd_rc=$(revcomp "$fwd")
    rev_rc=$(revcomp "$rev")

    CUTADAPT_ARGS+=( -g "${marker}=^${fwd}...${rev_rc}" )
    CUTADAPT_ARGS+=( -G "${marker}=^${rev}...${fwd_rc}" )
done

# ── Cutadapt ─────────────────────────────────────────────────────────────────
echo "==> Cutadapt : $SAMPLE ($(date))"
echo "    Marqueurs : ${MARKERS[*]}"

mkdir -p "$RUN_SCRATCH/demux"

cutadapt \
    "${CUTADAPT_ARGS[@]}" \
    --discard-untrimmed \
    --pair-filter=both \
    --minimum-length 120 \
    -e 0.1 \
    --cores "$SLURM_CPUS_PER_TASK" \
    -o "$RUN_SCRATCH/demux/${SAMPLE}_{name}_R1.fastq.gz" \
    -p "$RUN_SCRATCH/demux/${SAMPLE}_{name}_R2.fastq.gz" \
    --json "$RUN_SCRATCH/demux/${SAMPLE}.cutadapt.json" \
    "$R1" "$R2"

echo "==> Cutadapt terminé : $(date)"

# ── Résumé par marqueur ───────────────────────────────────────────────────────
echo ""
echo "Reads par marqueur :"
for marker in "${MARKERS[@]}"; do
    f="$RUN_SCRATCH/demux/${SAMPLE}_${marker}_R1.fastq.gz"
    if [[ -f "$f" ]]; then
        n=$(zcat "$f" | wc -l)
        printf "  %-8s : %d reads\n" "$marker" $(( n / 4 ))
    else
        printf "  %-8s : 0 reads (fichier absent)\n" "$marker"
    fi
done

# ─────────────────────────────────────────────────────────────────────────────

# ── Rapatriement des résultats (OBLIGATOIRE) ──────────────────────────────────
rsync -av "$RUN_SCRATCH/" "$RUN_RESULTS/"
echo "✓ Résultats → $RUN_RESULTS"

_log END "sample=$SAMPLE"