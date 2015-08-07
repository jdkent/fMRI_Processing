#!/bin/bash -x

function printHelp() {
	echo "Usage: fsf_renaming.sh -f <filteredFunc> -t <TimingDir> -d <DesignFile> -s <SubNum> -o <outDir>"
	echo "filteredFunc:			the preprocessed 4D image"
	echo "TimingDir:			the directory where the timing onsets are defined"
	echo "DesignFile:			the template design file (.fsf) being used"
	echo "SubNum:				the subject number"
	echo "outDir:				the name of the output directory"
	exit 1
}

while getopts "f:t:d:s:o:h" OPTION; do
	case $OPTION in
		f)
			FilteredFunc=${OPTARG}
			;;
		t)
			TimingDir=${OPTARG}
			;;
		d)
			DesignFile=${OPTARG}
			;;
		s)
			SubNum=${OPTARG}
			;;
		o)
			outDir=${OPTARG}
			;;
		h)
			printHelp
			;;
		*)
			printHelp
			;;
	esac
done


sed \
-e "s|TEMPLATE_DATA|${FilteredFunc}|" \
-e "s|CON_EV|${TimingDir}/s${SubNum}_con_fixdur.txt|" \
-e "s|INC_EV|${TimingDir}/s${SubNum}_inc_fixdur.txt|" \
-e "s|NEU_EV|${TimingDir}/s${SubNum}_neu_fixdur.txt|" \
-e "s|ERR_EV|${TimingDir}/s${SubNum}_errors_fixdur.txt|" \
-e "s|OUTPUT_DIRECTORY|${outDir}|" \
${DesignFile} > sub${SubNum}_design.fsf

