rule post_filter:
	input:
		ints = rules.combine_ints.output.all,
	output:
		kept = temp("{outpath}/{dset}/ints/{samp}.{host}.{virus}.integrations.filter.txt"),
		excluded = temp("{outpath}/{dset}/ints/{samp}.{host}.{virus}.integrations.removed.txt"),
	params:
		filterstring = lambda wildcards: get_value_from_df(wildcards, 'filter'),
                srcdir=workflow.basedir
	resources:
		mem_mb=lambda wildcards, attempt, input: int(resources_list_with_min_and_max(input, attempt, 1.5)),
		time = lambda wildcards, attempt: (30, 120, 1440, 10080)[attempt - 1],
	container:
		"docker://szsctt/isling:latest"
	conda: "../envs/filter.yml"
	shell:
		"""
		python3 {params.srcdir}/scripts/filter.py -i {input.ints} -k {output.kept} -e {output.excluded} -c '{params.filterstring}'
		"""

rule sort_bed:
	input:
		unsorted = "{name}.bed"
	output:
		sorted = "{name}.sorted.bed"
	container:
		"docker://szsctt/isling:latest"
	shell:
		"sort -k1,1 -k2,2n {input.unsorted} > {output.sorted}"

rule exclude_bed:
	input:
		beds = lambda wildcards: [os.path.splitext(i)[0] + '.sorted.bed' for i in get_value_from_df(wildcards, 'bed_exclude')],
		filt = rules.post_filter.output.kept,
		excluded = rules.post_filter.output.excluded
	output:
		tmp = temp("{outpath}/{dset}/ints/{samp}.{host}.{virus}.integrations.filter2.txt.tmp"),
		kept = temp("{outpath}/{dset}/ints/{samp}.{host}.{virus}.integrations.filter2.txt"),
		excluded = temp("{outpath}/{dset}/ints/{samp}.{host}.{virus}.integrations.removed2.txt"),
	resources:
		mem_mb=lambda wildcards, attempt, input: int(resources_list_with_min_and_max(input, attempt, 1.5)),
		time = lambda wildcards, attempt: (30, 120, 1440, 10080)[attempt - 1],
	container:
		"docker://szsctt/isling:latest"
	conda:
		"../envs/bedtools.yml"
	shell:
		"""
		cp {input.filt} {output.tmp}
		ARRAY=( {input.beds} )
		for bed in "${{ARRAY[@]}}"; do
			echo "excluding integrations that intersect with $bed"
			head -n1 {input.filt} > {output.kept}
			bedtools intersect -v -a {output.tmp} -b $bed >> {output.kept}
			bedtools intersect -u -a {output.tmp} -b $bed >> {output.excluded}
			cp {output.kept} {output.tmp}
		done
		"""

def get_for_include_bed(wildcards, file_type):
	assert file_type in {'kept', 'excluded'}
	# if there aren't any bed files to use for excluding
	if len(get_value_from_df(wildcards, 'bed_exclude')) == 0:
		if file_type == 'kept':
			return rules.post_filter.output.kept
		else:
			return rules.post_filter.output.excluded
	# if there are, then use files after excluding
	else:
		if file_type == 'kept':
			return rules.exclude_bed.output.kept
		else:
			return rules.exclude_bed.output.excluded
		

rule include_bed:
	input:
		beds = lambda wildcards: [os.path.splitext(i)[0] + '.sorted.bed' for i in get_value_from_df(wildcards, 'bed_include')],	
		filt = lambda wildcards:  get_for_include_bed(wildcards, 'kept'),
		excluded = lambda wildcards:  get_for_include_bed(wildcards, 'excluded')
	output:
		tmp = temp("{outpath}/{dset}/ints/{samp}.{host}.{virus}.integrations.filter3.txt.tmp"),
		kept = temp("{outpath}/{dset}/ints/{samp}.{host}.{virus}.integrations.filter3.txt"),
		excluded = temp("{outpath}/{dset}/ints/{samp}.{host}.{virus}.integrations.removed3.txt"),
	resources:
		mem_mb=lambda wildcards, attempt, input: int(resources_list_with_min_and_max(input, attempt, 1.5)),
		time = lambda wildcards, attempt: (30, 120, 1440, 10080)[attempt - 1],
	container:
		"docker://szsctt/isling:latest"
	conda:
		"../envs/bedtools.yml"
	shell:
		"""
		cp {input.filt} {output.tmp}
 
		ARRAY=( {input.beds} )
		for bed in "${{ARRAY[@]}}"; do
			echo "only keepint integrations that intersect with $bed"
			head -n1 {input.filt} > {output.kept}
			bedtools intersect -u -a {output.tmp} -b $bed >> {output.kept}
			bedtools intersect -v -a {output.tmp} -b $bed >> {output.excluded}
			cp {output.kept} {output.tmp}
		done
		"""

def get_post_final(wildcards, file_type):
	assert file_type in {'kept', 'excluded'}
	exclude_beds = len(get_value_from_df(wildcards, 'bed_exclude'))
	include_beds = len(get_value_from_df(wildcards, 'bed_exclude'))
	
	# if there aren't any bed files to use for excluding
	if exclude_beds == 0 and include_beds == 0:
		if file_type == 'kept':
			return rules.post_filter.output.kept
		else:
			return rules.post_filter.output.excluded
	# if there are, then use files after excluding
	elif exclude_beds != 0:
		if file_type == 'kept':
			return rules.exclude_bed.output.kept
		else:
			return rules.exclude_bed.output.excluded
	else:
		if file_type == 'kept':
			return rules.include_bed.output.kept
		else:
			return rules.include_bed.output.excluded		


rule post_final:
	input:
		kept = lambda wildcards: get_post_final(wildcards, 'kept'),
		excluded = lambda wildcards: get_post_final(wildcards, 'excluded'),
	output:
		kept = "{outpath}/{dset}/ints/{samp}.{host}.{virus}.integrations.post.txt",
		excluded = temp("{outpath}/{dset}/ints/{samp}.{host}.{virus}.integrations.filter_fail.txt")
	resources:
		mem_mb=lambda wildcards, attempt, input: int(resources_list_with_min_and_max(input, attempt, 1.5)),
		time = lambda wildcards, attempt: (30, 120, 1440, 10080)[attempt - 1],
	container:
		"docker://szsctt/isling:latest"
	shell:
		"""
		mv {input.kept} {output.kept}
		mv {input.excluded} {output.excluded}
		"""

rule separate_unique_locations:
	input:
		kept = rules.post_final.output.kept
	output:
		unique = "{outpath}/{dset}/ints/{samp}.{host}.{virus}.integrations.post.unique.txt",
		at_least_one_ambig = temp("{outpath}/{dset}/ints/{samp}.{host}.{virus}.integrations.post.atleastone.txt.tmp"),
		one_ambig = temp("{outpath}/{dset}/ints/{samp}.{host}.{virus}.integrations.post.one.txt.tmp"),
		host_ambig = "{outpath}/{dset}/ints/{samp}.{host}.{virus}.integrations.post.host_ambig.txt",
		virus_ambig = "{outpath}/{dset}/ints/{samp}.{host}.{virus}.integrations.post.virus_ambig.txt",
		both_ambig = "{outpath}/{dset}/ints/{samp}.{host}.{virus}.integrations.post.both_ambig.txt",
	params:
		mapq = lambda wildcards: int(get_value_from_df(wildcards, 'mapq_thresh')),
                srcdir=workflow.basedir
	container:
		"docker://szsctt/isling:latest"
	conda: "../envs/filter.yml"
	resources:
		mem_mb=lambda wildcards, attempt, input: int(resources_list_with_min_and_max(input, attempt, 1.5)),
		time = lambda wildcards, attempt: (30, 120, 1440, 10080)[attempt - 1],
	shell:
		"""
		# get uniquely localised integrations as kept
		python3 {params.srcdir}/scripts/filter.py \
		-i {input.kept} \
		-k {output.unique} \
		-e {output.at_least_one_ambig} \
		-c 'HostMapQ >= {params.mapq} and ViralMapQ >= {params.mapq} and HostAmbiguousLocation == False and ViralAmbiguousLocation == False'
		
		# get both ambiguous itegrations as kept
		python3 {params.srcdir}/scripts/filter.py \
		-i {output.at_least_one_ambig} \
		-k {output.both_ambig} \
		-e {output.one_ambig} \
		-c '(HostMapQ < {params.mapq} or HostAmbiguousLocation == True) and (ViralMapQ < {params.mapq} or ViralAmbiguousLocation == True)'
		
		# kept > ambiguous in virus, excluded > ambiguous in host
		python3 {params.srcdir}/scripts/filter.py \
		-i {output.one_ambig} \
		-k {output.virus_ambig} \
		-e {output.host_ambig} \
		-c '(ViralMapQ < {params.mapq} or ViralAmbiguousLocation == True)'	

		"""

rule rmd_summary_dataset:
	input:
		unique = lambda wildcards: expand(
							strip_wildcard_constraints(rules.separate_unique_locations.output.unique), 
							zip,
							samp = toDo.loc[toDo['dataset'] == wildcards.dset,'sample'],
							host = toDo.loc[toDo['dataset'] == wildcards.dset,'host'],
							virus = toDo.loc[toDo['dataset'] == wildcards.dset,'virus'],
							allow_missing = True
					),
		host_ambig = lambda wildcards: expand(
							strip_wildcard_constraints(rules.separate_unique_locations.output.host_ambig), 
							zip,
							samp = toDo.loc[toDo['dataset'] == wildcards.dset,'sample'],
							host = toDo.loc[toDo['dataset'] == wildcards.dset,'host'],
							virus = toDo.loc[toDo['dataset'] == wildcards.dset,'virus'],
							allow_missing = True
					),		
		virus_ambig = lambda wildcards: expand(
							strip_wildcard_constraints(rules.separate_unique_locations.output.virus_ambig), 
							zip,
							samp = toDo.loc[toDo['dataset'] == wildcards.dset,'sample'],
							host = toDo.loc[toDo['dataset'] == wildcards.dset,'host'],
							virus = toDo.loc[toDo['dataset'] == wildcards.dset,'virus'],
							allow_missing = True
					),
		conds = rules.write_analysis_summary.output.tsv,
		host_ann = lambda wildcards: expand("{prefix}.ann",
						prefix = toDo.loc[toDo['dataset'] == wildcards.dset,'host_prefix']), 
		virus_ann = lambda wildcards: expand("{prefix}.ann",
						prefix = toDo.loc[toDo['dataset'] == wildcards.dset,'virus_prefix']), 
		host_stats = lambda wildcards: expand(strip_wildcard_constraints(rules.host_stats.output.stats),
							zip,
							samp = toDo.loc[toDo['dataset'] == wildcards.dset,'sample'],
							host = toDo.loc[toDo['dataset'] == wildcards.dset,'host'],
							virus = toDo.loc[toDo['dataset'] == wildcards.dset,'virus'],
							allow_missing=True
							),
                virus_stats = lambda wildcards: expand(strip_wildcard_constraints(rules.virus_stats.output.stats),
							zip,
							samp = toDo.loc[toDo['dataset'] == wildcards.dset,'sample'],
							virus = toDo.loc[toDo['dataset'] == wildcards.dset,'virus'],
							allow_missing=True
							),


	output:
		rmd = "{outpath}/summary/{dset}.html"
	resources:
		mem_mb=lambda wildcards, attempt, input: int(resources_list_with_min_and_max(input, attempt, 3, 1000)),
		time = lambda wildcards, attempt: (30, 120, 1440, 10080)[attempt - 1],
	params:
		outfile = lambda wildcards, output: os.path.abspath(output.rmd),
		host = lambda wildcards: toDo.loc[(toDo['dataset'] == wildcards.dset).idxmax(), 'host'],
		virus = lambda wildcards: toDo.loc[(toDo['dataset'] == wildcards.dset).idxmax(), 'virus'],
		outdir = lambda wildcards, input: multiple_dirname(input.unique[0], 2),
		host_prefix = lambda wildcards, input: os.path.splitext(input.host_ann[0])[0],
		virus_prefix = lambda wildcards, input: os.path.splitext(input.virus_ann[0])[0],
		workdir = lambda wildcards: os.getcwd(),
                srcdir = workflow.basedir
	conda:
		"../envs/rscripts.yml"
	container:
		"docker://szsctt/isling:latest"
	shell:
		"""
		Rscript -e 'params=list("outdir"="{params.outdir}", "host"="{params.host}", "virus"="{params.virus}", "host_prefix"="{params.host_prefix}", "virus_prefix"="{params.virus_prefix}", "conds"="{input.conds}", "dataset"="{wildcards.dset}", "workdir"="{params.workdir}", "srcdir" = "{params.srcdir}"); rmarkdown::render("{params.srcdir}/scripts/summary.Rmd", output_file="{params.outfile}")'
		"""
	
rule rmd_summary:
	input:
		unique = lambda wildcards: expand(
							strip_wildcard_constraints(rules.separate_unique_locations.output.unique), 
							zip,
							samp = toDo.loc[:, 'sample'],
							host = toDo.loc[:, 'host'],
							virus = toDo.loc[:, 'virus'],
							dset = toDo.loc[:, 'dataset'],
							allow_missing = True
					),
		host_ambig = lambda wildcards: expand(
							strip_wildcard_constraints(rules.separate_unique_locations.output.host_ambig), 
							zip,
							samp = toDo.loc[:, 'sample'],
							host = toDo.loc[:, 'host'],
							virus = toDo.loc[:, 'virus'],
							dset = toDo.loc[:, 'dataset'],
							allow_missing = True
					),		
		virus_ambig = lambda wildcards: expand(
							strip_wildcard_constraints(rules.separate_unique_locations.output.virus_ambig), 
							zip,
							samp = toDo.loc[:, 'sample'],
							host = toDo.loc[:, 'host'],
							virus = toDo.loc[:, 'virus'],
							dset = toDo.loc[:, 'dataset'],
							allow_missing = True
					),
		both_ambig = lambda wildcards: expand(
							strip_wildcard_constraints(rules.separate_unique_locations.output.both_ambig), 
							zip,
							samp = toDo.loc[:, 'sample'],
							host = toDo.loc[:, 'host'],
							virus = toDo.loc[:, 'virus'],
							dset = toDo.loc[:, 'dataset'],
							allow_missing = True
					),
		conds = lambda wildcards: set(expand(
							strip_wildcard_constraints(rules.write_analysis_summary.output.tsv),
							dset = toDo.loc[:, 'dataset'],
							allow_missing = True
					)),
		host_ann = lambda wildcards: expand("{prefix}.ann", prefix = set(toDo.loc[:, 'host_prefix'])),
		virus_ann = lambda wildcards: expand("{prefix}.ann", prefix = set(toDo.loc[:, 'virus_prefix'])),
	output:
		rmd = "{outpath}/integration_summary.html"
	resources:
		mem_mb=lambda wildcards, attempt, input: int(resources_list_with_min_and_max(input, attempt, 3, 1000)),
		time = lambda wildcards, attempt: (30, 120, 1440, 10080)[attempt - 1],
	params:
		summary_dir = lambda wildcards, output: os.path.join(os.path.abspath(os.path.dirname(output.rmd)), "summary"),
		datasets = lambda wildcards: ", ".join([f'"{i}"' for i in set(toDo['dataset'])]),
		output_file = lambda wildcards, output: os.path.abspath(output.rmd),
		script = lambda wildcards: os.path.abspath(workflow.basedir + "/scripts/summary_all.Rmd"),
		host_prefixes = lambda wildcards, input:  "c('" + "', '".join(os.path.splitext(i)[0] for i in input.host_ann) + "')",
		virus_prefixes = lambda wildcards, input: "c('" + "', '".join(os.path.splitext(i)[0] for i in input.virus_ann) + "')",
		bucket = workflow.default_remote_prefix,
		workdir = lambda wildcards: os.getcwd(),
                srcdir = workflow.basedir
	conda:
		"../envs/rscripts.yml"
	container:
		"docker://szsctt/isling:latest"
	shell:
		"""
		Rscript -e 'params=list("workdir"="{params.workdir}","bucket"="{params.bucket}","summary_dir"="{params.summary_dir}", "host_prefixes"="{params.host_prefixes}", "virus_prefixes"="{params.virus_prefixes}", "datasets"=c({params.datasets})); rmarkdown::render("{params.script}", output_file="{params.output_file}")'
		"""
		
		
rule merged_bed:
	input:
		txt = rules.separate_unique_locations.output.unique
	output:
		merged = "{outpath}/{dset}/ints/{samp}.{host}.{virus}.integrations.post.unique.merged.txt"
	params:
		method = lambda wildcards: get_value_from_df(wildcards, 'merge_method'),
		n = lambda wildcards: int(get_value_from_df(wildcards, 'merge_n_min')),
                srcdir = workflow.basedir
	container:
		"docker://szsctt/isling:latest"
	conda:
		"../envs/bedtools.yml"
	resources:
		mem_mb=lambda wildcards, attempt, input: int(resources_list_with_min_and_max(input, attempt, 1.5, 1000)),
		time = lambda wildcards, attempt: (30, 120, 1440, 10080)[attempt - 1],
	threads: 1
	shell:
		"""
		python3 {params.srcdir}/scripts/merge.py -i {input.txt} -o {output.merged} -c {params.method} -n {params.n}
		"""

rule summarise:
	input: 
		merged_beds = lambda wildcards: expand(strip_wildcard_constraints(rules.merged_bed.output.merged), zip,
							samp = toDo.loc[toDo['dataset'] == wildcards.dset,'sample'],
							host = toDo.loc[toDo['dataset'] == wildcards.dset,'host'],
							virus = toDo.loc[toDo['dataset'] == wildcards.dset,'virus'],
							allow_missing = True
					)
	output:
		"{outpath}/summary/{dset}.xlsx",
		"{outpath}/summary/{dset}_annotated.xlsx"
	conda:
		"../envs/rscripts.yml"
	container:
		"docker://szsctt/isling:latest"
	params:
		outdir = lambda wildcards, output: path.dirname(output[0]),
		host = lambda wildcards: set(toDo.loc[toDo['dataset'] == wildcards.dset,'host']).pop(),
		virus = lambda wildcards: set(toDo.loc[toDo['dataset'] == wildcards.dset,'virus']).pop(),
                srcdir = workflow.basedir
	resources:
		mem_mb=lambda wildcards, attempt, input: resources_list_with_min_and_max(input, attempt, 3, 1000),
		time = lambda wildcards, attempt: (30, 120, 1440, 10080)[attempt - 1],
	threads: 1
	shell:
		"Rscript scripts/summarise_ints.R {params.host} {params.virus} {input} {params.outdir}"

rule ucsc_bed:
	input:
		merged_beds = lambda wildcards: expand(strip_wildcard_constraints(rules.merged_bed.output.merged), zip,
							samp = toDo.loc[toDo['dataset'] == wildcards.dset,'sample'],
							host = toDo.loc[toDo['dataset'] == wildcards.dset,'host'],
							virus = toDo.loc[toDo['dataset'] == wildcards.dset,'virus'],
							allow_missing = True
					)
	output:
		"{outpath}/summary/ucsc_bed/{dset}.post.bed"
	params:
		outdir = lambda wildcards, output: f"{os.path.dirname(output[0])}/{wildcards.dset}",
		host = lambda wildcards: set(toDo.loc[toDo['dataset'] == wildcards.dset,'host']).pop(),
		virus = lambda wildcards: set(toDo.loc[toDo['dataset'] == wildcards.dset,'virus']).pop()
	conda:
		"../envs/rscripts.yml"
	container:
		"docker://szsctt/isling:latest"
	resources:
		mem_mb=lambda wildcards, attempt, input: resources_list_with_min_and_max(input, attempt, 3, 1000),
		time = lambda wildcards, attempt: (30, 120, 1440, 10080)[attempt - 1],
	threads: 1
	shell:
		"""
		Rscript {params.srcdir}/scripts/writeBed.R {params.host} {params.virus} {input} {params.outdir}
		bash -e {params.srcdir}/scripts/format_ucsc.sh {params.outdir}
		"""

