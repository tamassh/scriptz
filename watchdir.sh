#!/bin/bash

# Sync file change / directory watch by Tamas Dravavolgyi <tamas.dravavolgyi@capita.co.uk>

# export watch=/var/atlassian

function takeCareOfFileAndSync(){
this=$1
withThis=$2
	
	if [ -z $# -eq 1 ]; then
		echo "Exiting due to first run .."
		break
	fi

	diff $this $withThis | grep ^\> | awk '{print $2}' > $sync
	echo "rsync ${sync}"

	if [ $? -eq 0 ]; then
		echo "Coool"
	else
		echo "Eeehhhhh"
	fi
}

# Aligning up to HH:MM:01 sec to avoid possible clock skew or delays in operation.
atSec=`date +%S`
waitSec=`expr 60 - $atSec + 1`

echo "Starting main loop in $waitSec second, it's time for inner peace :)"
sleep $waitSec


for ((;;)) do

	new=/tmp/watch`date +%s`

	find

	inotifywait -m -o $new -e modify -r /tmp &

	sleep 10

	killall inotifywait
	takeCareOfFileAndSync $old $new

	old=$new
done

