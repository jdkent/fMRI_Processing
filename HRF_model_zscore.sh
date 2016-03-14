#!/usr/bin/env bash

############################################################
# Bash Settings
############################################################
#These are settings to help a script run "cleanly"
#set -o errexit #exits script when a command fails (not compatable with clobber)
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
#	the repetition time, an integer
# Preconditions:
#	the input must be a 4D volume with header information
# Postconditions:
#	returns the correct repetition time (if its an integer)
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

function standard_deviation()
{
	local -a num_array
	num_array=($(cat $1))

	#using this as a global variable so I don't have to recalculate and have it available outside this function
	mean=$(awk '{sum += $1; n++} END { if (n > 0) print sum / n; }' < $1)
	local sum_of_squares=0
	for number in ${num_array[@]}; do
		sum_of_squares=$(echo "${sum_of_squares} + (${mean} - ${number})^2" | bc -l)
	done

	local stdev
	stdev=$(echo "sqrt(${sum_of_squares}/${#num_array[@]})" | bc -l)
	echo ${stdev}
	return 0


}
function control_c 
{
	echo -e "\n## Caught SIGINT: Cleaning up before exit"
	rm ${file_tracker[@]}
	#What is this rm command doing? Is it a good feature?
	exit $?
	#Q: Does the dollar sign '$' do something else beside signal variables?
	#A: Yes, it often also has the meaning 'last', so in this instance
	#	it means exit with the status of the last command (either a 0 or 1)
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
#Q: What is up with '>', '<', '&', and those numbers I see up there?
#A: This brings up a very important, if not confusing concept about redirection.
#	First I will cover what the numbers mean since we need to know the types of output we can have
#	0: stdin, what you (the user) inputs into the terminal prompt
#	1: stdout, what the commands that are ran in the terminal send their standard output to
#	2: stderr, if the command fails, then they will send the error message here
#	When we work on the terminal, stdout and stderr look the same since they are both directed
#	to terminal output, but they can be treated differently with stout going to one place
#	and stderr going to another.
#	Now the '>' symbol takes a commands output ('stdout' unless otherwise specified) and places it somewhere else.
#	This other place can be another file or even one of the other types of output as we see above.
#	the symbools '2>&1' say redirect stderr to stdout, so that where ever stdout goes, stderr follows.
#	We have to use the ampersand before 1 in order to tell bash this refers to stdout instead of a file named '1'
#	However, the argument immediately left of the '>' symbol are always interpreted to be one of the three outputs
#	the redirection before that '> /dev/null' takes advantage of the special properties of the file, /dev/null
#	/dev/null is the equivalent of a trash can or a black hole where you send output that you don't ever want to see.
#	When we put it all together, we see the command's stout and stderr are being redirected to the trash can /dev/null.
#Q: What is the || symbol doing?
#A:	The logical operator || means only one of the statements has to be true for the entire statement to be true.
#	The list of commands enclosed in brackets will always execute successfully, resulting in the script exiting.
#	However, if the first command 'command -v "${arg}"', executes successfully, the second command in curly brackets
#	is not executed or even looked at. This is because of the nature of the logical OR. Once one true statement (command) is found,
#	there is no use in evaluating the other statement since we know the outcome of the statement to be true.
#	To write it out in symbols lets say we have two commands, P and Q. we don't know whether they are true or not.
#	P=? and Q=?. Now look at the truth table for logical OR '||'
#	P || Q # Outcome
#	T    T    T
#   T    F    T
#	F    T    T
#   F    F    F
#	The only time the statement is false is when P and Q are false, so as soon as we know one is true, the statement has to be true



function printhelp
{
	echo "HRF_model.sh -i <filtered_func_data> -t <timing_file> -m <mask> -l <lower_bound> -u <upper_bound> -h (optional) -c (optional)"
	echo "-i <filtered_func_data>: preprocessed 4d functional image"
	echo "-t <timing_file>: The times the condition occured (single column, each time gets it's own line)"
	echo "-l <lower_bound>: The number of volumes before the stimulus you want to observe"
	echo "-u <upper_bound>: The number of volumes after the stimulus you want to observe"
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
while getopts "i:t:m:l:u:hc" OPTION; do
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
		l)
			volumes_before_stim="${OPTARG}"
			;;
		u)
			volumes_after_stim="${OPTARG}"
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

 command_check afni
 



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
for tim in $(cat "${timing_file}" | awk '{print $1}'); do
	volume_num=$(echo "${tim}/${TR}" | bc) &&\
	volume_index=$(( ${volume_index} + 1 )) &&\
	volume_array[${volume_index}]=${volume_num}
#Q: Why is there a '\' after the logical AND symbol '&&'?
#A: This is the opposite of the semicolon ';' which tells bash to treat any characters after the semicolon
#	as though they had their own line. The backslash tells bash to treat the next line as the same line.
#	Since && takes two arguments, they have to be on the same line, but it doesn't look aesthetically pleasing
#	for a bunch of commmands to be right after each other, so the backlash allows the code to look better.
#Ex: Why would anyone want to use the && in there code? What happens if one of the commands fail?
	lower_bound=$(( ${volume_num} - ${volumes_before_stim} ))
	upper_bound=$(( ${volume_num} + ${volumes_after_stim} ))


	if [ ${lower_bound} -lt 0 ]; then
		lower_bound=0
	fi

	if [ ${upper_bound} -gt ${Total_Volumes} ]; then
		upper_bound=${Total_Volumes}
	fi

	file_tracker[${file_index}]=HRz_${volume_num}.txt
	file_index=$(( ${file_index} + 1 ))
	#get the raw data values
	clobber HRz_${volume_num}.txt &&\
	for volume in $(seq ${lower_bound} ${upper_bound}); do
		value=$(3dmaskave -mask ${mask} -quiet ${filtered_func_data}[${volume}])
		echo ${value} >> HRz_${volume_num}.txt
	done
	#Q: How is >> different from >?
	#A: >> appends the output to a file, so that you can use it multiple times on the same file
	#	and the output won't be overwritten, but > will overwrite whatever is in the file each time
	#	it is called.
	#keep track of all files in case user hits control+c and for file management
	

	#Normalize the data
	#max=$(find_max HR_${volume_num}.txt)
	#min=$(find_min HR_${volume_num}.txt)
	stdev=$(standard_deviation HRz_${volume_num}.txt)

	file_tracker[${file_index}]=HRz_${volume_num}_norm.txt
	file_index=$(( ${file_index} + 1 ))
	mean=$(awk '{sum += $1; n++} END { if (n > 0) print sum / n; }' < HRz_${volume_num}.txt)
	declare -i temp_index=1
	clobber HRz_${volume_num}_norm.txt &&\
	for num in $(cat HRz_${volume_num}.txt); do
		norm_num=$(echo "((${num}-${mean})/${stdev})" | bc -l)
		echo ${norm_num} >> HRz_${volume_num}_norm.txt
		temp_index=$(( ${temp_index} + 1 ))
	done
	#again to keep track of files
	

	#Zero the data on the onset
	#clobber HR_${volume_num}_zero.txt &&\
	#for num in $(cat HR_${volume_num}_norm.txt); do
	#	echo "${num}-${zero_point}" | bc >> HRz_${volume_num}_zero.txt
	#done
	#still keeping track of files
	#file_tracker[${file_index}]=HRz_${volume_num}_zero.txt
	#file_index=$(( ${file_index} + 1 ))


done
#visualization
paste HRz_*norm.txt > all_HRz_norm.txt
mkdir -p ./HRz_files
mv ${file_tracker[@]} ./HRz_files
awk '{sum=0; for(i=1; i<=NF; i++){sum+=$i}; sum/=NF; print sum}' all_HRz_norm.txt > ave_HRz_norm.txt &&\
1dplot ave_HRz_norm.txt &
#Q: What does the single ampersand '&' do?
#A: runs the command in the background so you can run other commands from the terminal while
#	this one is still running

#If you saw the previous script on the voss wiki, then you should now have seen awk, grep, and sed in action.
#These are three commonly used utilities to filter text/data.
#Here is a description of what each of them can be used for:
#sed: renaming files
#grep: filtering lists, finding specific output
#awk: intelligently filter and manipulate lists and tables (like in excel files)
