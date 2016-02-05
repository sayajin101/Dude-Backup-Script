#!/bin/bash

#--========================================--#
# Set Varibles	                  		       #
# Only Change the below varibles you need to #
#--========================================--#
sshPort="22";			                           #
path="/home/backups/dude";                   #
#--========================================--#


# Check Folder Structure
[ ! -d "${path}/key" ] || [ ! -d "${path}/logs" ] || [ ! -d "${path}/backups" ] && mkdir -p "${path}"/{key,backups,logs};

# Check if ssh key exists
[ ! -f "${path}/key/mikrotik" ] && { ssh-keygen -q -t dsa -N "" -C "Used for Backups" -f "${path}/key/mikrotik" && echo -e "\nSSH Key has been created in ${path}/key called mikrotik.pub\nYou must upload & import the key into your Mikrotik -> system -> users -> ssh keys\n" && exit 1; };
[ -f "${path}/key/mikrotik.pub" ] && { echo "Once uploaded & imported to your Mikrotik, remove the file ${path}/key/mikrotik.pub" && exit 1; };

# Check if ncftpget exists
[ `which ncftpget > /dev/null 2>&1; echo $?` -ne 0 ] && { echo -e "\nYou need to install package 'nfctp' for this script to work correctly\n" && exit 1; };

pid_count=$(ps axc | awk "{if (\$5==\"$(basename $0)\") print \$1}" | grep -c "$$";);
date=$(/bin/date +%Y%m%d);

# Check for stale process(s) & kill them
if [ `pidof -x $(basename $0) > /dev/null` ]; then
	for p in $(pidof -x ${basename $0}); do
		if [ $p -ne $$ ]; then
			kill -9 ${p};
			echo "Script $0 is already running: exiting";
			exit 1;
		fi;
	done;
fi;

if [ $pid > /dev/null ]; then
	for p in $pid; do
		if [ "$p" -ne "$$" ]; then
			kill -9 $p;
		fi;
	done;
fi;

# Check if script is already running / Already been run that day
if [ "${pid_count}" -gt "1" ]; then
	echo "Backup Script Already Running";
	exit 1;
elif [ -d "${path}/backups/${date}" ]; then
	echo "Backups for ${date} have already been Run";
	exit 1;
else
	echo "Starting Dude Backup Script";
	lockFilePath="/var/run/backup";
	[ ! -d "${lockFilePath}" ] && mkdir ${lockFilePath};
	echo "$$" > ${lockFilePath}/backup_dude;
fi;


# Check User arguments
[ -z "${1}" ] || [ -z "${2}" ] || [ -z "${3}" ] && echo -e "\nPlease specify the following arguments\n($(basename $0) IPADDR USERNAME PASSWORD)" && exit 1;


# User Credentials
ip="${1}";
userName="${2}";
passWord="${3}";
ftpURL="ftp://${ip}";

# Log File
logFile="${path}/logs/${date}.log";
rm -f "${logFile}";
touch "${logFile}";

# Dude Store Folder Path
dudeStoreDir=$(ssh -4f -p ${sshPort} -i "${path}/key/mikrotik" -o ConnectTimeout="60" -o BatchMode="yes" -o StrictHostKeyChecking="no" ${userName}@"${ip}" ':put [/dude get data-directory];' | tr -d '\r');

dudeServerStatus() {
	[ -n "${counter}" ] && {(( counter++ )) && sleep 15;} || {(( counter++ ));};
	status=$(ssh -4f -p ${sshPort} -i "${path}/key/mikrotik" -o ConnectTimeout="60" -o BatchMode="yes" -o StrictHostKeyChecking="no" ${userName}@"${ip}" ':put [/dude get status]' | tr -d '\r');
	[ -n "${status}" ] && echo "Status...${status}";
	if [ `echo -n "${status}" | grep -c '^export done\|^running'` -eq "0" ]; then
		dudeServerStatus;
	elif [ `ssh -4f -p ${sshPort} -i "${path}/key/mikrotik" -o ConnectTimeout="60" -o BatchMode="yes" -o StrictHostKeyChecking="no" ${userName}@"${ip}" ':global dudeDIR [/dude get data-directory ]; :if ([:len [/file find name~"^\$dudeDIR-backup-.*.tgz"]] > 0) do={ :put [/dude get status]; };' | tr -d '\r' | grep -c '^export done\|^running'` -eq "0" ]; then
		dudeServerStatus;
	fi;
}

# Vacuum Dude Database & Create Backup File
if [ `ssh -4f -p ${sshPort} -i "${path}/key/mikrotik" -o ConnectTimeout="60" -o BatchMode="yes" -o StrictHostKeyChecking="no" ${userName}@"${ip}" ':global dudeDIR [/dude get data-directory]; /file remove [/file find where name~"^$dudeDIR-backup-.*'$ip'.tgz"]; :if ([:len $dudeDIR] > 0) do={ /dude vacuum-db; :delay 10; /dude export-db backup-file="$dudeDIR-backup-'$date'-'$ip'.tgz" }' > /dev/null 2>&1; echo $?` -ne "0" ]; then
	echo "${ip}, Dude Backup file was not created. - $?" >> ${logFile};
else
	echo -e "Dude Server has started Database Vacuum & Export\n";
	# Goto Backup status function loop
	dudeServerStatus;
fi;

# Download Backup to the Backup Directory
backupDir="${path}/backups";
cd ${backupDir};
echo "Dude Backup is being downloaded";
ncftpget -u ${userName} -p ${passWord} ${ftpURL}/${dudeStoreDir}-backup-${date}-${ip}.tgz;

# Cleanup
rm -f ${lockFilePath}/backup_dude;
