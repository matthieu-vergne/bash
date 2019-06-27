#!/bin/bash

#####################
# UTILITY FUNCTIONS #
#####################

create_temp_dir() {
	mktemp -d "${TMPDIR:-/tmp/}$(basename "$0").XXXXXXXXXXXX"
}

get_usage_as_file() {
	local dir
	dir=$(create_temp_dir)
	./convert_video.sh --help 1> "$dir/usage" 2> /dev/null
	echo "$dir/usage"
}

get_error_code() {
	local regex
	regex="$1"
	local err
	grep -E "^\s+[0-9]+\s+${regex}$" < "$(get_usage_as_file)" | awk '{print $1}'
}

add_full_mkv_video() {
	local target="$1"
	mkdir -p "$(dirname "$target")"
	cp "./test/full_video.mkv" "$target"
}

add_small_mkv_video() {
	local target="$1"
	mkdir -p "$(dirname "$target")"
	cp "./test/small_video.mkv" "$target"
}

get_one_line_content() {
	tr '\n\r' ' ' < "$1"
}

##################
# TEST FUNCTIONS #
##################

test_help_option_displays_usage_on_std_out() {
	local dir
	
	dir=$(create_temp_dir)
	./convert_video.sh --help 1> "$dir/stdout" 2> /dev/null
	assertContains "$(cat "$dir/stdout")" "Usage:"
}

test_unknown_option_err_is_present_in_usage() {
	assertContains "$(cat "$(get_usage_as_file)")" "Unknown option."
}

test_unknown_option_err_is_valid_err() {
	local err
	
	err=$(get_error_code 'Unknown option\.')
	assertNotNull "$err"
	assertTrue "[[ $err > 0 ]]"
}

test_no_input_err_is_present_in_usage() {
	assertContains "$(cat "$(get_usage_as_file)")" "Missing input."
}

test_no_input_err_is_valid_err() {
	local err
	
	err=$(get_error_code 'Missing input\.')
	assertNotNull "$err"
	assertTrue "[[ $err > 0 ]]"
}

test_conflicting_input_err_is_present_in_usage() {
	assertContains "$(cat "$(get_usage_as_file)")" "Both file and folder inputs are given."
}

test_conflicting_input_err_is_valid_err() {
	local err
	
	err=$(get_error_code 'Both file and folder inputs are given\.')
	assertNotNull "$err"
	assertTrue "[[ $err > 0 ]]"
}

test_no_output_folder_err_is_present_in_usage() {
	assertContains "$(cat "$(get_usage_as_file)")" "Missing output folder."
}

test_no_output_folder_err_is_valid_err() {
	local err
	
	err=$(get_error_code 'Missing output folder\.')
	assertNotNull "$err"
	assertTrue "[[ $err > 0 ]]"
}

test_no_option_fails_with_no_input_err() {
	local dir
	local actual
	local err
	
	dir=$(create_temp_dir)
	err=$(get_error_code 'Missing input\.')
	
	./convert_video.sh 1> /dev/null 2> "$dir/stderr"
	actual="$?"
	assertEquals "$err" "$actual"
}

test_unknown_option_fails_with_unknown_option_err() {
	local dir
	local actual
	local err
	
	dir=$(create_temp_dir)
	err=$(get_error_code 'Unknown option\.')
	
	./convert_video.sh --my-unknown-option 1> /dev/null 2> "$dir/stderr"
	actual="$?"
	assertEquals "${err}" "$actual"
}

test_single_video_conversion_retrieves_converted_file_in_target_dir() {
	local src_dir
	local tgt_dir
	
	src_dir=$(create_temp_dir)
	add_small_mkv_video "$src_dir/video.mkv" &
	wait
	
	tgt_dir=$(create_temp_dir)
	./convert_video.sh --input="$src_dir/video.mkv" --output-dir="$tgt_dir" 1> /dev/null
	assertEquals "video.mkv" "$(ls "$tgt_dir")"
}

test_video_conversion_on_directory_retrieves_converted_file_for_each_video_in_target_dir() {
	local src_dir
	local tgt_dir
	
	src_dir=$(create_temp_dir)
	add_small_mkv_video "$src_dir/video1.mkv" &
	add_small_mkv_video "$src_dir/video2.mkv" &
	wait
	
	tgt_dir=$(create_temp_dir)
	./convert_video.sh --input-dir="$src_dir" --output-dir="$tgt_dir" 1> /dev/null
	assertContains "$(ls "$tgt_dir")" "video1.mkv"
	assertContains "$(ls "$tgt_dir")" "video2.mkv"
}

test_video_conversion_on_directory_retrieves_only_converted_files_in_target_dir() {
	local src_dir
	local tgt_dir
	local logs
	
	src_dir=$(create_temp_dir)
	add_small_mkv_video "$src_dir/file1.mkv" &
	echo "text" > "$src_dir/file2.txt" &
	wait
	
	tgt_dir=$(create_temp_dir)
	logs="$(create_temp_dir)/logs"
	./convert_video.sh --input-dir="$src_dir" --output-dir="$tgt_dir" 1> "$logs"
	logs="$(get_one_line_content "$logs")"
	
	assertContains "$(ls "$tgt_dir")" "file1.mkv"
	assertNotContains "$(ls "$tgt_dir")" "file2.txt"
}

test_non_recursive_video_conversion_retrieves_converted_files_only_in_root_directory() {
	local src_dir
	local tgt_dir
	
	src_dir=$(create_temp_dir)
	mkdir "$src_dir/child"
	add_small_mkv_video "$src_dir/video1.mkv" &
	add_small_mkv_video "$src_dir/child/video2.mkv" &
	wait
	
	tgt_dir=$(create_temp_dir)
	./convert_video.sh --input-dir="$src_dir" --output-dir="$tgt_dir" 1> /dev/null
	assertTrue "[ -f '$tgt_dir/video1.mkv' ]"
	assertFalse "[ -f '$tgt_dir/child/video2.mkv' ]"
}

test_recursive_video_conversion_retrieves_converted_files_in_all_tree() {
	local src_dir
	local tgt_dir
	
	src_dir=$(create_temp_dir)
	mkdir "$src_dir/child"
	add_small_mkv_video "$src_dir/video1.mkv" &
	add_small_mkv_video "$src_dir/child/video2.mkv" &
	wait
	
	tgt_dir=$(create_temp_dir)
	./convert_video.sh --input-dir="$src_dir" --recursive --output-dir="$tgt_dir" 1> /dev/null
	assertTrue "[ -f '$tgt_dir/video1.mkv' ]"
	assertTrue "[ -f '$tgt_dir/child/video2.mkv' ]"
}

# TODO test preset option

test_no_shell_check_report_on_script() {
	shellcheck ./convert_video.sh
}

test_no_shell_check_report_on_tests() {
	shellcheck "$(basename "$0")"
}

# Load shUnit2.
if [ "$SHUNIT2" == "" ]; then
	>&2 echo "SHUNIT2 environment variable undefined."
	>&2 echo "You need to create it with the path to your shunit2 script."
	exit 1
fi
. "$SHUNIT2"
