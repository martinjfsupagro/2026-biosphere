#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# DADA2 HEX — Job 3 : mergeSequenceTables + removeBimeraDenovo
# Ne pas lancer directement — soumis par 04-dada2_HEX_launcher.sh
# Variables reçues via --export : SHARED_DIR
#
# Produit le résultat final : seqtab_HEX_final.rds + seqtab_HEX_final.csv
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
export R_SHARED_DIR="$SHARED_DIR"
export R_SCRATCH="$RUN_SCRATCH"

Rscript - <<'EOF'
library(dada2)

shared_dir <- Sys.getenv("R_SHARED_DIR")
scratch    <- Sys.getenv("R_SCRATCH")
n_threads  <- as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", unset="8"))

cat("=== mergeSequenceTables + removeBimeraDenovo — HEX ===\n\n")

# ── Charger les deux seqtabs ──────────────────────────────────────────────
f_P1_5 <- file.path(shared_dir, "seqtab_HEX_P1-5.rds")
f_P6   <- file.path(shared_dir, "seqtab_HEX_P6.rds")

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

# ── Tableau de suivi complet ──────────────────────────────────────────────
cat("\n=== Tableau de suivi des reads ===\n\n")

track_p1_5 <- read.csv(file.path(shared_dir, "track_HEX_P1-5.csv"))
track_p6   <- read.csv(file.path(shared_dir, "track_HEX_P6.csv"))
track_all  <- rbind(track_p1_5, track_p6)

nonchim <- data.frame(
    sample      = rownames(seqtab_nochim),
    non_chimera = rowSums(seqtab_nochim),
    row.names   = NULL
)
track_all <- merge(track_all, nonchim, by="sample", all.x=TRUE)
track_all[is.na(track_all)] <- 0
track_all <- track_all[order(track_all$sample), ]

track_all$pct_filtered <- round(100 * track_all$filtered   / track_all$input,    1)
track_all$pct_merged   <- round(100 * track_all$merged      / track_all$filtered, 1)
track_all$pct_nonchim  <- round(100 * track_all$non_chimera / track_all$merged,   1)
track_all$pct_total    <- round(100 * track_all$non_chimera / track_all$input,    1)

cat("Aperçu (10 premiers samples) :\n")
print(head(track_all[, c("sample","input","filtered","merged","non_chimera",
                          "pct_filtered","pct_merged","pct_nonchim","pct_total")], 10))

cat(sprintf("\nRésumé global :\n"))
cat(sprintf("  Reads input total     : %d\n", sum(track_all$input)))
cat(sprintf("  Reads filtrés         : %d (%.1f%%)\n",
            sum(track_all$filtered),    100*sum(track_all$filtered)/sum(track_all$input)))
cat(sprintf("  Reads mergés          : %d (%.1f%%)\n",
            sum(track_all$merged),      100*sum(track_all$merged)/sum(track_all$input)))
cat(sprintf("  Reads non-chimériques : %d (%.1f%%)\n",
            sum(track_all$non_chimera), 100*sum(track_all$non_chimera)/sum(track_all$input)))

# ── Sauvegarde ────────────────────────────────────────────────────────────
saveRDS(seqtab_nochim,
        file.path(scratch, "seqtab_HEX_final.rds"))
write.csv(t(seqtab_nochim),
          file.path(scratch, "seqtab_HEX_final.csv"))
write.csv(track_all,
          file.path(scratch, "track_HEX_final.csv"), row.names=FALSE)

cat(sprintf("\n✓ Fichiers finaux dans %s :\n", scratch))
cat("  seqtab_HEX_final.rds   — pour analyses R aval\n")
cat("  seqtab_HEX_final.csv   — ASVs en lignes, samples en colonnes\n")
cat("  track_HEX_final.csv    — suivi des reads par sample à chaque étape\n")
EOF

# ─────────────────────────────────────────────────────────────────────────────
rsync -av "$RUN_SCRATCH/" "$RUN_RESULTS/"
echo "✓ Résultats finaux → $RUN_RESULTS"
echo "  seqtab_HEX_final.rds : $RUN_RESULTS/seqtab_HEX_final.rds"

_log END