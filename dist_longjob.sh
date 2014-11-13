#!/bin/bash 
#DESCRIPTION checkpoint restart for long jobs, and batching of subsequent jobs into arrays
#
# Inspired by longjob, written by Dirk Colbry
# Written by Rosangela Canino-Koning
#

## Script acts as the initial job runner,
## or as the restorer of a checkpointed job

## Setup and Environment Variables

# Set the default wait time to just under four hours
#export BLCR_WAIT_SEC=$(( 4 * 60 * 60 - 5 * 60 ))
export BLCR_WAIT_SEC=30 # 90 seconds for testing

# these variables must be passed in via qsub -v, or be exported in the environment
# if calling dist_longjob.sh directly (not recommended).
# e.g. qsub -v JOBNAME=JOB_YES,TARGET_DIR="/mnt/home/caninoko/tmp/qsub_dev/output/101"

echo TARGETDIR $TARGETDIR
echo STARTSEED $STARTSEED
seed=$(($STARTSEED + $PBS_ARRAYID))
JOBTARGET="${JOBNAME}_${seed}"
echo seed $seed
echo JOBTARGET $JOBTARGET
echo JOBNAME $JOBNAME
echo JOBSEEDS $JOBSEEDS
echo DEST_DIR $DEST_DIR
echo LSTRING $LSTRING
echo JOBCOMMAND $JOBCOMMAND
echo CONFIGDIR $CONFIGDIR
echo CPR $CPR

###### get the job going
if [ $CPR -eq "0" ] ## initial
then
    ## do the inital work
    #change directory to the directory this was run from
    cd $PBS_O_WORKDIR

    # create the tmp dir where we will do our work
    mkdir $TMPDIR/$JOBTARGET

    # copy the config dir
    cp -r ${CONFIGDIR}/* $TMPDIR/$JOBTARGET

    # head to the tmp directory on the node
    cd $TMPDIR/$JOBTARGET

    pwd > pwd.data ## copy our actual path for later relocation

    # dump out the JOBCOMMAND
    echo "#!/bin/bash -c" > command.sh
    echo $JOBCOMMAND >> command.sh
    chmod 755 ./command.sh

    # and run it with cr_run

    cr_run ./command.sh 1> blcr.output.txt 2>&1 &
    export PID=$!

    # finally, make up the directory where our stuff will go in the end
    mkdir $TARGETDIR/$JOBTARGET
else ## restart an existing job!
    
    # go to the final location, where we should've stashed our checkpoint
    cd $TARGETDIR/$JOBTARGET 

    # create our node tmp directory location
    mkdir $TMPDIR/$JOBTARGET 

    # copy everything to our tmp directory
    cp -r * $TMPDIR/$JOBTARGET 

    # head to the tmp directory
    cd $TMPDIR/$JOBTARGET

    # restart our job, using the pwd we saved before!
    oldpath=`cat pwd.data`
    newpath=`pwd`
    echo "Restarting!"
    echo $oldpath
    echo $newpath
    echo "HEYA RESTARTING" >> blcr.output.txt
    cr_restart --relocate "${oldpath}"="${newpath}" --no-restore-pid --file checkpoint.blcr >> blcr.output.txt 2>&1 &
    PID=$!

    # re-save the pwd information for the next iteration
    pwd > pwd.data
fi

copy_out() {
    tar czf dist_transfer.tar.gz .

    mv dist_transfer.tar.gz $TARGETDIR/$JOBTARGET
    cd $TARGETDIR/$JOBTARGET
    tar xzf dist_transfer.tar.gz
    rm dist_transfer.tar.gz
}

checkpoint_timeout() {
    echo "Timeout. Checkpointing Job"

    time cr_checkpoint --term $PID

    if [ ! "$?" == "0" ]
    then
        echo "Failed to checkpoint."
        exit 2
    fi

    # rename the context file
    mv context.${PID} checkpoint.blcr

    # stash the context file (and everything else) to the final location
    copy_out;

    # sleep a random amount of time
    sleep $[ 10 + $[ RANDOM % 20 ]]

    ## calculate what the successor job's name should be

    # trim out the excess after the [ from the jobID
    trimmedid=`echo ${PBS_JOBID} | rev | cut -d[ -f2- | rev`

    # now, trim the completed name down to 16 characters because that's
    # what'll show up on qstat
    sname=`echo "${trimmedid}_${JOBNAME}" | cut -c 1-16`
    echo $sname

    # look through qstat until you find the name
    echo "qstat -u $PBS_O_LOGNAME | grep $sname | wc -l"
    combinedstatus=`qstat -u $PBS_O_LOGNAME | grep $sname | wc -l`

    # if we didn't find it, go ahead and create the successor job ourselves
    # start it in a held state
    if [ $combinedstatus -lt 1 ]
    then
        echo qsub -h -l $LSTRING -N $sname -o ${DEST_DIR}/message.log -t $JOBSEEDS -v STARTSEED="${STARTSEED}",TARGETDIR="${TARGETDIR}",JOBNAME="${JOBNAME}",DEST_DIR="${DEST_DIR}",JOBSEEDS="${JOBSEEDS}",LSTRING="$LSTRING",CPR=1,EMAILSCRIPT="$EMAILSCRIPT" /mnt/research/devolab/dist_qsub/dist_longjob.sh
        qsub -h -l $LSTRING -N $sname -o ${DEST_DIR}/message.log -t $JOBSEEDS -v STARTSEED="${STARTSEED}",TARGETDIR="${TARGETDIR}",JOBNAME="${JOBNAME}",DEST_DIR="${DEST_DIR}",JOBSEEDS="${JOBSEEDS}",LSTRING=\"$LSTRING\",CPR=1,EMAILSCRIPT="$EMAILSCRIPT" /mnt/research/devolab/dist_qsub/dist_longjob.sh 
    fi

    # now, find the ID of the successor job
    # trim it down so we can send messages to it.
    echo "qstat -u $PBS_O_LOGNAME | grep "$sname" | awk '{print \$1}' | rev | cut -d[ -f2- | rev"
    sid=`qstat -u $PBS_O_LOGNAME | grep "$sname" | awk '{print \$1}' | rev | cut -d[ -f2- | rev`

    # send an un-hold message to our particular successor sub-job 
    echo "qrls -t $PBS_ARRAYID ${sid}[]"
    qrls -t $PBS_ARRAYID ${sid}[]
}


# set checkpoint timeout, which will go in the background.
# This will run if the job didn't finish before the timer runs out.
# Because the timeout kills the job, the wait ${PID} below will return.
# Even after the wait ${PID} below returns, the timeout may still be going,
# what with re-submitting the job, etc.
echo $BLCR_WAIT_SEC
(sleep $BLCR_WAIT_SEC; echo 'Timer Done'; checkpoint_timeout;) &
timeout=$!
echo "starting timer (${timeout}) for $BLCR_WAIT_SEC seconds"

echo "Waiting on cr_run job: $PID"
wait ${PID} 
RET=$?

#Check to see if job finished because it checkpointed
if [ "${RET}" = "143" ] #Job terminated due to cr_checkpoint 
then
	echo "Job seems to have been checkpointed, waiting for checkpoint_timeout to complete."
	wait ${timeout}
	exit 0
fi

## JOB completed
echo "Oh, hey, we finished before the timeout!"

#Kill timeout timer 
kill ${timeout} # prevent it from doing anything dumb.

#Copy data out to final location
copy_out;

#Email the user that the job has completed
$EMAILSCRIPT $PBS_JOBID $USER " " $JOBNAME
#	 qstat -f ${PBS_JOBID} | mail -s "JOB COMPLETE" ${USER}@msu.edu
echo "Job completed with exit status ${RET}"
qstat -f ${PBS_JOBID} | grep "used"
export RET
