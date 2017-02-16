#!/bin/bash

pref=https://www.youtube.com/watch?v=

for i in $(cat $1); do
	youtube-dl --extract-audio --audio-format mp3 --audio-quality 2 $pref$i
done
