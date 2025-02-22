#!/bin/bash

# Moves the successful ProteinMPNN or AF2 PDBs into a separate folder, given the out.txt file.

### REQUIRED ARGUMENTS
# $1. .out.txt
# $2. path to all PDBs (ProteinMPNN output OR AF2 output)
# $3. path to new output dir

out_txt=$1
input_dir=$2
output_dir=$3

tmpfile=$(mktemp)
cat $out_txt > "${tmpfile}"

# add new line to end of file
echo "" >> $tmpfile

set -e

mkdir -p $output_dir

{
    read
    while read -r x x x pae_interaction x x x x x x description successful
    do
        if [ "$successful" = "True" ]; then
            file_name="${description%_af2pred}"            

            # check for proteinmpnn pdb
            if [ -e "${input_dir}/${file_name}.pdb" ]; then
                cp $input_dir/${file_name}.pdb $output_dir
                echo Copied ${file_name}.pdb, pAE_interaction=$pae_interaction
            fi            

            # check for af2 pdb
            if [ -e "${input_dir}/${description}.pdb" ]; then
                mv $input_dir/${description}.pdb $output_dir
                echo Copied ${description}.pdb, pAE_interaction=$pae_interaction
            fi
        fi
    done

} < $tmpfile 

echo Done.
