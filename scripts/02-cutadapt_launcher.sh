#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Lanceur cutadapt : soumet un job SLURM par sample
# Usage : bash scripts/02-cutadapt_launcher.sh
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

# ── Boucle sur les paires R1/R2 ───────────────────────────────────────────────
N_JOBS=0

for R1 in "$RAW_DIR"/*_R1_001.fastq.gz; do
    [[ -f "$R1" ]] || { echo "Aucun fichier R1 trouvé dans $RAW_DIR"; exit 1; }

    R2="${R1/_R1_001.fastq.gz/_R2_001.fastq.gz}"

    if [[ ! -f "$R2" ]]; then
        echo "⚠ R2 manquant pour $(basename "$R1"), ignoré"
        continue
    fi

    SAMPLE=$(basename "$R1" _R1_001.fastq.gz)

    # Passage uniquement de variables simples sans virgules
    # Le worker lit lui-même PRIMERS_FILE → plus de sérialisation fragile
    sbatch \
        --job-name="cutadapt_${SAMPLE}" \
        --export=ALL,SAMPLE="$SAMPLE",R1="$R1",R2="$R2",PRIMERS_FILE="$PRIMERS_FILE" \
        "$WORKER"

    echo "→ soumis : $SAMPLE"
        (( N_JOBS++ )) || true
done

echo ""
echo "✓ $N_JOBS job(s) soumis"