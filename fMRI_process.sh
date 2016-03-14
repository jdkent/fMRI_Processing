#!/usr/bin/env bash
########################################################
# Name: 
#	fMRI_process.sh
# Purpose:
#	Preprocesses data from PACR-AD to make it ready for either 
#	AFNI or FSL GLMs
# Parameters:
#	i, 4D functional Volume
#   a, 3D anatomical Volume
#   c, overwrite output (optional)
#   o, Output Directory (optional)
# Produces:
#	4D functional dataset that has been
#	> Motion Corrected (AFNI)
#	> Spatially Smoothed (FSL)
#	> Highpass Filtered (AFNI) Now FSL
#	> temporally scaled (AFNI) Not anymore
#	> Registered to standard space (FSL)
# Preconditions
#	No further preconditions
#Postconditions
#	No further postconditions


############################################################
# Bash Settings
############################################################
#These are settings to help a script run "cleanly"
#set -o errexit #exits script when a command fails
set -o pipefail #the exit status of a command that returned a non-zero exit code during a pipe
set -o nounset #exit the script when you try to use undeclared variables
#set -o xtrace #prints out the commands a they are called, (for debugging)


############################################################
# Functions
############################################################
#What to run when user presses "control C" (kill script)
function control_c 
{
	echo -e "\n## Caught SIGINT: Cleaning up before exit"
	echo "Do you want to remove all output? (y/n)"
	read ans
	if [ "${ans}" = "y" ]; then
		rm -rf ${outDir}
	else
		echo "keeping output"
	fi
 	exit $?
}


function clobber
{	
	#Tracking Variables
	local -i num_existing_files=0
	local -i num_args=$#

	#Tally all existing outputs
	for arg in $@; do
		if [ -e "${arg}" ] && [ "${clob}" == true ]; then
			rm "${arg}"
		elif [ -e "${arg}" ] && [ "${clob}" == false ]; then
			num_existing_files=$(( ${num_existing_files} + 1 ))
			continue
		elif [ ! -e "${arg}" ]; then
			continue
		else
			echo "How did you get here?"
		fi
	done

	#see if the command should be run by seeing if the requisite files exist.
	#0=true
	#1=false
	if [ ${num_existing_files} -lt ${num_args} ]; then
		return 0
	else
		return 1
	fi

	#example usage
	#clobber test.nii.gz &&\
	#fslmaths input.nii.gz -mul 10 test.nii.gz
}

function command_check
{
	local arg="${1}"
	command -v "${arg}" > /dev/null 2>&1 || \
	{ echo >&2 "${arg} was not found, exiting script"; exit 1; }
	#else
	return 0
}


function printhelp
{
	echo "fMRI_process.sh -i <func_data> -a <highres_anat> -o <outdir> -h (optional) -c (optional)"
	echo "-i <func_data>: the 4-D functional flanker task data"
	echo "-a <highres_anat>: the 3-D high resolution T1 MPRAGE"
	echo "-h: displays this helpful message"
	echo "-c: clobber (overwrites the output)"
	echo "if you have any questions or comments please email james-kent@uiowa.edu"
	exit 1
}


############################################################
# Job Control Statements
############################################################
#trap (or intercept) the control+C (kill process) command
trap control_c SIGINT
trap control_c SIGTERM





############################################################
# Variable Defaults
############################################################
clob=false




############################################################
# Variable setting and checking
############################################################

#See if any arguments were passed into this script
if [ $# -eq 0 ]; then
	printhelp
fi


# INITIALIZE ARRAY #
declare -a cond_array
declare -i cond_index
cond_index=0
clob=false
while getopts "i:a:t:o:ch" OPTION; do
	case $OPTION in
		i)
			FLANKER_NIFTI=$OPTARG
			;;
		a)
			Anat=${OPTARG}
			;;
		t)
			cond_array[${cond_index}]=${OPTARG}
			cond_index=$(( ${cond_index}+1 ))
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
########################################################

echo "clobber is set to ${clob}"

#HELPER FUNCTIONS
################################################################################################################
########################################################
# Name: clobber
# Purpose: allows for commands to only be ran once, without
#		   trying to overwrite outputs each time the script
#		   is called, unless the user specifies they want 
#		   the output overwritten.
# Parameters: any number of files/objects
# Output: either a zero (true) or a one (false)
# Preconditions/Postconditions: the first file is only file 
# 				 checked so if
#    			 that file exists and clob is set to 1
#				 then all the files will be removed and the
#				 function will return 0.
#				 if clob is set to 0, then if the file exists
#				 the function will return 1. if the file
#				 doesn't exist, the function will return 0.

# function clobber()
# {
	
# 		if [ -e $1 ] && [ "${clob}" = true ]; then
# 			rm $@
# 			return 0
# 		elif [ -e $1 ] && [ "${clob}" = false ]; then
# 			return 1
# 		elif [ ! -e $1 ]; then
# 			return 0
# 		else
# 			echo "How did you get here?"
# 			return 1
# 		fi
# }
########################################################



########################################################
# Name: GetMiddleVolume
# Purpose: find and isolate the middle volume of a functional dataset
# Parameters: 
#	$1=the functional dataset
#	$2=the output directory (optional)
# Produces: a 3-D volume that represents the 
#			midpoint of the functional scan.
# Preconditions: The input functional volume must exist
#				 The function GetNumVols and GetName must be defined
#				 Depends on
#						   > GetNumVols
#						   > GetName
#						   > clobber
# Postconditions: The output file is placed in the output dir
#				  if the output dir wasn't defined, then it will
#				  be placed in the same directory as the input file.				
function GetMiddleVolume()
{	
	if [ "$2" == "" ]; then
		local outDir=$(dirname $1)
	else
		local outDir=$2
	fi

	local Total=$(GetNumVols $1)
	local Half=$(( ${Total}/2 ))
	local Name=$(GetName $1)
	Middle_Vol=${outDir}/${Name}_Middle_Volume.nii.gz

	clobber ${Middle_Vol} &&\
	fslroi $1 ${Middle_Vol} ${Half} 1 &&\
	return 0
	#else
	return 1
}
########################################################



########################################################
# Name: GetName
# Purpose:
#	gets basename of file by stripping directory and suffix information
# Parameters:
# 	$1=file with directory and/or suffix info
# Produces:
#	filename, type text
# Preconditions:
#	no preconditions
# Postconditions:
#	returns the filename without directory or suffix information
function GetName()
{
	echo $(basename "${1%%.*}")
}
########################################################



########################################################
# Name: GetNumVols
# Purpose:
#	Finds the number of volumes in a 4-D set
# Parameters:
# 	$1=4D Volume, an image file
# Produces:
#	the number of volumes
# Preconditions:
#	the input must be a 4D volume with header information
# Postconditions:
#	returns the correct number of volumes in the 4D dataset
function GetNumVols()
{
	echo $(3dinfo $1 | grep "Number of time steps" | awk -F" " '{print $6}')
}
########################################################


########################################################
# Name: GetTR
# Purpose:
#	finds the repetition time of a 4D volume
# Parameters:
# 	$1=4D Volume, an image file
# Produces:
#	the repetition time
# Preconditions:
#	the input must be a 4D volume with header information
# Postconditions:
#	returns the correct repetition time
function GetTR()
{
	echo $(3dinfo -verb $1 | grep "Time step" | awk -F" " '{print $10}' | sed 's/\..*$//')
}
########################################################



########################################################
# Name: GetDuration
# Purpose:
#	Finds how long (in seconds) the session for a 4D scan took
#	found in
#			> FindOutlierVols
# Parameters:
# 	$1=4D Volume, an image file
# Produces:
#	The session time
# Preconditions:
#	the input must be a 4D volume with header information
#	Depends on
#			  > GetNumVols
#			  > GetTR
# Postconditions:
#	returns the session time
function GetDuration()
{
	local NumVols=$(GetNumVols $1)
	local TR=$(GetTR $1)
	echo $(( ${TR}*${NumVols} ))

}
########################################################


########################################################
# Name: GetMean
# Purpose:
#	Finds the voxelwise mean of a 4D Volume
#	found in
#			 > SpatialSmooth
# Parameters:
# 	$1=4D Volume, an image file
#	$2=mask, a 3D binary image file
#	$3=outDir, a directory (optional)
# Produces:
#	the repetition time
# Preconditions:
#	the input must be a 4D volume with header information
#	Depends on
#			  > clobber
#			  > GetName
# Postconditions:
#	returns the correct repetition times
function GetMean()
{	

	if [ "$3" == "" ]; then
		local outDir=$(dirname $1)
	else
		local outDir=$3
	fi

	local Name=$(GetName $1)
	local mask=$2
	mean_func=${outDir}/${Name}_mean_func.nii.gz
	clobber ${mean_func} &&\
	3dmerge -prefix ${mean_func} -doall -gmean $1 1>/dev/null
	fslstats ${mean_func} -k ${mask} -p 50 &&\
	return 0
	#else
	return 1
}
########################################################



########################################################
# Name: BiasCorrect
# Purpose:
#	Corrects for in field inhomogeneities
#	Makes the image better for skull stripping
#	found in
#			> SkullStrip
# Parameters:
# 	$1=high resolution anatomical scan, a 3D Volume
#	$2=outDir, a directory (optional)
# Produces:
#	bias_correct_image, A 3D Volume
# Preconditions:
#	the input must be a 3D anatomical Volume
#	must have access to ANTS commands defined in path
#	Depends on
#			  > GetName
#			  > clobber
# Postconditions:
#	returns bias corrected image
function BiasCorrect()
{
	if [ "$2" == "" ]; then
		local outDir=$(dirname $1)
	else
		local outDir=$2
	fi

	local Name=$(GetName $1)
	biasCorrectName=${outDir}/${Name}_bc.nii.gz

	clobber ${biasCorrectName} &&\
	N4BiasFieldCorrection -d 3 -i $1 -o ${Name}_bc.nii.gz &&\
	return 0
	#else
	return 1
}
########################################################



########################################################
# Name: SkullStrip
# Purpose:
#	Removes skull from T1 image using a bayesian corrected
#	average of different skull stripping algorithms
#	found in
#			> Registration_epi2std
# Parameters:
# 	$1=high resolution anatomical scan, a 3D Volume
#	$2=outDir, a directory (optional)
# Produces:
#	T1_mask, a binary 3D Volume
#   T1_brain, a masked T1 Volume
# Preconditions:
#	the input must be a 3D anatomical Volume
#	must have access to ANTS commands defined in path
#	Depends on
#			  > BiasCorrect
#			  > GetName
#			  > clobber
# Postconditions:
#	returns the mask and a skull stripped brain
function SkullStrip()
{
	if [ "$2" == "" ]; then
		local outDir=$(dirname $1)
	else
		local outDir=$2
	fi

	local Name=$(GetName $1)
	biasCorrectName=${outDir}/${Name}_bc.nii.gz
	T1_mask=${outDir}/${Name}_bc_mask_60_smooth.nii.gz
	T1_brain=${outDir}/${Name}_ss.nii.gz
	
	clobber ${biasCorrectName} &&\
	BiasCorrect $1 ${outDir}
	clobber ${T1_brain} &&\
	MBA.sh -s ${biasCorrectName} -o ${outDir} -b /Volumes/VossLab/Repositories/MBA_maps/brainPrior/Ave_brain.nii.gz -a /Volumes/VossLab/Repositories/MBA_maps &&\
	3dcalc -a $1 -b ${T1_mask} -expr 'a*b' -prefix ${T1_brain} &&\
	return 0
	#else
	return 1
}
########################################################

#FUNCTIONS CALLED IN THE MAIN SCRIPT
################################################################################################################

########################################################
# Name: FindOutlierVols
# Purpose:
#	Goes through each 3D image in a 4D Volume to find images with 
#	a significant amount of voxels that are outliers
#	See http://afni.nimh.nih.gov/pub/dist/doc/program_help/3dToutcount.html for how outliers are defined
# Parameters:
# 	$1=functional scan, 4D Volume
# Produces:
#	% of voxels that over 2 standard deviations away from the mean for each volume
# Preconditions:
#	4D volume must exist.
#	Depends on
#			  > GetDuration
# Postconditions:
#	no further postconditions
function FindOutlierVols()
{
	local Duration=$(GetDuration $1)
	local auto_polort=$(( 1+(${Duration}/150) ))
	3dToutcount -automask -fraction -polort ${auto_polort} -legendre $1 &&\
	return 0
	#else
	return 1
}
########################################################



########################################################
# Name: MotionCorrection
# Purpose:
#	Corrects motion artefacts due to (hopefully) subtle head movements over time. 
# Parameters:
# 	$1=functional scan, 4D Volume
#	$2=outDir, output directory (optional)
# Produces:
#	Motion parameters for translations and rotations in the x,y,z, planes
#	mcName, the motion corrected 4D functional volume
# Preconditions:
#	4D volume must exist.
#	Depends on
#			  > GetName
#			  > GetMiddleVolume
#			  > clobber
# Postconditions:
#	no further postconditions
function MotionCorrection()
{
	if [ "$2" == "" ]; then
		local outDir=$(dirname $1)
	else
		local outDir=$2
	fi

	local Name=$(GetName $1)
	mcName=${outDir}/${Name}_mc.nii.gz

	GetMiddleVolume $1 ${outDir} &&\
	clobber ${mcName} &&\
	3dvolreg -prefix ${mcName} -Fourier -zpad 4 -base ${outDir}/${Name}_Middle_Volume.nii.gz -dfile ${outDir}/${Name}_motion_file.txt $1 &&\
	return 0
	#else
	return 1
}
########################################################



########################################################
# Name: MakeMask
# Purpose:
#	 mask the 4D functional dataset to remove non-brain materials
#	 from statistical analysis
# Parameters:
# 	$1=functional scan, 4D Volume
#	$2=outDir, output directory (optional)
# Produces:
#	Motion parameters for translations and rotations in the x,y,z, planes
#	mcName, the motion corrected 4D functional volume
# Preconditions:
#	4D volume must exist.
#	Depends on
#			  > GetName
#			  > GetMiddleVolume
#			  > clobber
# Postconditions:
#	no further postconditions
function MakeMask()
{
	if [ "$2" == "" ]; then
		local outDir=$(dirname $1)
	else
		local outDir=$2
	fi

	local Name=$(GetName $1)
	mask=${outDir}/${Name}_mask.nii.gz
	masked_mc=${outDir}/${Name}_masked.nii.gz

	clobber ${mask} &&\
	3dAutomask -dilate 1 -prefix ${mask} $1 &&\
	3dcalc -a $1 -b ${mask} -expr 'a*b' -prefix ${masked_mc} &&\
	return 0
	#else
	return 1
}
########################################################



########################################################
# Name: HighPassFilter
# Purpose:
#	 Remove the slow trends in the data which aren't
#	 signals of interest.
# Parameters:
# 	$1=functional scan, 4D Volume (motion corrected)
#	$2=mask, a binary 3D volume
#	$3=outDir, output directory (optional)
# Produces:
#	A 4D functional data set with slow trends removed
# Preconditions:
#	4D volume must exist.
#	Depends on
#			  > GetName
#			  > clobber
# Postconditions:
#	no further postconditions
function HighPassFilter_AFNI()
{
	#reason to do filtering: http://mindhive.mit.edu/node/116
	if [ "$3" == "" ]; then
		local outDir=$(dirname $1)
	else
		local outDir=$3
	fi

	local Name=$(GetName $1)
	hpfName=${outDir}/${Name}_hpf.nii.gz

	#Adding the mean back in:
	#http://afni.nimh.nih.gov/afni/community/board/read.php?1,84353,84356#msg-84356
	clobber ${hpfName} &&\
	3dBandpass -prefix ${outDir}/tmp_bp.nii.gz -mask $2  0.01  99999 $1 &&\
	3dTstat -mean -prefix ${outDir}/orig_mean.nii.gz $1 &&\
	3dTstat -mean -prefix ${outDir}/bp_mean.nii.gz ${outDir}/tmp_bp.nii.gz &&\
	3dcalc -a ${outDir}/tmp_bp.nii.gz -b ${outDir}/orig_mean.nii.gz -c ${outDir}/bp_mean.nii.gz -expr "a+b-c" -prefix ${hpfName} &&\
	return 0
	#else
	return 1
}
function HighPassFilter_FSL()
{
	if [ "$3" == "" ]; then
		local outDir=$(dirname $1)
	else
		local outDir=$3
	fi

	local Name=$(GetName $1)
	hpfName=${outDir}/${Name}_hpf.nii.gz

	clobber ${hpfName} &&\
	fslmaths $1 -bptf 25.0 -1 ${hpfName} &&\
	return 0
	#else
	return 1
}
########################################################


#######################################################
# Name: SpatialSmooth
# Purpose:
#	 Smooth the data to average out noise and boost signal
#	 Also may help in group analysis since structure/function
#	 relationships vary between individuals
# Parameters:
# 	$1=functional scan, 4D Volume (motion corrected)
#	$2=mask, a binary 3D volume
#	$3=outDir, output directory (optional)
# Produces:
#	A 4D functional data set with slow trends removed
# Preconditions:
#	4D volume must exist.
#	Depends on
#			  > GetName
#			  > clobber
# Postconditions:
#	no further postconditions
function SpatialSmooth()
{
	if [ "$3" == "" ]; then
		local outDir=$(dirname $1)
	else
		local outDir=$3
	fi

	local Name=$(GetName $1)
	local mask=$2

	mean_func=${outDir}/${Name}_mean_func.nii.gz
	smoothName=${outDir}/${Name}_smooth.nii.gz
	clobber ${mean_func} &&\
	GetMean $1 $2 $3
	mean=$(GetMean $1 $2 $3)
	echo "mean=${mean}"
	local brightness_threshold=$(echo "${mean}*0.75" | bc)
	 #can't reference variable from other function?
	
	clobber ${smoothName} &&\
	susan $1 ${brightness_threshold} 2.5 3 1 1 ${mean_func} ${brightness_threshold} ${smoothName} &&\
	return 0
	#else
	return 1
}



#######################################################
# Name: Scale
# Purpose:
#	Temporally scales each voxel to have a mean of 100 across the
#	timeseries. range [0,200]
# Parameters:
# 	$1=functional scan, 4D Volume (motion corrected,masked,spatially smoothed)
#	$2=mean_func, 3D image
#	$3=outDir, output directory (optional)
# Produces:
#	scaleName, a 4D Volume
# Preconditions:
#	4D volume must exist.
#	Depends on
#			  > GetName
#			  > clobber
# Postconditions:
#	no further postconditions

#NOT NEEDED
function Scale()
{
	if [ "$3" == "" ]; then
		local outDir=$(dirname $1)
	else
		local outDir=$3
	fi

	local Name=$(GetName $1)
	local mean_func=$2
	scaleName=${outDir}/${Name}_scaled.nii.gz

	clobber ${scaleName} &&\
	3dcalc -a $1 -b ${mean_func} -expr 'min(200, a/b*100)*step(a)*step(b)'  -prefix ${scaleName} &&\
	return 0
	#else
	return 1
}
#######################################################


#######################################################
# Name: Registration_epi2std
# Purpose:
#	Registers the epi data to standard space for group analysis
# Parameters:
# 	$1=functional scan, 4D Volume (motion corrected,masked,spatially smoothed)
#	$2=anatomical scan, a 3D image
#	$3=outDir, output directory (optional)
# Produces:
#	affine matrices and warps to move from subject space to standard space
# Preconditions:
#	4D volume must exist.
#	Depends on
#			  > GetName
#			  > clobber
# Postconditions:
#	no further postconditions
function Registration_epi2std()
{	
	if [ "$3" == "" ]; then
		local outDir=$(dirname $1)
	else
		local outDir=$3
	fi
	local Name=$(GetName $1)
	T1_mask=${outDir}/${Name}_bc_mask_60_smooth.nii.gz
	T1_brain=${outDir}/${Name}_ss.nii.gz
	

	cd ${outDir} &&\
	clobber ${T1_brain} &&\
	SkullStrip $2 ${outDir}

	clobber highres &&\
	fslmaths ${T1_brain} highres

	clobber example_func.nii.gz &&\
	fslmaths $1 example_func

	clobber highres_head.nii.gz &&\
	fslmaths $2 highres_head

	clobber standard standard_head standard_mask &&\
	fslmaths ${FSLDIR}/data/standard/MNI152_T1_2mm_brain standard &&\
	fslmaths ${FSLDIR}/data/standard/MNI152_T1_2mm standard_head &&\
	fslmaths ${FSLDIR}/data/standard/MNI152_T1_2mm_brain_mask_dil standard_mask

	clobber example_func2highres* &&\
	epi_reg --epi=example_func --t1=highres_head --t1brain=highres --out=example_func2highres &&\
	convert_xfm -inverse -omat highres2example_func.mat example_func2highres.mat

	clobber highres2standard* &&\
	flirt -in highres -ref standard -out highres2standard -omat highres2standard.mat -cost corratio -dof 12 -searchrx -90 90 -searchry -90 90 -searchrz -90 90 -interp trilinear &&\
	fnirt --iout=highres2standard_head --in=highres_head --aff=highres2standard.mat --cout=highres2standard_warp --iout=highres2standard --jout=highres2highres_jac --config=T1_2_MNI152_2mm --ref=standard_head --refmask=standard_mask --warpres=10,10,10 &&\
	applywarp -i highres -r standard -o highres2standard -w highres2standard_warp &&\
	convert_xfm -inverse -omat standard2highres.mat highres2standard.mat &&\
	convert_xfm -omat example_func2standard.mat -concat highres2standard.mat example_func2highres.mat &&\
	convertwarp --ref=standard --premat=example_func2highres.mat --warp1=highres2standard_warp --out=example_func2standard_warp &&\
	applywarp --ref=standard --in=example_func --out=example_func2standard --warp=example_func2standard_warp &&\
	convert_xfm -inverse -omat standard2example_func.mat example_func2standard.mat &&\
	cd - &&\
	return 0

	#else
	return 1
	#use 3dQwarp to move from anat to MNI
	#use epi_reg to get from epi to anat
	#apply transforms?
}
function fsl_glm() {

	filtered_func=$1

	fslmaths ${filtered_func} -nan -mul 1000 ${filtered_func}
	min_val=$(fslstats ${filtered_func} -R | awk {print $1})

	film_gls -rn stats -sa -ms 5 

}
function Program_check() {
	command_check=$(which "${1}")
	if [ "${command_check}" == "" ]; then
		echo "${1} is either not downloaded or not defined in your $PATH variable, please make the necessary changes and restart the script"
		exit 1
	fi
	return 0
}
###
# END FUNCTIONS
###

#MAIN SCRIPT
################################################################################################################
#check to make sure all necessary commands are accessible
#Can't run the script if these don't work
Program_check fsl
Program_check afni
Program_check MBA.sh
Program_check N4BiasFieldCorrection


if [ "${outDir}" == "" ]; then
	outDir=$(pwd)
else
	mkdir -p ${outDir}
fi

#variables that must be defined/initialized
#mask=${outDir}/mask/${mcName} ${Name}_mask.nii.gz


#strip the directory and file extension information from the file
FLANKER_NAME=$(GetName ${FLANKER_NIFTI})

#making directory for intermediate files and other directories for results.
mkdir -p ${outDir}/{smoothed,stats,mc,reg,logs,mask,hpf,scaled}
#cp ${cond_array[@]} ${outDir}/${FLANKER_NAME}_intermediate_files && cond_index=0 && for cond in ${cond_array[@]}; do cond_array[${cond_index}]=$(basename ${cond}); cond_index=$((${cond_index}+1)); done
cd ${outDir} #work from this directory




echo "Starting Analysis"
clobber ./logs/outlier_test.txt &&\
touch ./logs/outlier_test.txt &&\
FindOutlierVols ${FLANKER_NIFTI} > ./logs/outlier_test.txt


echo "Starting Motion Correction"
FLANKER_MOTION_DIR=$(dirname ${FLANKER_NIFTI} | sed 's|$|/motion|')
echo "Going to copy from ${FLANKER_MOTION_DIR}"
#Not going to run 3dVolreg again since reconstruction.sh takes care of it
mcName=${outDir}/mc/${FLANKER_NAME}_mc.nii.gz &&\
clobber ${mcName} &&\
cp ${FLANKER_MOTION_DIR}/* ${outDir}/mc/ &&\
cp ${outDir}/mc/mcImg.par ${outDir}/mc/prefiltered_func_data_mcf.par &&\
cp ${outDir}/mc/mcImg.nii.gz ${outDir}/mc/${FLANKER_NAME}_mc.nii.gz

#Still may need the middle volume
GetMiddleVolume ${outDir}/mc/${FLANKER_NAME}_mc.nii.gz ${outDir}/mc/
#MotionCorrection ${FLANKER_NIFTI} ${outDir}/mc 


echo "Starting to make mask for epi data"
MakeMask ${mcName} ${outDir}/mask
#Moving mask to main directory for FSL
cp ${mask} ${outDir}/mask.nii.gz

echo "Starting Spatial Smoothing"
SpatialSmooth ${masked_mc} ${mask} ${outDir}/smoothed


echo "Starting Highpass Filtering"
HighPassFilter_FSL ${smoothName} ${mask} ${outDir}/hpf
#FSL Preprocessing (intnorm) see featlib.tcl
clobber ${outDir}/filtered_func_data.nii.gz &&\
normmean=10000 &&\
median_intensity=$(fslstats ${mcName} -k ${mask} -p 50) &&\
scaling=$(echo "scale=16; ${normmean}/${median_intensity}" | bc) &&\
fslmaths ${hpfName} -mul ${scaling} ${outDir}/filtered_func_data.nii.gz


#Not necessary since voxel are now gaurenteed to be above zero in highpass filtering
#echo "Scaling Voxel Time Series"
#Scale ${hpfName} ${mean_func} ${outDir}/scaled
#For fsl processing
#cp ${scaleName} ${outDir}/filtered_func_data.nii.gz
#fslmaths ${outDir}/filtered_func_data.nii.gz -add ${mask} -mul 1000 filtered_func_data.nii.gz

echo "registering the epi data to standard space"
Registration_epi2std ${Middle_Vol} ${Anat} ${outDir}/reg



echo "Finished Processing"



###############################################
# ANALYSIS STEPS NOT IMPLEMENTED
###############################################
# Slice Timing Correction
# Normalizing each 3D volume in the 4D file
