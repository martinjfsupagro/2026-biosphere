#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# DADA2 LEP — Job 3 : mergeSequenceTables + removeBimeraDenovo
# Ne pas lancer directement — soumis par 04-dada2_LEP_launcher.sh
# Variables reçues via --export : SHARED_DIR
#
# Produit le résultat final : seqtab_LEP_final.rds + seqtab_LEP_final.csv
# ─────────────────────────────────────────────────────────────────────────────

#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=${SLURM_MAIL}
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --account=ondemand@biomics
#SBATCH --qos=cpu-ondemand-long
#SBATCH --time=4:00:00

set -euo pipefail

# ── Environnement ─────────────────────────────────────────────────────────────
source "$WORK/projects/2026-biosphere/config/project.env"
module load bioinfo-ifb r/4.5.2          # ← ajuster : module avail r

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
_log START

# ─────────────────────────────────────────────────────────────────────────────
Rscript - <<EOF
library(dada2)

shared_dir <- "$SHARED_DIR"
scratch    <- "$RUN_SCRATCH"
n_threads  <- as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", unset="8"))

cat("=== mergeSequenceTables + removeBimeraDenovo — LEP ===\n\n")

# ── Charger les deux seqtabs ──────────────────────────────────────────────
f_P1_5 <- file.path(shared_dir, "seqtab_LEP_P1-5.rds")
f_P6   <- file.path(shared_dir, "seqtab_LEP_P6.rds")

if (!file.exists(f_P1_5)) stop("Introuvable : ", f_P1_5)
if (!file.exists(f_P6))   stop("Introuvable : ", f_P6)

seqtab_P1_5 <- readRDS(f_P1_5)
seqtab_P6   <- readRDS(f_P6)

cat(sprintf("  Plaques 1-5 : %d samples × %d ASVs\n",
            nrow(seqtab_P1_5), ncol(seqtab_P1_5)))
cat(sprintf("  Plaque  6   : %d samples × %d ASVs\n",
            nrow(seqtab_P6), ncol(seqtab_P6)))

# ── Fusion ────────────────────────────────────────────────────────────────
cat("\n--- mergeSequenceTables ---\n")
seqtab_all <- mergeSequenceTables(seqtab_P1_5, seqtab_P6)
cat(sprintf("  Après merge : %d samples × %d ASVs\n",
            nrow(seqtab_all), ncol(seqtab_all)))

cat("\nDistribution des longueurs avant suppression chimères :\n")
print(table(nchar(getSequences(seqtab_all))))

# ── Suppression des chimères ──────────────────────────────────────────────
cat("\n--- removeBimeraDenovo ---\n")
seqtab_nochim <- removeBimeraDenovo(
    seqtab_all,
    method      = "consensus",
    multithread = n_threads,
    verbose     = TRUE
)

n_before  <- ncol(seqtab_all)
n_after   <- ncol(seqtab_nochim)
pct_reads <- round(100 * sum(seqtab_nochim) / sum(seqtab_all), 1)
pct_asvs  <- round(100 * n_after / n_before, 1)

cat(sprintf("\nASVs avant : %d\n", n_before))
cat(sprintf("ASVs après : %d (%.1f%% des ASVs, %.1f%% des reads conservés)\n",
            n_after, pct_asvs, pct_reads))

cat("\nDistribution des longueurs finales :\n")
print(table(nchar(getSequences(seqtab_nochim))))

# ── Sauvegarde ────────────────────────────────────────────────────────────
saveRDS(seqtab_nochim,
        file.path(scratch, "seqtab_LEP_final.rds"))
write.csv(t(seqtab_nochim),
          file.path(scratch, "seqtab_LEP_final.csv"))

cat(sprintf("\n✓ Fichiers finaux dans %s :\n", scratch))
cat("  seqtab_LEP_final.rds  — pour analyses R aval (assignation taxonomique etc.)\n")
cat("  seqtab_LEP_final.csv  — ASVs en lignes, samples en colonnes\n")
EOF

# ─────────────────────────────────────────────────────────────────────────────
rsync -av "$RUN_SCRATCH/" "$RUN_RESULTS/"
echo "✓ Résultats finaux → $RUN_RESULTS"
echo "  seqtab_LEP_final.rds : $RUN_RESULTS/seqtab_LEP_final.rds"

_log END