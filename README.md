# RFdiffusion Pipeline

In 2023, the Baker Lab published [RFdiffusion](https://github.com/RosettaCommons/RFdiffusion), a deep-learning framework for *de novo* protein design. Using [ProteinMPNN and AlphaFold2](https://github.com/nrbennet/dl_binder_design) for validation, the authors demonstrated RFdiffusion's ability to tackle a diverse range of design challenges, including the successful generation of high-affinity binders to desired target proteins.

# Automated Validation Pipeline

A collection of scripts that automates the validation process of **RFdiffusion &#8594; ProteinMPNN &#8594; AlphaFold2 (AF2)**. Developed specifically for protein binder design on the SickKids High-Performance Computing (HPC) cluster.

![image](https://github.com/sophia-xie/protein-binder-design/assets/154448471/28c5fb17-8c1a-4819-af37-63d485732065)
<sub>Image adapted from [Watson et al.](https://www.nature.com/articles/s41586-023-06415-8)</sub>

In this pipeline, *RFdiffusion* designs binders to hotspot residues on the target protein. It then uses *ProteinMPNN* to generate sequences for the designed structures. Finally, *AlphaFold2* reconstructs the binders onto the target and evaluates their likelihood of success.

*In silico* success is defined by three confidence metrics produced by *AlphaFold2*:
1. **pae_interaction < 10**: how likely binder will bind to target (key indicator of success)
2. **plddt_binder > 80**: how likely binder will fold into its intended structure
3. **binder_aligned_rmsd < 1**: similarity between RFdiffusion and AF2 binder structures

### Input
The input parameters to the pipeline are as follows:
| Parameter | Description | Example | Notes |
| --- | --- | --- | --- |
| RUN_NAME | Name of the run | test_run1 | Must be unique. Can have two runs with the same target PDB but different names. |
| PATH_TO_PDB | Absolute path to target PDB | /home/usr/inputs/target.pdb | Avoid ~, $HOME, .., etc. Note that RFdiffusion can only process standard residues designated ATOM. |
| HOTSPOTS | Hotspot residues for RFdiffusion | A232,A245,A271 | Comma-separated list of <chain><residue>, no spaces. Use helper scripts to find hydrophobic residues closest to a known ligand or to sample hotspots from a predicted binding site. |
| MIN_LENGTH | Minimum length for binder (aa) | 40 | |
| MAX_LENGTH | Maximum length for binder (aa) | 60 | |
| NUM_STRUCTS | Number of RFdiffusion structures to generate  | 500 | |
| SEQUENCES_PER_STRUCT | Number of ProteinMPNN sequences to generate for each structure | 2 | |
| OUTPUT_DIR | Output directory | /home/usr/outputs/ | |
| SBATCH_FLAGS | Flags to pass to sbatch command | --mem=128G --tmp=128G --time=48:00:00 | See [Slurm HPC Quickstart](https://hpc.ccm.sickkids.ca/w/index.php/Slurm_HPC_Quickstart) for formatting and defaults. `--gpus 1` is already included. |

### Usage
#### Single run
To run one job:
```
sbatch --gpus 1 <SBATCH_FLAGS> scripts/pipeline.sh /path/to/rfdiffusion-pipeline <RUN_NAME> <PATH_TO_PDB> <HOTSPOTS> <MIN_LENGTH> <MAX_LENGTH> <NUM_STRUCTS> <SEQUENCES_PER_STRUCT> <OUTPUT_DIR>
```

#### Bulk run
To run multiple jobs at once, specify all input configurations in a single text file, one row per run. This file MUST follow the format provided in `inputs/input.txt` with the headers included. 
```
bash launch.sh inputs/input.txt
```

### Output
AF2 output scores are provided in `<OUTPUT_DIR>/<RUN_NAME>/<RUN_NAME>.out.txt`, sorted from best to worst design. The `successful` column indicates whether the design passed all three criteria (`pae_interaction` < 10, `plddt_binder` > 80, `binder_aligned_rmsd` < 1).

AF2 predicted structures .pdbs in `<OUTPUT_DIR>/<RUN_NAME>/af2/` can be visualized and compared with their respective RFdiffusion designs in `<OUTPUT_DIR>/<RUN_NAME>/rfdiffusion/`.

# Individual Steps of the Pipeline

The following explains how to run components of the pipeline individually.

## RFdiffusion
#### 1. Get contig
The contig tells RFdiffusion what section of the target protein to use. To extract the contig for the entire target protein:

```
python scripts/get_contigs.py <PATH_TO_PDB>
```

Output contig is printed.

#### 2. Run script
```
sbatch --gpus 1 --mem 32G --tmp 32G --time 12:00:00 scripts/rfdiffusion.sh <RUN_NAME> <OUTPUT_DIR> <PATH_TO_PDB> <CONTIG> <HOTSPOTS> <MIN_LENGTH> <MAX_LENGTH> <NUM_STRUCTS>
```
(GPU required, specify more resources as necessary)

Results are output to `<OUTPUT_DIR>/rfdiffusion/`.

## ProteinMPNN
Pass the directory of RFdiffusion output PDBs as `<input_dir>`.

```
sbatch scripts/proteinmpnn.sh <RUN_NAME> <OUTPUT_DIR> <SEQ_PER_STRUCT> <input_dir>
```
(GPU optional, specify more resources as necessary)

Results are output to `<OUTPUT_DIR>/proteinmpnn/`.

## AlphaFold2
Pass the directory of ProteinMPNN output PDBs as `<input_dir>`.

#### 1. Run script
```
sbatch --gpus 1 --mem 64G --tmp 64G --time 12:00:00 scripts/af2.sh <RUN_NAME> <OUTPUT_DIR> <input_dir>
```
(GPU required, specify more resources as necessary)

Results are output to `<OUTPUT_DIR>` and `<OUTPUT_DIR>/af2/`.

#### 2. Sort output
```
python scripts/filter_output.py <OUTPUT_DIR>/<RUN_NAME>.out.sc
```

The sorted text file will be created as `<OUTPUT_DIR>/<RUN_NAME>.out.txt`.

# Additional Functionalities

Here we provide a set of scripts to run additional, optional functionalities for the pipeline.

To run python scripts:
```
srun --pty bash -l  # enter a compute node
module load python/3.11.3  # this python version has the required packages for all scripts used below
```

## PDB Cleaning
Adapted from [PDB_Cleaner](https://github.com/LePingKYXK/PDB_cleaner). Removes ligands, waters, etc. For more complex PDBs, this may have unintended effects. We **recommend manually cleaning** your target proteins in [PyMOL](https://www.pymol.org/) instead.

Clean PDBs and any ligands are outputted to the specified output path. The program will generate a cleaned PDB for all files in the input folder. Usage:

```
python helper_scripts/pdb_cleaner.py <folder-of-input-pdbs> <folder-for-output> <save_ligands(true/false)>
```

## Selecting Hotspot Residues

### Proteins with a Ligand 
For proteins with a known ligand, to generate accurate and effective hotspot residues to RFDiffusion, we developed 3 methods: 1) randomly select 6 hydrophobic residues within an 11-angstrom radius of the ligand centroid, 2) select the top 6 residues closest to ANY atom in the ligand, and 3) select residues which have closest beta-Carbon atoms to the ligand. This suite of residue selectors ensures we may select "important" binding residues that RFDiffusion will accept.

Usages:

```
python helper_scripts/residue_selection/select_residues_using_centroid.py <pdb-of-interest> <pdb-of-ligand> <output-path>
```

```
python helper_scripts/residue_selection/select_residues_using_AAdistance.py <pdb-of-interest> <pdb-of-ligand> <output-path>
```

```
python helper_scripts/residue_selection/select_residues_PPinterface.py <pdb-of-interest> <pdb-of-ligand> <number-of-residues> <output-path>
```

### Proteins without a Ligand

When no ligands are present, or novel binding sites are desired, we can use protein binding site prediction methods.

Currently installed:
#### [P2Rank](https://github.com/rdk/p2rank) (2018)
A rapid, template-free machine learning model based on Random Forest.

```
sbatch scripts/p2rank.sh <input_pdb> <output_dir>
```

Predicted pockets will be output in order of confidence to `output_dir/<pdb_name>.pdb_predictions.csv`. Pockets and residues can be viewed by downloading and opening `output_dir/visualizations/`.

## Fold Conditioning
*RFdiffusion* has a fold conditioning feature that allows you to prespecify desired topologies for your binders. This is done by passing information from other PDBs with those desired topologies; these will act as scaffolds. Running *RFdiffusion* with fold conditioning requires three steps:

#### 1. Generate scaffolds for the PDBs with desired binder topologies
```
bash helper_scripts/make_scaffolds.sh <pdb_dir> <binder_scaffolds_outdir>
```
This will create a secondary structure (`*_ss.pt`) and block adjacency (`_*adj.pt`) file for each PDB.

#### 2. Generate scaffold for target
```
bash helper_scripts/make_scaffolds.sh <target_pdb> <target_scaffold_outdir>
```
This will create a secondary structure (`*_ss.pt`) and block adjacency (`_*adj.pt`) file for the target.

#### 3. Run pipeline with fold conditioning
```
sbatch --gpus 1 <SBATCH_FLAGS> scripts/pipeline_fold_conditioning.sh /path/to/rfdiffusion-pipeline <RUN_NAME> <PATH_TO_PDB> <HOTSPOTS> <NUM_STRUCTS <SEQUENCES_PER_STRUCT> <OUTPUT_DIR> <target_scaffold_outdir>/<*_ss.pt> <target_scaffold_outdir>/<*_adj.pt> <binder_scaffolds_outdir>
```

## Mix and Match Binders
You may be interested in designing binders to one target protein, but validating them on another. This could be to analyze the specificity of the binders to similar proteins. Or, the protein was truncated for RFdiffusion, but the entire structure is to be used in AF2 validation.

The script below takes designed binders from ProteinMPNN-generated PDBs and adds them to a separate target PDB. This output can then be passed to AF2, allowing the designed binders to be validated on proteins they weren't designed for. Note that this script handles AF2's requirement for unique residue indices across chains.

```
python helper_scripts/integrate_binders.py <old_target_proteinmpnn_outdir> <path_to_new_target_pdb> <new_output_dir>
```

## Isolate Successful Designs
Given the `.out.txt` file, you may wish to copy all successful PDBs into their own directory. This can be done for either ProteinMPNN-generated PDBs (to validate the successful sequences on another target, for example) or to isolate the successful AF2 reconstructed designs.

```
bash helper_scripts/isolate_successful.sh <.out.txt> <folder_with_all_pdbs> <new_folder_for_successful_pdbs_only>
```

# Troubleshooting

* **No module named 'MODULE_NAME':** Avoid running the automated pipeline from a compute node. RFdiffusion requires a specific Python module to run. If you're on a compute node with Python loaded, it may try to use packages from the newest Python version available.
* **Struct with tag <SAMETAG> failed in 0 seconds with error: <class 'EXCEPTION'>:** See [dl_binder_design: Troubleshooting](https://github.com/nrbennet/dl_binder_design?tab=readme-ov-file#troubleshooting-)
