# 2026-biosphere

## Description
<!-- Une phrase -->

## Structure
```
2026-biosphere/
├── scripts/
│   ├── job_template.sh   ← copier pour chaque nouveau job
│   └── check_run.sh      ← vérifier un run
├── config/
│   └── project.env       ← variables communes
├── results/              ← {jobname}_{jobid}/ par run
├── logs/                 ← .out / .err SLURM
├── docs/                 ← notes, protocoles
└── runs.log              ← registre de tous les jobs
```

## Procédure
```bash
cp scripts/job_template.sh scripts/mon_job.sh
# éditer mon_job.sh ...
git add scripts/mon_job.sh && git commit -m "feat: description"
sbatch scripts/mon_job.sh
bash scripts/check_run.sh results/mon_job_JOBID
```
