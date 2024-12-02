#!/bin/bash 
# (c) Tim Peugniez 2021

USAGE=$(cat << END
Usage: $(basename $0) [-n <count>] [-m <message>] [-a] [-e]
  -n	Squash the last <count> commits (default is 2) 
  -m	Use the given commit <message> (overrides the -a option) 
  -a	Include all commit messages (default is to use the oldest) 
  -e	Edit message before committing 
END
)

#TODO: Support skip/take parameters for squashing older commits?

LOG_FORMAT="%C(auto)%h %s (%cr)"

# Set default options
NUM=2
MSG=""
ALL=false
EDIT=false

# Parse command line
while getopts "h?n:m:ae" opt; do
	case "$opt" in
	h|\?)
		echo "${USAGE}"
		exit 0
		;;
	n)	NUM=$OPTARG
		if (( NUM < 2 )); then
			echo "Cannot squash fewer than two commits"
			exit 1
		fi
		;;
	m)	MSG=$OPTARG
		;;
	a)	ALL=true
		;;
	e)	EDIT=true
		;;
	esac
done

EDIT=$([ "$EDIT" = true ] && echo "--edit")

shift $(($OPTIND - 1))
if [ $# -gt 0 ]; then
	echo "${USAGE}"
	exit 1
fi

# Reference Nth previous commmit
OLD_REF="HEAD~$((NUM-1))"

# Extract commit message/s from git log if not given
if [ "$MSG" = "" ]; then
	if [ "$ALL" = true ]; then
		NEW_REF="HEAD"
	else
		NEW_REF="${OLD_REF}"
	fi
	
	MSG=$(git log --format=%s%b ${OLD_REF}^! ${NEW_REF})
	if [ $? -ne 0 ]; then
		exit 2 # git error
	fi
fi

# Display commits to be squashed
echo "Squashing ${NUM} commits:"
git log --format="${LOG_FORMAT}" "${OLD_REF}^!" "HEAD"
if [ $? -ne 0 ]; then
	exit 2 # git error
fi

# Record HEAD commit hash to rollback
HEAD_REF="$(git log --format=%H -1)"

# Check whether OLD_REF has a parent
git rev-parse --verify "${OLD_REF}~" &>/dev/null
if [ $? -eq 0 ]; then
	# Reset to OLD_REF parent and recommit subsequent changes
	git reset --soft "${OLD_REF}~" && git commit ${EDIT} -m "${MSG}"
else
	# OLD_REF has no parent so dereference HEAD and recommit all changes
	git update-ref -d HEAD && git commit ${EDIT} -m "${MSG}"
fi

# Rollback on reset & recommit failure
if [ $? -ne 0 ]; then
	echo "Cannot squash commits, rolling back..."
	git reset --hard "${HEAD_REF}"
	echo "Rolled back."
	exit 3 # git error / rollback
fi

# Display newly squashed commit
git log --format="${LOG_FORMAT}" -1
echo "Done."
exit 0
