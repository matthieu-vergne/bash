#!/bin/bash

#####################
# UTILITY FUNCTIONS #
#####################

temp_dir() {
	mktemp -d "${TMPDIR:-/tmp/}$(basename "$0").XXXXXXXXXXXX"
}

addValidVideo() {
	local target="$1"
	mkdir -p "$(dirname "$target")"
	cp "./test/video1.m4v" "$target"
}

addNoTimeVideo() {
	local target="$1"
	mkdir -p "$(dirname "$target")"
	touch "$target" # Empty file has no time
}

getUsageAsFile() {
	local dir
	dir=$(temp_dir)
	./size_all.sh 1> /dev/null 2> "$dir/stderr"
	echo "$dir/stderr"
}

##################
# TEST FUNCTIONS #
##################

testNoDirErrIsValidErr() {
	local err
	
	err=$(grep -E '^\s+[0-9]+\s+No directory provided\.$' < "$(getUsageAsFile)" | awk '{print $1}')
	assertNotNull "$err"
	assertTrue "[[ $err > 0 ]]"
}

testNoOptionFailsWithNoDirErr() {
	local dir
	local actual
	local noDirErr
	dir=$(temp_dir)
	noDirErr=$(grep -E '^\s+[0-9]+\s+No directory provided\.$' < "$(getUsageAsFile)" | awk '{print $1}')
	
	./size_all.sh 1> /dev/null 2> "$dir/stderr"
	actual="$?"
	assertEquals "$noDirErr" "$actual"
}

testUnknownOptionErrIsValidErr() {
	local err
	
	err=$(grep -E '^\s+[0-9]+\s+Unknown option\.$' < "$(getUsageAsFile)" | awk '{print $1}')
	assertNotNull "$err"
	assertTrue "[[ $err > 0 ]]"
}

testUnknownOptionFailsWithUnknownOptionErr() {
	local dir
	local actual
	local unknownOptionErr
	dir=$(temp_dir)
	unknownOptionErr=$(grep -E '^\s+[0-9]+\s+Unknown option\.$' < "$(getUsageAsFile)" | awk '{print $1}')
	
	./size_all.sh --my-unknown-option 1> /dev/null 2> "$dir/stderr"
	actual="$?"
	assertEquals "${unknownOptionErr}" "$actual"
}

testNoOptionDisplaysUsageOnStdErr() {
	local dir
	local result
	dir=$(temp_dir)
	
	./size_all.sh 1> /dev/null 2> "$dir/stderr"
	grep "Usage:" < "$dir/stderr" > /dev/null
}

testHelpOptionDisplaysUsageOnStdOut() {
	local dir
	local result
	dir=$(temp_dir)
	
	./size_all.sh --help 1> "$dir/stdout" 2> /dev/null
	assertContains "$(cat "$dir/stdout")" "Usage:"
}

testListAllValidVideoOfDir() {
	local dir
	local result
	dir=$(temp_dir)
	addValidVideo "$dir/vid1" &
	addValidVideo "$dir/vid2" &
	addValidVideo "$dir/vid3" &
	wait
	
	result="$(./size_all.sh --dir="$dir")"
	assertContains "$result" "$dir/vid1"
	assertContains "$result" "$dir/vid2"
	assertContains "$result" "$dir/vid3"
}

testListAllValidVideoOfSubDir() {
	local dir
	local result
	dir=$(temp_dir)
	addValidVideo "$dir/sub/vid1" &
	addValidVideo "$dir/sub/vid2" &
	addValidVideo "$dir/sub/vid3" &
	wait
	
	result="$(./size_all.sh --dir="$dir")"
	assertContains "$result" "$dir/sub/vid1"
	assertContains "$result" "$dir/sub/vid2"
	assertContains "$result" "$dir/sub/vid3"
}

testIgnoreVideoWithNoTime() {
	local dir
	local out
	local err
	dir=$(temp_dir)
	addNoTimeVideo "$dir/00-noTime" # First file
	for i in $(seq 1 9); do
		addValidVideo "$dir/0$i-vid"
	done
	addNoTimeVideo "$dir/10-noTime" # File somewhere between others
	for i in $(seq 11 19); do
		addValidVideo "$dir/$i-vid"
	done
	addNoTimeVideo "$dir/20-noTime" # Last file
	wait
	
	./size_all.sh --dir="$dir" 1> "$dir/stdout" 2> "$dir/stderr"
	# Ignored in output
	out="$(cat "$dir/stdout")"
	assertNotContains "In output:" "$out" "$dir/00-noTime"
	assertNotContains "In output:" "$out" "$dir/10-noTime"
	assertNotContains "In output:" "$out" "$dir/20-noTime"
	# Ignore warnings
	err="$(cat "$dir/stderr")"
	assertContains "In warnings:" "$err" "$dir/00-noTime"
	assertContains "In warnings:" "$err" "$dir/10-noTime"
	assertContains "In warnings:" "$err" "$dir/20-noTime"
}

testIgnoreVideoWithNoTimeWhenParallel() {
	local dir
	local out
	local err
	dir=$(temp_dir)
	addNoTimeVideo "$dir/00-noTime" # First file
	for i in $(seq 1 9); do
		addValidVideo "$dir/0$i-vid"
	done
	addNoTimeVideo "$dir/10-noTime" # File somewhere between others
	for i in $(seq 11 19); do
		addValidVideo "$dir/$i-vid"
	done
	addNoTimeVideo "$dir/20-noTime" # Last file
	wait
	
	./size_all.sh --dir="$dir" --parallel 1> "$dir/stdout" 2> "$dir/stderr"
	# Ignored in output
	out="$(cat "$dir/stdout")"
	assertNotContains "In output:" "$out" "$dir/00-noTime"
	assertNotContains "In output:" "$out" "$dir/10-noTime"
	assertNotContains "In output:" "$out" "$dir/20-noTime"
	# Ignore warnings
	err="$(cat "$dir/stderr")"
	assertContains "In warnings:" "$err" "$dir/00-noTime"
	assertContains "In warnings:" "$err" "$dir/10-noTime"
	assertContains "In warnings:" "$err" "$dir/20-noTime"
}

testNoShellCheckReportOnScript() {
	shellcheck ./size_all.sh
}

testNoShellCheckReportOnTests() {
	shellcheck "$(basename "$0")"
}

# Load shUnit2.
if [ "$SHUNIT2" == "" ]; then
	>&2 echo "SHUNIT2 environment variable undefined."
	>&2 echo "You need to create it with the path to your shunit2 script."
	exit 1
fi
. "$SHUNIT2"
