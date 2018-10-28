#!/bin/bash

# This script is intended to be used for identifying videos to be re-encoded
# for compression. It retrieves the size, duration, etc. of the files given
# in arguments. They are displayed in one line, separated by tabs for easy
# retrieval in tables. If the duration cannot be retrieved, the file is
# assumed not to be a video, and thus ignored.

dir_opt="dir"
dir_opt_short="d"
entries_only_opt="entries-only"
entries_only_opt_short="e"
help_opt="help"
help_opt_short="h"
parallel_opt="parallel"
parallel_opt_short="p"
status_opt="status"
status_opt_short="s"
separator_opt="separator"
separator_opt_short="t"

err_no_dir=64
err_unknown_option=65

sep=$(echo -e "\t")
temp_dir=$(mktemp -d "${TMPDIR:-/tmp/}$(basename "$0").XXXXXXXXXXXX")

#########
# USAGE #
#########

display_usage() {
	local cmd
	cmd=$(basename "$0")
	cat <<EOF
Usage:
	$cmd --$dir_opt=<dir> [--$separator_opt=<sep>] [--$status_opt] [--$parallel_opt] [--$entries_only_opt]
	$cmd --$help_opt

Options:
	--$dir_opt, -$dir_opt_short
		Directory to scan for video files.
	--$entries_only_opt, -$entries_only_opt_short
		Show only entries, without headers.
	--$help_opt, -$help_opt_short
		Display this usage page.
	--$parallel_opt, -$parallel_opt_short
		Parallelize each entry formatting. Faster, but can be heavy on I/O.
	--$status_opt, -$status_opt_short
		Show progress.
	--$separator_opt, -$separator_opt_short
		Use specific separator. Use tabulation by default. Pay attention to
		special characters and avoid characters you may find in the data.

Errors:
	$err_no_dir	No directory provided.
	$err_unknown_option	Unknown option.
EOF
}

###########
# OPTIONS #
###########

show_headers="true"

for arg in "$@"; do
case $arg in
	--$dir_opt=*|-$dir_opt_short=*)
		scan_dir="${arg#*=}"
		shift
		;;
	--$separator_opt=*|-$separator_opt_short=*)
		sep="${arg#*=}"
		shift
		;;
	--$status_opt|-$status_opt_short)
		show_status="true"
		shift
		;;
	--$parallel_opt|-$parallel_opt_short)
		parallelize="true"
		shift
		;;
	--$entries_only_opt|-$entries_only_opt_short)
		show_headers="false"
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

if [ "$scan_dir" = "" ];then
	>&2 echo "No directory provided for scan, add --$dir_opt"
	>&2 display_usage
	exit $err_no_dir
fi

##################
# FILE FUNCTIONS #
##################

get_size() {
	local file="$1"
	
	du -s "$file" | cut -f1 -
}

get_time() {
	local file="$1"
	
	ffmpeg -i "$file" 2>&1 | grep "Duration" | cut -d ' ' -f 4 | sed "s/,//"
}

get_seconds() {
	local time="$1"
	local value
	local ref
	
	value=$(date --date="$time" +"%s")
	ref=$(date --date="0" +"%s")
	echo $((value - ref))
}

get_bitrate() {
	local size="$1"
	local seconds="$2"
	
	echo $((size / seconds))
}

####################
# IGNORE FUNCTIONS #
####################

ignored_file="$temp_dir/ignore"
ignore() {
	local file="$1"
	local cause="$2"
	
	>&2 echo "Ignore because $cause: $file"
	echo "" >> "$ignored_file" # Store empty line because we only count lines
}

count_ignored() {
	if [ -f "$ignored_file" ]; then
		wc -l < "$ignored_file"
	else
		echo 0
	fi
}

#####################
# DISPLAY FUNCTIONS #
#####################

display_headers() {
	echo "Size (kB)${sep}Time${sep}Seconds${sep}Bitrate (kB/s)${sep}File"
}

display_entry() {
	local file="$1"
	local time
	local seconds
	local size
	local bitrate
	
	time=$(get_time "$file")
	if [ "$time" = "" ] || [ "$time" = "N/A" ] ;then
		ignore "$file" "no time available"
		return
	fi
	
	seconds=$(get_seconds "$time")
	if [ "$seconds" = "0" ]; then
		ignore "$file" "time is zero"
		return
	fi
	
	size=$(get_size "$file")
	bitrate=$(get_bitrate "$size" "$seconds")

	echo "${size}${sep}${time}${sep}${seconds}${sep}${bitrate}${sep}${file}"
}

######################
# PROGRESS FUNCTIONS #
######################

now() {
	date +"%s"
}

total_file="$temp_dir/total"

# Retrieve total in parallel
find "$scan_dir" -type f | wc -l > "$total_file" &

next_check=$(now) # Next check on first call
check_step=1 # Check again after 1s
get_total() {
	local default="$1"
	local total
	
	total="$(cat "$total_file")"
	next_check=$((next_check + check_step))
	if [ "$total" != "" ]; then
		echo "$total"
	else
		echo "$default"
	fi
}

total="-"
get_progress() {
	local count="$1"
	local percent="-"
	
	if [ "$total" == "-" ]; then
		total="$(get_total "$total")"
	fi
	
	if [ "$total" != "-" ]; then
		percent=$((100 * count / total))
	fi
	
	echo "$count/$total ($percent%)"
}

count=0
update_progress() {
	count=$((count + 1))
	if [ "$show_status" == "true" ]; then
		>&2 echo -en "$(get_progress "$count"), $(count_ignored) ignored\r"
	fi
}

terminate_progress() {
	>&2 echo ""
}
if [ "$show_status" == "true" ]; then
	trap terminate_progress EXIT
fi

#################
# MAIN FUNCTION #
#################

scan() {
	local dir="$1"
	
	if [ "$show_headers" == "true" ]; then
		display_headers
	fi
	find "$dir" -type f | while read file; do
		if [ "$parallelize" == "true" ]; then
			display_entry "$file" &
		else
			display_entry "$file"
		fi
		update_progress
	done
	wait
	
	# Hack to wait for child jobs warnings (ignored files).
	# Otherwise, the last ones tend to be displayed after
	# termination and mess the prompt.
	if [ "$parallelize" == "true" ]; then
		sleep 1
	fi
}

scan "$scan_dir"
