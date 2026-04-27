#!/bin/bash
#SBATCH -c 1 # Number of cores
#SBATCH -p arguelles_delgado,shared,sapphire
#SBATCH --mem 10000
#SBATCH -t 0-12:00 # Maximum execution time (D-HH:MM)
#SBATCH -J TAMBO
#SBATCH -o /n/netscratch/arguelles_delgado_lab/Everyone/pzhelnin/corsika_tambo/Larger_Valley/output/output_%A.out
#SBATCH -e /n/netscratch/arguelles_delgado_lab/Everyone/pzhelnin/corsika_tambo/Larger_Valley/error/error_%A.err

export PATH=/n/home03/pzhelnin/.juliaup/bin/julia:$PATH
singularity_command=$1
eval $singularity_command