#! /bin/bash

# This script aims for automatically converting a video into another one. Its is
# primarily implemented with the aim for compressing big videos into smaller
# ones. It uses HandBrake for the conversion of video and audio, and MKVMerge to
# put everything together.

###########
# OPTIONS #
###########

input_opt='input'
input_opt_short='i'
input_dir_opt='input-dir'
input_dir_opt_short='id'
output_dir_opt='output-dir'
output_dir_opt_short='od'
recursive_opt='recursive'
recursive_opt_short='r'
handbrake_preset_opt='handbrake-preset'
handbrake_preset_opt_short='hp'
help_opt='help'
help_opt_short='h'

###############
# ERROR CODES #
###############

err_unknown_option=64
err_no_input=65
err_no_output_dir=66
err_conflicting_inputs=67
err_recursive_file=68

##################
# DEFAULT VALUES #
##################

output_dir="."
temp_dir=$(mktemp -d "${TMPDIR:-/tmp/}$(basename "$0").XXXXXXXXXXXX")
video_audio_file="$temp_dir/conversion.mkv"
handbrake_preset="Very Fast 480p30"
#handbrake_preset="Anime (custom)" # TODO remove

#########
# USAGE #
#########

display_default() {
	echo "[Default: $1]"
}

display_usage() {
	local cmd
	cmd=$(basename "$0")
	cat <<EOF
Usage:
	$cmd --$help_opt
	$cmd --$input_opt=<file> [--$output_dir_opt=<dir>] [--$handbrake_preset_opt=<preset>]
	$cmd --$input_dir_opt=<dir> [--$recursive_opt] [--$output_dir_opt=<dir>] [--$handbrake_preset_opt=<preset>]
Options:
	--$input_opt, -$input_opt_short
		Video to convert. You cannot give an input folder (--$input_dir_opt) at the same time.
	--$input_dir_opt, -$input_dir_opt_short
		Folder in which the videos to convert are stored. All the videos contained in this directory will be converted. You cannot give an input file (--$input_opt) at the same time.
	--$output_dir_opt, -$output_dir_opt_short
		Folder in which the conversion will be stored. The converted files will have the same name than their original file.
		$(display_default "$output_dir")
	--$recursive_opt, -$recursive_opt_short
		Tells whether the input folder (--$input_dir_opt) should be converted recursively on all its sub-folders.
		$(display_default "false")
	--$handbrake_preset_opt, -$handbrake_preset_opt_short
		HandBrake preset to use for conversion.
		$(display_default "$handbrake_preset")
	--$help_opt, -$help_opt_short
		Display this usage page.
Errors:
	$err_unknown_option	Unknown option.
	$err_no_input	Missing input.
	$err_no_output_dir	Missing output folder.
	$err_conflicting_inputs	Both file and folder inputs are given.
	$err_recursive_file	Recursive option used on file input.
EOF
}

###########
# OPTIONS #
###########

for arg in "$@"; do
case $arg in
	--$input_opt=*|-$input_opt_short=*)
		input="${arg#*=}"
		shift
		;;
	--$input_dir_opt=*|-$input_dir_opt_short=*)
		input_dir="${arg#*=}"
		shift
		;;
	--$output_dir_opt=*|-$output_dir_opt_short=*)
		output_dir="${arg#*=}"
		shift
		;;
	--$handbrake_preset_opt=*|-$handbrake_preset_opt_short=*)
		handbrake_preset="${arg#*=}"
		shift
		;;
	--$recursive_opt|-$recursive_opt_short)
		recursive="true"
		shift
		;;
	--$help_opt|-$help_opt_short)
		display_usage
		exit 0
		;;
	*)
		>&2 echo "Unknown option $arg"
		>&2 display_usage
		exit $err_unknown_option
esac
done

if [[ "$input" == "" &&  "$input_dir" == "" ]];then
	>&2 echo "No input given for conversion, add --$input_opt or  --$input_dir_opt"
	>&2 display_usage
	exit $err_no_input
elif [[ "$input" != "" &&  "$input_dir" != "" ]];then
	>&2 echo "Bot inputs are given for conversion, choose only --$input_opt or  --$input_dir_opt"
	>&2 display_usage
	exit $err_conflicting_inputs
elif [[ "$input" != "" &&  "$recursive" != "" ]];then
	>&2 echo "Recursivity cannot apply to single file, use --$input_dir_opt or remove recursivity"
	>&2 display_usage
	exit $err_recursive_file
elif [ "$output_dir" = "" ];then
	>&2 echo "No output folder given for conversion, add --$output_dir_opt"
	>&2 display_usage
	exit $err_no_output_dir
fi

#####################
# UTILITY FUNCTIONS #
#####################

count_audio_tracks() {
	local source="$1"
	mkvmerge -i "$source" | grep -c "audio"
}

get_audio_track_ID() {
	local source="$1"
	local filter="$2"
	mkvmerge -i "$source" | grep "audio" | grep "$filter" | awk -F: '{print $1}' | awk '{print $NF}'
}

build_audio_filter() {
	local id
	if [[ $(count_audio_tracks "$video_audio_file") -ge 2 ]]; then
		id=$(get_audio_track_ID "$video_audio_file" "AAC")
		echo "-a $id"
	else
		echo ""
	fi
}

extract_handbrake_progress() {
	local file="$1"
	local line
	local percent
	local eta
	
	line=$(tr '\r' '\n' < "$file" | grep -E "^Encoding" | tail -1)
	
	percent=$(echo "$line" | awk '{print $6}')
	if [[ "$percent" = "" ]]; then
		percent="0"
	fi
	
	eta=$(echo "$line" | awk '{print $14}')
	if [[ "$eta" = "" ]]; then
		eta="-"
	fi
	
	echo "$percent% - ETA $eta"
}

extract_mkvmerge_progress() {
	local file="$1"
	local line
	local percent
	
	line=$(tr '\r' '\n' < "$file" | grep -E "^Progression" | tail -1)
	
	percent=$(echo "$line" | awk '{print $3}')
	if [[ "$percent" = "" ]]; then
		percent="0%"
	fi
	
	echo "$percent"
}

########################
# PROCESSING FUNCTIONS #
########################

clean_message() {
	echo -e -n "$(echo "$1" | tr -c ' ' ' ')\r"
}

convert_video_and_audio() {
	local source="$1"
	local target="$2"
	local preset="$3"
	local message
	HandBrakeCLI --preset-import-gui --preset "$preset" --all-audio -i "$source" -o "$target" 1> "$temp_dir/handbrake.log" 2> "$temp_dir/handbrake.err" &
	while [[ -n $(jobs -r) ]]; do
		message="Convert: $(extract_handbrake_progress "$temp_dir/handbrake.log")"
		echo -e -n "$message\r"
		sleep 1s
	done
	clean_message "$message"
}

merge_video_and_audio() {
	local video_audio_source="$1"
	local remaining_source="$2"
	local target="$3"
	local audio_filter
	local message
	audio_filter=$(build_audio_filter)
	# shellcheck disable=SC2086
	mkvmerge -o "$target" --no-global-tags $audio_filter "$video_audio_source" -D -A "$remaining_source" 1> "$temp_dir/mkvmerge.log" 2> "$temp_dir/mkvmerge.err" &
	while [[ -n $(jobs -r) ]]; do
		message="Merge: $(extract_mkvmerge_progress "$temp_dir/mkvmerge.log")"
		echo -e -n "$message\r"
		sleep 1s
	done
	clean_message "$message"
}

get_target_file() {
	local file="$1"
	local source_dir="$2"
	local target_dir="$3"
	extension="$(basename "$file" | cut -d'.' -f2)"
	echo "$file" | sed "s|^${source_dir}|${target_dir}|" | sed "s|${extension}$|mkv|"
}

#################
# MAIN FUNCTION #
#################

convert_file() {
	local source="$1"
	local target="$2"
	# TODO if target already exists, overwrite or pass
	# TODO if conversion stopped, delete target
	if [[ ${source: -4} != ".mkv" ]]; then
		# TODO Ignore or copy (or custom?)
		# TODO make output extension depends on preset
		# TODO manage other types of video
		# Normally it works already, but avoid extra operations: it seems too open (never fail)
		echo "Ignore $source: type not managed"
	else
		echo "Convert $source to $target"
		convert_video_and_audio "$source" "$video_audio_file" "$handbrake_preset"
		merge_video_and_audio "$video_audio_file" "$source" "$target"
	fi
}

convert_dir() {
	local recurse="$1"
	local source_dir="$2"
	local target_dir="$3"
	local source
	local target
	local depth
	
	depth=""
	if [[ "$recurse" == "" ]]; then
		depth="-maxdepth 1"
	fi
	
	# shellcheck disable=SC2086
	find "$source_dir" $depth -type f -print0 | while IFS= read -r -d '' source; do
		target="$(get_target_file "$source" "$source_dir" "$target_dir")"
		convert_file "$source" "$target"
	done
}

echo "All intermediary files will be stored in $temp_dir"
if [[ "$input" != "" ]]; then
	output="$(get_target_file "$input" "$(dirname "$input")" "$output_dir")"
	convert_file "$input" "$output"
else
	convert_dir "$recursive" "$input_dir" "$output_dir"
fi
echo "Conversion finished"
