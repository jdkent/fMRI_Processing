#!/bin/bash
#Dependent on fMRI_preprocess.sh to be ran
#Designed for PACR-AD
set -o nounset
set -o pipefail

#Function to make sure commands are not run if their output already exists
#unless specified to overwrite by user
function clobber()
{
	
		if [ -e $1 ] && [ "${clob}" = true ]; then
			rm $@
			return 0
		elif [ -e $1 ] && [ "${clob}" = false ]; then
			return 1
		elif [ ! -e $1 ]; then
			return 0
		else
			echo "How did you get here?"
			return 1
		fi
}
clob=false
declare -a cond_array
declare -i cond_index
cond_index=0
while getopts "i:o:hc" OPTION; do
	case $OPTION in
		i)
			FLANKER_NIFTI=$OPTARG
			;;
		c)
			clob=true
			;;
		o)
			outDir=${OPTARG}
			;;
		h)
			echo "this is help (uninitialized)"
			;;
	esac
done

if [ -z "${outDir+z}" ]; then
	#one directory above where the FLANKER_NIFTI is
	outDir=$(dirname ${FLANKER_NIFTI})
fi

workingDir=$(dirname ${outDir})/$(basename ${outDir}.AFNI3)
mkdir -p ${workingDir}
#Using motion file from reconstruct.sh

#change into that directory
cd ${workingDir}

#get the subject number from ${FLANKER_NIFTI}
subNum=$(echo $(dirname ${FLANKER_NIFTI}) | egrep -o sub[0-9]+ | sed 's/sub//')


#Assuming behavioral data is here: /Volumes/VossLab/Projects/PACR-AD/Imaging/BehavData/
declare -a timing_array
timing_array=( $(ls /Volumes/VossLab/Projects/PACR-AD/Imaging/BehavData/sub${subNum}_1/*fixdur* | sort) )

cp ${timing_array[@]} ${workingDir}

time_index=0
for timing_file in ${timing_array[@]}; do
	awk -F' ' '{print $1}' ${workingDir}/$(basename ${timing_file}) > ${workingDir}/$(basename ${timing_file/.txt/1_column.txt})
	timing_array[${time_index}]=${workingDir}/$(basename ${timing_file/.txt/1_column.txt})
	time_index=$(( ${time_index} + 1 ))
done
#order
#0=con
#1=errors
#2=inc
#3=neu
1dBport -band 0 0.01 -input ${FLANKER_NIFTI} > ${workingDir}/highpass.1D
#find the motion file
motion_file=${outDir}/mc/mcImg_mm.par

clobber sub${subNum}_bucket.REML_cmd sub${subNum}_bucket.xmat.1D sub${subNum}_bucket_REML+orig.BRIK	sub${subNum}_bucket_REML+orig.HEAD	sub${subNum}_bucket_REMLvar+orig.BRIK	sub${subNum}_bucket_REMLvar+orig.HEAD &&\
3dDeconvolve -input ${FLANKER_NIFTI} \
-GOFORIT 2 \
-nfirst 0 \
-polort 0 \
-num_stimts 10 \
-mask ${outDir}/mask/*_mask.nii.gz \
-stim_times 1 ${timing_array[0]} 'GAM(6.0024,0.9996)' -stim_label 1 con \
-stim_times 2 ${timing_array[1]} 'GAM(6.0024,0.9996)' -stim_label 2 errors \
-stim_times 3 ${timing_array[2]} 'GAM(6.0024,0.9996)' -stim_label 3 inc \
-stim_times 4 ${timing_array[3]} 'GAM(6.0024,0.9996)' -stim_label 4 neu \
-stim_file  5 ${motion_file}[0]		-stim_label 5 roll \
-stim_file  6 ${motion_file}[1]		-stim_label 6 pitch \
-stim_file	7 ${motion_file}[2]		-stim_label 7 yaw \
-stim_file  8 ${motion_file}[3]		-stim_label 8 I_S \
-stim_file  9 ${motion_file}[4]		-stim_label 9 R_L \
-stim_file 10 ${motion_file}[5]		-stim_label 10 A_P \
-num_glt 8 \
-glt_label 1 con_ave -gltsym 'SYM: con' \
-glt_label 2 errors_ave -gltsym 'SYM: errors' \
-glt_label 3 inc_ave -gltsym 'SYM: inc' \
-glt_label 4 neu_ave -gltsym 'SYM: neu' \
-glt_label 5 con-neu -gltsym 'SYM: +con -neu' \
-glt_label 6 inc-neu -gltsym 'SYM: +inc -neu' \
-glt_label 7 con-inc -gltsym 'SYM: +con -inc' \
-glt_label 8 inc-con -gltsym 'SYM: +inc -con' \
-ortvec highpass.1D \
-tout -fout -bucket sub${subNum}_bucket -xjpeg sub${subNum}_glm_matrix.jpg -x1D_stop &&\
3dREMLfit -matrix sub${subNum}_bucket.xmat.1D \
-GOFORIT 2 \
-input ${FLANKER_NIFTI} \
-mask ${outDir}/mask/*_mask.nii.gz \
-fout -tout -Rbuck sub${subNum}_bucket_REML -Rvar sub${subNum}_bucket_REMLvar -verb


declare -a output_labels
output_labels=($(3dinfo -verb sub${subNum}_bucket_REML+orig | grep \#[0-9] | awk -F"'" '{print $2}'))
for output_index in $(seq 0 $((${#output_labels[@]}-1))); do
	clobber ${output_labels[${output_index}]}.nii.gz &&\
	3dcalc -float -a sub${subNum}_bucket_REML+orig[${output_index}] -expr 'a' -prefix ${output_labels[${output_index}]}.nii.gz
	if [[ "${output_labels[${output_index}]}" == *Tstat ]]; then
		clobber ${output_labels[${output_index}]/Tstat/Zstat}.nii.gz &&\
		dof=$(3dinfo ${output_labels[${output_index}]}.nii.gz | grep statpar | awk '{print $6}') &&\
		3dcalc -a ${output_labels[${output_index}]}.nii.gz -expr 'fitt_t2z(a,299)' -prefix ${output_labels[${output_index}]/Tstat/Zstat}.nii.gz
		#same as 3dmerge -1zscore -datum float -prefix Zmap.nii Fmap.nii

		clobber ${output_labels[${output_index}]/Tstat/Zstat_std}.nii.gz &&\
		applywarp -i ${output_labels[${output_index}]/Tstat/Zstat}.nii.gz \
		-o ${output_labels[${output_index}]/Tstat/Zstat_std}.nii.gz \
		-r ${FSLDIR}/data/standard/MNI152_T1_2mm_brain.nii.gz \
		--premat=${outDir}/reg/example_func2highres.mat \
		-w ${outDir}/reg/highres2standard_warp.nii.gz
	fi

	if [[ "${output_labels[${output_index}]}" == *Coef ]]; then
		clobber ${output_labels[${output_index}]/Coef/Coef_std}.nii.gz &&\
		applywarp -i ${output_labels[${output_index}]/Tstat/Zstat}.nii.gz \
		-o ${output_labels[${output_index}]/Coef/Coef_std}.nii.gz \
		-r ${FSLDIR}/data/standard/MNI152_T1_2mm_brain.nii.gz \
		--premat=${outDir}/reg/example_func2highres.mat \
		-w ${outDir}/reg/highres2standard_warp.nii.gz
	fi
done

#go back to directory the command was called in
cd -

