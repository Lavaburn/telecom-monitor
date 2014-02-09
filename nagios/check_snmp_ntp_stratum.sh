#!/bin/bash

check_env() {
	for i in ntpdc awk grep
	do
		if ! which $i > /dev/null 2>&1; then
			echo "$i is not installed!"
			exit 3 #UNKNOWN
		fi
	done
}

check_ntp_stratum() {
	peer=`ntpdc -c sysinfo "$hostname" 2> /tmp/ntptest | grep "system peer:" | awk '{print $3}'`
	errors=`wc -l /tmp/ntptest | awk '{print $1}'`
	stratum=`ntpdc -c sysinfo "$hostname" | grep "stratum:" | awk '{print $2}'`

	if [[ "$errors" -gt "0" ]];
	then
		echo "STRATUM UNKNOWN - NTP is not responding!"
		stateid=3
	elif [[ "$stratum" -lt "5" ]];
	then
    		echo  "Stratum = $stratum (System Peer: $peer) - OK |stratum=$stratum;"
       		stateid=0
	elif  [[ "$stratum" -lt "8" ]];
  	then
      		echo  "Stratum = $stratum (System Peer: $peer) - WARNING |stratum=$stratum;"
       		stateid=1
	elif  [[ "$stratum" -lt "16" ]];
   	then
      		echo  "Stratum = $stratum (System Peer: $peer) - CRITICAL |stratum=$stratum;"
         	stateid=2
	elif  [[ "$stratum" -eq "16" ]];
   	then
      		echo  "Stratum = $stratum (System Peer: $peer) - CRITICAL |stratum=$stratum;"
        	stateid=2
	else
		echo  "STRATUM UNKNOWN. Level: Stratum = $stratum (System Peer: $peer) - UNKNOWN"
        	stateid=3                    
        fi

	exit $stateid
}


hostname="$1"
check_env
check_ntp_stratum
