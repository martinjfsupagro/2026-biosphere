#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# DADA2 LEP — Job 2 : filterAndTrim + dada, plaque 6
# Ne pas lancer directement — soumis par 04-dada2_LEP_launcher.sh
# Variables reçues via --export : SHARED_DIR
#
# Attend job 1 (plaque 1-5) pour charger err_fwd/rev_LEP.rds
# Produit dans SHARED_DIR :
#   seqtab_LEP_P6.rds
# ─────────────────────────────────────────────────────────────────────────────

#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=${SLURM_MAIL}
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G
#SBATCH --account=ondemand@biomics
#SBATCH --qos=cpu-ondemand-long
#SBATCH --time=16:00:00

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
export R_DEMUX_DIR="$PROJECT_DIR/results/cutadapt_LEP_4258570/demux"
export R_SCRATCH="$RUN_SCRATCH"
export R_SHARED_DIR="$SHARED_DIR"

Rscript - <<'EOF'
library(dada2)

demux_dir  <- Sys.getenv("R_DEMUX_DIR")
scratch    <- Sys.getenv("R_SCRATCH")
shared_dir <- Sys.getenv("R_SHARED_DIR")
n_threads  <- as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", unset="16"))

# ─────────────────────────────────────────────────────────────────────────
# ÉTAPE 1 : filterAndTrim plaque 6
# ─────────────────────────────────────────────────────────────────────────
cat("=== filterAndTrim (plaque 6) ===\n\n")

all_R1 <- sort(list.files(demux_dir, pattern="_R1\\.fastq\\.gz$", full.names=TRUE))
all_R2 <- sort(list.files(demux_dir, pattern="_R2\\.fastq\\.gz$", full.names=TRUE))
if (length(all_R1) == 0) stop("Aucun fichier R1 trouvé dans ", demux_dir)

idx <- grepl("^6-", basename(all_R1))
R1  <- all_R1[idx]
R2  <- all_R2[idx]
if (length(R1) == 0) stop("Aucun fichier plaque 6 trouvé")
cat(sprintf("  %d samples détectés pour la plaque 6\n", length(R1)))

filt_dir <- file.path(scratch, "filtered")
dir.create(filt_dir, showWarnings=FALSE)

out_R1 <- file.path(filt_dir, sub("_R1\\.fastq\\.gz$", "_R1_filt.fastq.gz", basename(R1)))
out_R2 <- file.path(filt_dir, sub("_R2\\.fastq\\.gz$", "_R2_filt.fastq.gz", basename(R2)))

out <- filterAndTrim(
    R1, out_R1, R2, out_R2,
    truncLen    = c(220, 220),
    maxN        = 0,
    maxEE       = c(2, 2),
    truncQ      = 2,
    rm.phix     = TRUE,
    compress    = TRUE,
    multithread = n_threads
)

total_in  <- sum(out[, 1])
total_out <- sum(out[, 2])
pct       <- round(100 * total_out / total_in, 1)
cat(sprintf("  %d → %d reads (%.1f%% conservés)\n\n", total_in, total_out, pct))

# ─────────────────────────────────────────────────────────────────────────
# ÉTAPE 2 : charger le modèle d'erreur produit par job 1
# ─────────────────────────────────────────────────────────────────────────
cat("=== Chargement modèle d'erreur (job 1) ===\n\n")

err_fwd_path <- file.path(shared_dir, "err_fwd_LEP.rds")
err_rev_path <- file.path(shared_dir, "err_rev_LEP.rds")

if (!file.exists(err_fwd_path)) stop("Modèle d'erreur introuvable : ", err_fwd_path)

err_fwd <- readRDS(err_fwd_path)
err_rev <- readRDS(err_rev_path)
cat("  ✓ Modèles chargés\n\n")

# ─────────────────────────────────────────────────────────────────────────
# ÉTAPE 3 : dada + mergePairs + makeSequenceTable plaque 6
# ─────────────────────────────────────────────────────────────────────────
cat("=== dada + mergePairs (plaque 6) ===\n\n")

R1_filt <- sort(list.files(filt_dir, pattern="_R1_filt\\.fastq\\.gz$", full.names=TRUE))
R2_filt <- sort(list.files(filt_dir, pattern="_R2_filt\\.fastq\\.gz$", full.names=TRUE))

sample_names <- sub("_R1_filt\\.fastq\\.gz$", "", basename(R1_filt))
names(R1_filt) <- sample_names
names(R2_filt) <- sample_names

derep_fwd <- derepFastq(R1_filt, verbose=FALSE)
derep_rev <- derepFastq(R2_filt, verbose=FALSE)
names(derep_fwd) <- sample_names
names(derep_rev) <- sample_names

dada_fwd <- dada(derep_fwd, err=err_fwd, multithread=n_threads, verbose=TRUE)
dada_rev <- dada(derep_rev, err=err_rev, multithread=n_threads, verbose=TRUE)

mergers  <- mergePairs(dada_fwd, derep_fwd, dada_rev, derep_rev, verbose=FALSE)

seqtab_P6 <- makeSequenceTable(mergers)
cat(sprintf("\nPlaque 6 : %d samples → %d ASVs\n", nrow(seqtab_P6), ncol(seqtab_P6)))

cat("\nDistribution des longueurs d'amplicons :\n")
print(table(nchar(getSequences(seqtab_P6))))

saveRDS(seqtab_P6, file.path(shared_dir, "seqtab_LEP_P6.rds"))
cat(sprintf("\n✓ seqtab_LEP_P6.rds sauvegardé dans %s\n", shared_dir))
EOF

# ─────────────────────────────────────────────────────────────────────────────
rsync -av "$RUN_SCRATCH/" "$RUN_RESULTS/"
echo "✓ Résultats → $RUN_RESULTS"

_log END