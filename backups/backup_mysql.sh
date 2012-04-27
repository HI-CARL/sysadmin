#!/bin/bash

# Dump MySQL databases to file. Designed to be run on daily crontab.

##### Start Configuration #####
MYSQL_HOST=
MYSQL_PORT=3306
MYSQL_USER=
MYSQL_PASS=

# no trailing / please
BACKUP_LOCATION=/ebs/backup

##### Finish Configuration #####

rm $BACKUP_LOCATION/*.sql.gz

echo "Backing up MySQL databases on $MYSQL_HOST"
for DB in $(echo "show databases" | mysql -h$MYSQL_HOST -P$MYSQL_PORT -u$MYSQL_USER -p$MYSQL_PASS | grep -v Database | grep -v mysql | grep -v innodb | grep -v information_schema | grep -v performance_schema | grep -v test)
do
    echo "Dumping $DB to $BACKUP_LOCATION/${DB}.sql.gz"
    mysqldump -h$MYSQL_HOST -P$MYSQL_PORT -u$MYSQL_USER -p$MYSQL_PASS --hex-blob $DB | gzip -c -9 > $BACKUP_LOCATION/${DB}.sql.gz
done
echo "Done."
