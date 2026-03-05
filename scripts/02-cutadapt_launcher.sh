#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Lanceur cutadapt : soumet un job SLURM par sample
# Usage : bash scripts/02-cutadapt_launcher.sh
# Prérequis : config/primers.tsv rempli, 02-cutadapt_worker.sh présent
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

source "$WORK/projects/2026-biosphere/config/project.env"

PRIMERS_FILE="$PROJECT_DIR/config/primers.tsv"
WORKER="$PROJECT_DIR/scripts/02-cutadapt_worker.sh"
RAW_DIR="$PROJECT_DIR/data"

# ── Vérifications ─────────────────────────────────────────────────────────────
[[ -f "$PRIMERS_FILE" ]] || { echo "ERREUR : $PRIMERS_FILE introuvable"; exit 1; }
[[ -f "$WORKER" ]]       || { echo "ERREUR : $WORKER introuvable";       exit 1; }

if ! git -C "$PROJECT_DIR" diff-index --quiet HEAD --; then
    echo "ERREUR : des changements non commités existent dans $PROJECT_DIR"
    echo "Fais un  git add -A && git commit -m 'description'  avant de soumettre."
    exit 1
fi

# ── Lecture des primers (ignore lignes vides et commentaires) ─────────────────
declare -a MARKERS FWDS REVS
while IFS=$'\t' read -r marker fwd rev; do
    [[ "$marker" =~ ^#   ]] && continue
    [[ -z "$marker"      ]] && continue
    MARKERS+=("$marker")
    FWDS+=("$fwd")
    REVS+=("$rev")
done < "$PRIMERS_FILE"

echo "Marqueurs chargés : ${MARKERS[*]}"
echo "Samples détectés dans $RAW_DIR :"

N_JOBS=0

# ── Boucle sur les paires R1/R2 ───────────────────────────────────────────────
for R1 in "$RAW_DIR"/*_R1_001.fastq.gz; do
    [[ -f "$R1" ]] || { echo "  Aucun fichier R1 trouvé dans $RAW_DIR"; exit 1; }

    R2="${R1/_R1_001.fastq.gz/_R2_001.fastq.gz}"

    if [[ ! -f "$R2" ]]; then
        echo "  ⚠ R2 manquant pour $(basename "$R1"), ignoré"
        continue
    fi

    SAMPLE=$(basename "$R1" _R1_001.fastq.gz)
    echo "  → $SAMPLE"

    # Sérialiser les tableaux en chaînes séparées par des virgules pour --export
    MARKERS_STR=$(IFS=,; echo "${MARKERS[*]}")
    FWDS_STR=$(IFS=,;    echo "${FWDS[*]}")
    REVS_STR=$(IFS=,;    echo "${REVS[*]}")

    sbatch \
        --export=ALL,\
SAMPLE="$SAMPLE",\
R1="$R1",\
R2="$R2",\
MARKERS_STR="$MARKERS_STR",\
FWDS_STR="$FWDS_STR",\
REVS_STR="$REVS_STR" \
        "$WORKER"

    (( N_JOBS++ ))
done

echo ""
echo "✓ $N_JOBS job(s) soumis"