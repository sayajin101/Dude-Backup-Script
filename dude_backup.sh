#!/bin/bash
#--========================================--#
# Set Varibles			       #
# Only Change the below varibles you need to #
#--========================================--#
sshPort="22";				#
path="/home/backups/dude";		   #
#--========================================--#

# Check User arguments
[ -z "${1}" ] || [ -z "${2}" ] || [ -z "${3}" ] && echo -e "\nPlease specify the following arguments\n($(basename $0) IPADDR USERNAME PASSWORD)" && exit 1;

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


# User Credentials
ip="${1}";
userName="${2}";
passWord="${3}";
ftpURL="ftp://${ip}";

# Log File
logFile="${path}/logs/${date}.log";
rm -f "${logFile}";
touch "${logFile}";

# Get Dude Store Folder Path
dudeStoreDir=$(ssh -4f -p ${sshPort} -i "${path}/key/mikrotik" -o ConnectTimeout="60" -o BatchMode="yes" -o StrictHostKeyChecking="no" ${userName}@"${ip}" ':put [/dude get data-directory];' | tr -d '\r');
echo "${dudeStoreDir}";

# Dude status function
dudeServerStatus() {
	echo "Entering Status Function";
	[ -n "${counter}" ] && {(( counter++ )) && sleep 15;} || {(( counter++ ));};
	ncftpls -u ${userName} -p ${passWord} ${ftpURL}/dude/ | grep -c 'dude\.db-';
	status=$(ssh -4f -p ${sshPort} -i "${path}/key/mikrotik" -o ConnectTimeout="60" -o BatchMode="yes" -o StrictHostKeyChecking="no" ${userName}@"${ip}" ':put [/dude get status]' | tr -d '\r');
	[ -n "${status}" ] && echo "Status...${status}";

	if [ "${1}" == "stopDude" ]; then
		if [ `echo -n "${status}" | grep -c ': stopped$'` -eq "0" ]; then
			[ `ncftpls -u ${userName} -p ${passWord} ${ftpURL}/dude/ | grep -c 'dude\.db-'` -ne "0" ] && dudeServerStatus stopDude;
		fi;
	fi;
	if [ "${1}" == "VacuumDB" ]; then
		if [ `ncftpls -u ${userName} -p ${passWord} ${ftpURL}/dude/ | grep -c 'dude\.db-'` -ne "0" ]; then
			[ `ncftpls -u ${userName} -p ${passWord} ${ftpURL}/dude/ | grep -c 'dude\.db-'` -ne "0" ] && dudeServerStatus VacuumDB;
		fi;
	fi;
	if [ "${1}" == "backupFile" ]; then
		if [ `echo -n "${status}" | grep -c '^export done$'` -eq "0" ]; then
			[ `ncftpls -u ${userName} -p ${passWord} ${ftpURL}/dude/ | grep -c "^${dudeStoreDir}/dude-backup-${date}-${ip}.tgz$"` -eq "0" ] && dudeServerStatus backupFile;
		fi;
	fi;
	if [ "${1}" == "startDude" ]; then
		if [ `echo -n "${status}" | grep -c '^running'` -eq "0" ]; then
			[ `ncftpls -u ${userName} -p ${passWord} ${ftpURL}/dude/ | grep -c 'dude\.db-'` -ne "0" ] && dudeServerStatus startDude;
		fi;
	fi;
}

# Stop Dude Service
echo "Stopping Dude Server";
ssh -4f -p ${sshPort} -i "${path}/key/mikrotik" -o ConnectTimeout="60" -o BatchMode="yes" -o StrictHostKeyChecking="no" ${userName}@"${ip}" '/dude set enabled=no;';
dudeServerStatus stopDude;

# Vacuum Dude Database
echo "Vacuum completed";
ssh -4f -p ${sshPort} -i "${path}/key/mikrotik" -o ConnectTimeout="60" -o BatchMode="yes" -o StrictHostKeyChecking="no" ${userName}@"${ip}" '/dude vacuum-db;';
dudeServerStatus vacuumDB;

# Create dude backup file
echo "Creating Backup File";
ssh -4f -p ${sshPort} -i "${path}/key/mikrotik" -o ConnectTimeout="60" -o BatchMode="yes" -o StrictHostKeyChecking="no" ${userName}@"${ip}" '/dude export-db backup-file="'${dudeStoreDir}'/dude-backup-'${date}'-'${ip}'.tgz"'
dudeServerStatus backupFile;

# Start Dude Service
echo "Starting Dude Service";
ssh -4f -p ${sshPort} -i "${path}/key/mikrotik" -o ConnectTimeout="60" -o BatchMode="yes" -o StrictHostKeyChecking="no" ${userName}@"${ip}" '/dude set enabled=yes;';
dudeServerStatus startDude;

# Download Backup to the Backup Directory
echo "Downloading backup file";
backupDir="${path}/backups";
cd ${backupDir};
echo "Dude Backup is being downloaded";
ncftpget -u ${userName} -p ${passWord} ${ftpURL}/${dudeStoreDir}/dude-backup-${date}-${ip}.tgz;


# Cleanup
rm -f ${lockFilePath}/backup_dude;
