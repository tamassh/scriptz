#!/bin/bash
#
# Version Thu 17 May 08:47:37 BST 2018, initial working
# Version Thu 17 May 09:54:11 BST 2018, added slight tune if a partial hostname found
# Version Fri 18 May 10:05:21 BST 2018, filtering root user
#
# For environments without DNS, heavily relying on /etc/hosts..

param=$1

if [[ -z $1 ]] || [[ $(id -u) -eq 0 ]]; then echo "Wa? Arg, user?" && exit 1; fi

hits=$(grep $param /etc/hosts | grep ^[0-9] | awk '{print $2}')
num=$(grep $param /etc/hosts | grep ^[0-9] | awk '{print $2}' | wc -l)

function conn(){
  if [ -z ${1} ]; then
    ssh $param 2>/dev/null || ssh $(grep $param /etc/hosts | grep ^[0-9] | head -${1} | tail -1 | awk '{print $1}') 2>/dev/null
  else
    ssh $(grep $param /etc/hosts | grep ^[0-9] | head -${1} | tail -1 | awk '{print $1}')
  fi
}

if [ $num -gt 1 ]; then
  printf "${hits}\nSelect: 1-${num}: "
  read answare
  conn ${answare}
else
  conn
fi
