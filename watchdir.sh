#!/bin/bash

# Sync file change / directory watch by Tamas Dravavolgyi <tamas.dravavolgyi@capita.co.uk>

watch=/var/atlassian
watches=`cat /proc/sys/fs/inotify/max_user_watches`

first=1
lazyness=3

function takeCareOfFileAndSync(){

this=$1
withThis=$2

# Work.variables
sync=`mktemp`
tmp=`mktemp`
tmp2=`mktemp`

# Sorting inotify data
awk '{print $1$3}' < ${inot} | grep -v \/$ | sort | uniq > ${tmp}

# Sorting input ($1, $2) data
diff ${this} ${withThis} | grep ^\> | awk '{print $2}' | grep -v \/$ | sort | uniq > ${tmp2}

# Concat>inotify+in.data
cat ${tmp} ${tmp2} | sort | uniq > ${sync}

echo "rsync ${sync}"
echo "rm ${sync}"

}

if [ $watches -lt 65536 ]; then
	echo "65536" > /proc/sys/fs/inotify/max_user_watches
fi

for ((;;)) do

	het=`date +%s`
	new=/tmp/watch${het}
	export inot=/tmp/inot${het}

	find ${watch} > $new
	
	echo "inotifywait -m -o $new -e modify -r ${watch} &>/dev/null &"
	inotifywait -m -o ${inot} -e modify -r ${watch} &>/dev/null &
	
	sleep $lazyness

	killall inotifywait

	if [ $first -eq 1 ]; then
		first=0
	else
		takeCareOfFileAndSync $old $new
	fi
	
	old=$new		# set current filename as the other cycle's baseline
	
	ls -1 /tmp/watch* | grep -v $old | grep -v $new | xargs rm -f	# Clean everything which is not current

done
