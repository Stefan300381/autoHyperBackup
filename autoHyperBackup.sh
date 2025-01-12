#!/bin/bash

function send_email ()
{
	echo "To: " $emailAddress > email.txt
	echo "From: " $emailAddress >> email.txt
	if [[ -z "${email_errormsg}" ]]
	then
		echo "Subject: Backup $jobName" >> email.txt
	else
		echo "Subject: ERROR Backup $jobName" >> email.txt
	fi
	
	echo "" >> email.txt
	echo "$date_start ### START ###" >> email.txt
	echo -e "$email_infomsg" >> email.txt
	if [[ ! -z "${email_errormsg}" ]]
	then
		echo -e "$email_errormsg" >> email.txt
	fi
	date_end=$(date '+%d.%m.%Y %H:%M:%S')
	echo "$date_end #### END ###" >> email.txt

    ssmtp $emailAddress < email.txt
	rm email.txt
	exit 0
}

function error_check ()
{
	if [[ ! -z "${email_errormsg}" ]]
    then
		send_email
	fi
}

function wake_up ()
{
	timestamp=$(date '+%d.%m.%Y %H:%M:%S')
	email_infomsg+="$timestamp Target not reachable -> waking up...\n"
	/usr/syno/sbin/synonet --wake $macAddress $netintf
	exitcode=$?
	if [ $exitcode -ne 0 ]
	then
		timestamp=$(date '+%d.%m.%Y %H:%M:%S')
		email_errormsg+="$timestamp ERROR:\n"
		email_errormsg+="Reason: Synonet wakeup command failed:\n"
		email_errormsg+="Command: /usr/syno/sbin/synonet --wake $macAddress $netintf\n"
		email_errormsg+="Exit Code: $exitcode\n"
	fi
	sleep 180
	ping -c 2 -w 2 $sshIP &>/dev/null
	exitcode=$?
	if [ $exitcode -ne 0 ]
	then
		timestamp=$(date '+%d.%m.%Y %H:%M:%S')
		email_errormsg+="$timestamp ERROR:\n"
		email_errormsg+="Reason: Remote server still unreachable 180s after waking up\n"
		email_errormsg+="Command: ping -c 2 -w 2 $sshIP\n"
		email_errormsg+="Exit Code: $exitcode\n"
	fi
}

#START

date_start=$(date '+%d.%m.%Y %H:%M:%S')

#check arguments
if [ $# -ne 7 ]
then
	echo "Required arguments: jobName HyperBackupID emailAddress sshUser sshIP macAddress netintf"
	echo "get backupID via: synoschedtask --get | grep dsmbackup"
	exit 1
fi

#variables
jobName=$1
HyperBackupID=$2
emailAddress=$3
sshUser=$4
sshIP=$5
macAddress=$6
netintf=$7
email_infomsg=""
email_errormsg=""

#check connection and wake up, if needed
timestamp=$(date '+%d.%m.%Y %H:%M:%S')
email_infomsg+="$timestamp Check if target is online...\n"
ping -c 2 -w 2 $sshIP &>/dev/null
if [ $? -ne 0 ]
then
	wake_up
	error_check
fi
timestamp=$(date '+%d.%m.%Y %H:%M:%S')
email_infomsg+="$timestamp Target online! -> Launching HyperBackup\n"


#launch HyperBackup
/var/packages/HyperBackup/target/bin/img_backup -B -k $HyperBackupID
exitcode=$?
if [ $exitcode -ne 0 ]
then
	timestamp=$(date '+%d.%m.%Y %H:%M:%S')
	email_errormsg+="$timestamp ERROR:\n"
	email_errormsg+="Reason: HyperBackup could not be launched or failed\n"
	email_errormsg+="Command: /var/packages/HyperBackup/target/bin/img_backup -B -k $HyperBackupID\n"
	email_errormsg+="Exit Code: $exitcode\n"
fi

error_check
timestamp=$(date '+%d.%m.%Y %H:%M:%S')
email_infomsg+="$timestamp Backup finished successfully"

#after backup historic data might get wiped, check for existing img_backup process
while true; do 
    if ! pidof "img_backup" > /dev/null 2>&1; then
        #shutdown remote server
        ssh $sshUser@$sshIP 'sudo shutdown -h now' &>/dev/null
        #if [ $? -ne 0 ]
        #then
        #   email_errormsg+="ERROR: Remote server shutdown failed\n"
        #    email_errormsg+="CMD: ssh $sshUser@$sshIP 'sudo shutdown -h now'\n"
        #   email_errormsg+="EXITCODE: $?\n"
        #fi

        send_email
        break
    else
        sleep 60
    fi
done
