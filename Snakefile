#### pipeline for detecting viral integrations in NGS data ####

# the pipeline detecets viral integrations into a host genome in short reads by 
# identifying chimeric reads, discordant read pairs, and short insertions of virus 
# flanked by host sequence on both sides

# note that only paired-end reads are supported
#
# A yaml file specifies which references are to be used with which datasets
# the pipline lives in the isling folder which should be cloned
# from the git repo

# the steps in the pipeline are as follows:
# 1. preprocessing
#   - convert bam files to fastq, if necessary
#   - either merge R1 and R2 using seqprep, or don't do merging, as specified in the config file
# 2. alignments
#   - align all the reads to the virus
#   - remove duplicates
#   - extract only the alinged reads to a fastq
#   - align these reads to the host
# 3. perl scripts
#   - run perl scripts with alignment sam files as inputs to detect integrations
# 4. postprocessing
#   - apply various types of postprocessing: dedup, filter, mask, annotate
#   - generate ouput xlsx files for each dataset
#   - write output files for visualzation in UCSC browser
#  
# the primary output of the pipeline is the xlsx files for each datasets which
# contain the details of the detected integrations.

#### python modules ####

from glob import glob
from os import path, getcwd
import pandas as pd
import pdb
import sys
import re

# set working directory - directory in which snakefile is located
if 'snakedir' not in config:
	config['snakedir'] = getcwd()
	print(f"warning: 'snakedir' not specified in config file: using current working directory ({config['snakedir']})")
workdir: config['snakedir']
snakedir = workflow.basedir
config.pop('snakedir')

# Check if cloud computing is used
config['bucket'] = workflow.default_remote_prefix

sys.path.append(os.path.join(snakedir, "scripts/"))
from scripts.make_df import make_df, make_reference_dict


# construct dataframe with wildcards and other information about how to run analysis

toDo = make_df(config)

# construct dictionary with reference names as keys and reference fastas as values

ref_names = make_reference_dict(toDo)

#### global wildcard constraints ####

wildcard_constraints:
	virus = "|".join([re.escape(i) for i in set(toDo.loc[:,'virus'])]),
	samp = "|".join([re.escape(i) for i in set(toDo.loc[:,'sample'])]),
	dset = "|".join([re.escape(i) for i in set(toDo.loc[:,'dataset'])]),
	host = "|".join([re.escape(i) for i in set(toDo.loc[:,'host'])]),
	align_type = "bwaPaired|bwaSingle",
	outpath = "|".join([re.escape(i) for i in set(toDo.loc[:,'outdir'])]),
	part = "\d+"

#### local rules ####
localrules: all, touch_merged, check_bam_input_is_paired

#### target files ####
conditions = set()
summary_files = set()
ucsc_files = set()
merged_bed = set()

for i, row in toDo.iterrows():
	if row['generate_report']:
		summary_files.add(f"{row['outdir']}/summary/{row['dataset']}.html")
		summary_files.add(f"{row['outdir']}/integration_summary.html")
	ucsc_files.add(f"{row['outdir']}/summary/ucsc_bed/{row['dataset']}.post.bed")
	conditions.add(f"{row['outdir']}/summary/{row['dataset']}.analysis_conditions.tsv")
	merged_bed.add(f"{row['outdir']}/{row['dataset']}/ints/{row['sample']}.{row['host']}.{row['virus']}.integrations.post.unique.merged.txt")

rule all:
	input:
		conditions,
		summary_files,
#		ucsc_files,
		merged_bed,
#		expand("{outpath}/{dset}/virus_aligned/{samp}.{virus}.bam",
#			zip,
#			outpath = toDo.loc[:,'outdir'],
#			dset = toDo.loc[:,'dataset'],
#			samp = toDo.loc[:,'sample'],
#			virus = toDo.loc[:,'virus'],
#			host = toDo.loc[:,'host'],
#			),
#		expand("{outpath}/{dset}/host_aligned/{samp}.{host}.readsFrom{virus}.bam",
#			zip,
#			outpath = toDo.loc[:,'outdir'],
#			dset = toDo.loc[:,'dataset'],
#			samp = toDo.loc[:,'sample'],
#			virus = toDo.loc[:,'virus'],
#			host = toDo.loc[:,'host'],
#			)

#### read preprocessing ####
include: "snakemake_rules/preprocessing.smk"

#### alignments ####
include: "snakemake_rules/alignment.smk"

#### find integrations ####
include: "snakemake_rules/find_ints.smk"

#### postprocessing ####
include: "snakemake_rules/postprocessing.smk"


