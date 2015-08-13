#!/usr/bin/env bash

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
function find_min()
{
	local -a num_array
	num_array=($(cat $1))
	local current_min=${num_array[0]}

	local num
	for num in ${num_array[@]:1}; do
		local -i comp=$(echo "${current_min}<${num}" | bc)
		if [ ${comp} -eq 0 ]; then
			current_min=${num}
		fi
	done
	echo ${current_min}
}

function find_max()
{
	local -a num_array
	num_array=($(cat $1))
	local current_max=${num_array[0]}

	local num
	for num in ${num_array[@]:1}; do
		local -i comp=$(echo "${current_max}>${num}" | bc)
		if [ ${comp} -eq 0 ]; then
			current_max=${num}
		fi
	done
	echo ${current_max}
}

function control_c 
{
	echo -e "\n## Caught SIGINT: Cleaning up before exit"
	rm ${file_tracker[@]}
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

	#see if command should be run
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
	echo "HRF_model.sh -i <filtered_func_data> -t <timing_file> -m <mask> -h (optional) -c (optional)"
	echo "-i <filtered_func_data>: preprocessed 4d functional image"
	echo "-t <timing_file>: The times the condition occured (single column, each time gets it's own line)"
	echo "-h: displays this helpful message"
	echo "-c: clobber (overwrites the output)"
	echo "if you have any questions or comments please email james-kent@uiowa.edu"
	exit 1
}


############################################################
# Job Control Statements
############################################################
#trap (or intercept) the control+C command
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


#Set the inputs we are looking
while getopts "i:t:m:hc" OPTION; do
	case $OPTION in
		i)
			filtered_func_data="${OPTARG}"
			;;
		t)
			timing_file="${OPTARG}"
			;;
		m)
			mask="${OPTARG}"
			;;
		h)
			printhelp
			;;
		c)
			clob=true
			;;
		*)
			printhelp
			;;
	esac
done


if [ -z "${filtered_func_data}" ]; then
	echo "-i <filtered_func_data> is unset, printing help and exiting"
	printhelp
fi

if [ -z "${timing_file}" ]; then
	echo "-t <timing_file> is unset, printing help and exiting"
	printhelp
fi

############################################################
# Program/command Checking
############################################################
#These are commands that are necessary to run the script

#should use for specialized packages (like fsl or afni)
#normally don't need to check basic commands like these
 command_check afni
 command_check fsl



############################################################
# main()
############################################################
TR=$(GetTR ${filtered_func_data})
Total_Volumes=$(GetNumVols ${filtered_func_data})
#window of interest: one volume before and ten volumes after (2 seconds before to 20 seconds after)
#Convert timing file to volumes
declare -a file_tracker
declare -i file_index
declare -a volume_array
declare -i volume_index=-1
declare -i volume_num
for tim in $(cat "${timing_file}"); do
	volume_num=$(echo "${tim}/${TR}" | bc) &&\
	volume_index=$(( ${volume_index} + 1 )) &&\
	volume_array[${volume_index}]=${volume_num}

	lower_bound=$(( ${volume_num} - 1 ))
	upper_bound=$(( ${volume_num} + 10 ))

	if [ ${lower_bound} -lt 0 ]; then
		lower_bound=0
	fi

	if [ ${upper_bound} -gt ${Total_Volumes} ]; then
		upper_bound=${Total_Volumes}
	fi

	#get the raw data
	clobber HR_${volume_num}.txt &&\
	for volume in $(seq ${lower_bound} ${upper_bound}); do
		value=$(3dmaskave -mask ${mask} -quiet ${filtered_func_data}[${volume}])
		echo ${value} >> HR_${volume_num}.txt
	done
	file_tracker[${file_index}]=HR_${volume_num}.txt
	file_index=$(( ${file_index} + 1 ))

	#Normalize the data
	max=$(find_max HR_${volume_num}.txt)
	min=$(find_min HR_${volume_num}.txt)

	declare -i temp_index=1
	clobber HR_${volume_num}_norm.txt &&\
	for num in $(cat HR_${volume_num}.txt); do
		norm_num=$(echo "(${num}-${min})/(${max}-${min})" | bc -l)
		if [ ${temp_index} -eq 2 ]; then
			zero_point=${norm_num}
		fi
		echo ${norm_num} >> HR_${volume_num}_norm.txt
		temp_index=$(( ${temp_index} + 1 ))
	done
	file_tracker[${file_index}]=HR_${volume_num}_norm.txt
	file_index=$(( ${file_index} + 1 ))

	#Zero the data on the onset
	clobber HR_${volume_num}_zero.txt &&\
	for num in $(cat HR_${volume_num}_norm.txt); do
		echo "${num}-${zero_point}" | bc >> HR_${volume_num}_zero.txt
	done
	file_tracker[${file_index}]=HR_${volume_num}_zero.txt
	file_index=$(( ${file_index} + 1 ))


done
#visualization
paste HR_*zero.txt > all_HR_zero.txt
mkdir -p ./HR_files
mv ${file_tracker[@]} ./HR_files
awk '{sum=0; for(i=1; i<=NF; i++){sum+=$i}; sum/=NF; print sum}' all_HR_zero.txt > ave_HR_zero.txt &&\
1dplot ave_HR_zero.txt &


