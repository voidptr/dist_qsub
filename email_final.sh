#!/bin/bash

# wait some random number of seconds between 10-30
sleep $[ 10 + $[ RANDOM % 20 ]]

jobid=`echo $1 | awk -F "[" '{print $1}'`
jobname=`echo $4 | rev | cut -d- -f2- | rev`
combinedstatus=`qstat -t -a -u $2 | grep $jobid | awk '{print $10}'`
runningjobct=`echo $combinedstatus | grep -o "[^C ]" | wc -l`;

if [ $runningjobct -gt 1 ]; 
then 
    echo "STILL RUNNING"; 
else 
    /bin/echo -e "Job ID: " $jobid "\nJob Resource Request:\n" $6 | /bin/mail -s "Job Complete - $jobname" $2@msu.edu
    echo "Done"; 
fi



