#!/bin/bash
while getopts "f:t:d:s:o:" OPTION; do
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
			echo "this is help (uninitialized)"
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

