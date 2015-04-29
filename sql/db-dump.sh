#!/bin/bash

dumpdir=/home/username/dbdump

dt=`date +%d-%b-%Y`

dumpfile=$dumpdir/username-dbdump-$dt.sql

/usr/bin/mysqldump --add-drop-table -udbusername -pdbpassword dbname > $dumpfile

gzip $dumpfile
