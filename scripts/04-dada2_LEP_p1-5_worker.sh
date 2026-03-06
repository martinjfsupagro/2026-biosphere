#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# DADA2 LEP — Job 1 : filterAndTrim + learnErrors + dada, plaques 1-5
# Ne pas lancer directement — soumis par 04-dada2_LEP_launcher.sh
# Variables reçues via --export : SHARED_DIR
#
# Produit dans SHARED_DIR :
#   err_fwd_LEP.rds       — modèle d'erreur forward (partagé avec job 2)
#   err_rev_LEP.rds       — modèle d'erreur reverse (partagé avec job 2)
#   seqtab_LEP_P1-5.rds   — table ASVs plaques 1-5
# ─────────────────────────────────────────────────────────────────────────────

#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=${SLURM_MAIL}
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --account=ondemand@biomics
#SBATCH --qos=cpu-ondemand-long
#SBATCH --time=12:00:00

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
# Export des variables bash → lues par Sys.getenv() dans R
# <<'EOF' (guillemets simples) = bash ne traite pas le contenu du heredoc
# → les backslash des regex R sont préservés tels quels
export R_DEMUX_DIR="$PROJECT_DIR/results/cutadapt_LEP_4258570/demux"
export R_SCRATCH="$RUN_SCRATCH"
export R_SHARED_DIR="$SHARED_DIR"

Rscript - <<'EOF'
library(dada2)

demux_dir  <- Sys.getenv("R_DEMUX_DIR")
scratch    <- Sys.getenv("R_SCRATCH")
shared_dir <- Sys.getenv("R_SHARED_DIR")
n_threads  <- as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", unset="16"))
plates     <- 1:5

# ── Lister tous les fichiers R1/R2 du dossier demux ──────────────────────
all_R1 <- sort(list.files(demux_dir, pattern="_R1\\.fastq\\.gz$", full.names=TRUE))
all_R2 <- sort(list.files(demux_dir, pattern="_R2\\.fastq\\.gz$", full.names=TRUE))
if (length(all_R1) == 0) stop("Aucun fichier R1 trouvé dans ", demux_dir)

# ─────────────────────────────────────────────────────────────────────────
# ÉTAPE 1 : filterAndTrim en boucle sur les plaques 1-5
# ─────────────────────────────────────────────────────────────────────────
cat("=== filterAndTrim (plaques 1-5) ===\n\n")

filt_dir <- file.path(scratch, "filtered")
dir.create(filt_dir, showWarnings=FALSE)

for (plate in plates) {
    cat(sprintf("--- Plaque %d ---\n", plate))

    idx <- grepl(paste0("^", plate, "-"), basename(all_R1))
    R1  <- all_R1[idx]
    R2  <- all_R2[idx]

    if (length(R1) == 0) { cat(sprintf("  aucun fichier pour plaque %d, ignoré\n", plate)); next }

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
    cat(sprintf("  %d samples : %d → %d reads (%.1f%% conservés)\n\n",
                length(R1), total_in, total_out, pct))
}

# ─────────────────────────────────────────────────────────────────────────
# ÉTAPE 2 : learnErrors sur plaque 1
# ─────────────────────────────────────────────────────────────────────────
cat("=== learnErrors (plaque 1) ===\n\n")

R1_P1 <- sort(list.files(filt_dir, pattern="^1-.*_R1_filt\\.fastq\\.gz$", full.names=TRUE))
R2_P1 <- sort(list.files(filt_dir, pattern="^1-.*_R2_filt\\.fastq\\.gz$", full.names=TRUE))

if (length(R1_P1) == 0) stop("Aucun fichier filtré plaque 1 trouvé dans ", filt_dir)
cat(sprintf("  %d samples plaque 1 utilisés pour learnErrors\n", length(R1_P1)))

cat("--- err_fwd ---\n")
err_fwd <- learnErrors(R1_P1, multithread=n_threads, verbose=TRUE)

cat("\n--- err_rev ---\n")
err_rev <- learnErrors(R2_P1, multithread=n_threads, verbose=TRUE)

# Sauvegarde dans SHARED_DIR (lu par job 2)
saveRDS(err_fwd, file.path(shared_dir, "err_fwd_LEP.rds"))
saveRDS(err_rev, file.path(shared_dir, "err_rev_LEP.rds"))
cat(sprintf("\n✓ Modèles d'erreur sauvegardés dans %s\n\n", shared_dir))

# ─────────────────────────────────────────────────────────────────────────
# ÉTAPE 3 : dada + mergePairs + makeSequenceTable en boucle plaques 1-5
# ─────────────────────────────────────────────────────────────────────────
cat("=== dada + mergePairs (plaques 1-5) ===\n\n")

seqtabs <- list()

for (plate in plates) {
    cat(sprintf("--- Plaque %d ---\n", plate))

    R1_filt <- sort(list.files(filt_dir,
        pattern=paste0("^", plate, "-.*_R1_filt\\.fastq\\.gz$"), full.names=TRUE))
    R2_filt <- sort(list.files(filt_dir,
        pattern=paste0("^", plate, "-.*_R2_filt\\.fastq\\.gz$"), full.names=TRUE))

    if (length(R1_filt) == 0) { cat("  aucun fichier filtré, ignoré\n\n"); next }

    sample_names <- sub("_R1_filt\\.fastq\\.gz$", "", basename(R1_filt))
    names(R1_filt) <- sample_names
    names(R2_filt) <- sample_names

    # Déréplication
    derep_fwd <- derepFastq(R1_filt, verbose=FALSE)
    derep_rev <- derepFastq(R2_filt, verbose=FALSE)
    names(derep_fwd) <- sample_names
    names(derep_rev) <- sample_names

    # Inférence DADA
    dada_fwd <- dada(derep_fwd, err=err_fwd, multithread=n_threads, verbose=FALSE)
    dada_rev <- dada(derep_rev, err=err_rev, multithread=n_threads, verbose=FALSE)

    # Fusion
    mergers <- mergePairs(dada_fwd, derep_fwd, dada_rev, derep_rev, verbose=FALSE)

    # Table de séquences
    seqtabs[[plate]] <- makeSequenceTable(mergers)

    cat(sprintf("  %d samples → %d ASVs\n", nrow(seqtabs[[plate]]), ncol(seqtabs[[plate]])))

    # Libération mémoire — on garde seqtabs[[plate]], on libère tout le reste
    rm(derep_fwd, derep_rev, dada_fwd, dada_rev, mergers)
    gc()

    cat(sprintf("  mémoire libérée (plaque %d)\n\n", plate))
}

# Fusion des tables plaques 1-5
cat("=== mergeSequenceTables (plaques 1-5) ===\n")
seqtab_P1_5 <- mergeSequenceTables(tables = seqtabs)
cat(sprintf("  %d samples × %d ASVs\n", nrow(seqtab_P1_5), ncol(seqtab_P1_5)))

saveRDS(seqtab_P1_5, file.path(shared_dir, "seqtab_LEP_P1-5.rds"))
cat(sprintf("✓ seqtab_LEP_P1-5.rds sauvegardé dans %s\n", shared_dir))
EOF

# ─────────────────────────────────────────────────────────────────────────────
# Rapatriement (logs + script uniquement — les RDS sont déjà dans SHARED_DIR)
rsync -av "$RUN_SCRATCH/" "$RUN_RESULTS/"
echo "✓ Résultats → $RUN_RESULTS"

_log END