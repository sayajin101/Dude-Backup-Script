# Dude-Backup-Script

This is a Linux bash script for the new Mikrotik Dude Server (6.34+)

* It will create all the needed directories for you once you modify the top 2 Variables to your liking.
* It will automatically create you a ssh key for the mikrotik that you need to upload & import onto the mikrotik there the Dude Server resides.
* The script will then get the dude-store location & vacuum it, once it has vacuumed the DB it will start an export of the DB.
* Once the export is completed nfctpget is used to download the DB backup.

* Script usage
* ./dude_backup.sh IPADDR USERNAME PASSWORD
* 
