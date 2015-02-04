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
export BLCR_WAIT_SEC=$(( 4 * 60 * 60 - 5 * 60 ))
#export BLCR_WAIT_SEC=60 # 90 seconds for testing

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
echo EMAILSCRIPT $EMAILSCRIPT
echo USESCRATCH $USESCRATCH

###### get the job going
if [ $CPR -eq "0" ] ## initial
then
    ## do the inital work
    #change directory to the directory this was run from
    cd $PBS_O_WORKDIR

    # create the directory where we will do our work
    mkdir $TARGETDIR/$JOBTARGET

    # copy the config dir
    cp -r ${CONFIGDIR}/* $TARGETDIR/$JOBTARGET

    # head to the tmp directory on the node
    cd $TARGETDIR/$JOBTARGET


    # dump out the JOBCOMMAND
    echo "#!/bin/bash" > command.sh
    echo $JOBCOMMAND >> command.sh
    chmod 755 ./command.sh

    # and run it with cr_run

    cr_run ./command.sh 1> run.log 2>&1 &
    export PID=$!

else ## restart an existing job!

    # go to the final location, where we should've stashed our checkpoint
    cd $TARGETDIR/$JOBTARGET

    if [ $CPR -eq "2" ] ## we're performing some necromancy here!
    then
        ## ideally, we don't try to start any jobs that we know completed
        ## already. We know this because completed jobs will have cleaned
        ## up their checkpoint.blcr* files.
        if [ -f checkpoint.blcr~ ]
        then
            ## if we've got a backup, use that instead. Better to back up a
            ## step, than to risk pulling in a bad (unfinished, failed)
            ## checkpoint file
            cp checkpoint.blcr~ checkpoint.blcr
        fi

        if [ ! -f checkpoint.blcr ] # if there's no checkpoint
        then
            echo "Nothing to resuscitate."
            ## mark our job as being done, so it gets cleaned up in later iterations.
            echo $PBS_ARRAYID >> $TARGETDIR/${JOBNAME}_done_arrayjobs.txt
            ## TODO - this could create a lineage of zombie jobs if a resuscitation
            ## attempt is made on an already finished job. Imagine if this job
            ## gets finally queued after everyone else has moved on to the next
            ## iteration. It'd be the last one left to clean itself up from the
            ## next iteration. So, how can I ensure that they all get cleaned
            ## up? Imagine if EVERYONE is two iterations ahead, then there'll
            ## be a freaking line of zombie hold jobs that will never be
            ## enabled, but have no mechanism for getting cleaned up.
            exit 0
        fi
    fi

    # restart our job, using the context we saved before!
    echo "Restarting!"
    echo "HEYA RESTARTING" >> run.log
    cr_restart --no-restore-pid --file checkpoint.blcr >> run.log 2>&1 &
    PID=$!
fi

#echo $LSTRING >> lstring.out

copy_out() {
    tar czf dist_transfer.tar.gz .

    mv dist_transfer.tar.gz $TARGETDIR/$JOBTARGET
    cd $TARGETDIR/$JOBTARGET
    tar xzf dist_transfer.tar.gz
    rm dist_transfer.tar.gz
}

checkpoint_timeout() {
    echo "Timeout. Checkpointing Job"

    # make a backup of the starting checkpoint file
    mv checkpoint.blcr checkpoint.blcr~

    time cr_checkpoint --term $PID

    if [ ! "$?" == "0" ]
    then
        echo "Failed to checkpoint."

## TODO - revisit the died_once kill-switch. I feel like there's a corner
## case in here, but I can't quite put my finger on it. Stupid spaghetti code.

        if [ -f checkpoint.blcr~ ] && [ ! -f died_once.touch ]
        then
            echo "Attempting to recover by starting from a previous checkpoint."
            cp checkpoint.blcr~ checkpoint.blcr
            touch died_once.touch ## so we don't do this indefinitely
        else
            ## the only reason this could happen is if we die in the initial
            ## CPR=0 wave, without a checkpoint file ever having been produced.
            ## Ultimately, what this means is that we ran, somehow, all the
            ## way to the end of the timeout, but weren't able to checkpoint
            ## at all, the first time. I'm making a judgement call that this
            ## is bad, and probably not an HPCC issue with checkpointing,
            ## so I won't mandate a restart.
            ## This is one of those corner cases. DWI.
            ## ~~~ OR ~~~ we already tried restarting from backup once.
            echo "No working backup checkpoint file was found. Calling it dead."

            ## mark our job as being done, so it gets cleaned up in later iterations.
            echo $PBS_ARRAYID >> $TARGETDIR/${JOBNAME}_done_arrayjobs.txt
            ## also mark it as dead, for debugging purposes later
            echo $PBS_ARRAYID >> $TARGETDIR/${JOBNAME}_dead_arrayjobs.txt
            exit 2
        fi
    else
        # rename the context file
        mv context.${PID} checkpoint.blcr
    fi

    ## calculate what the successor job's name should be

    # trim out the excess after the [ from the jobID
    trimmedid=`echo ${PBS_JOBID} | rev | cut -d[ -f2- | rev`

    # now, trim the completed name down to 16 characters because that's
    # what'll show up on qstat
    sname=`echo "${trimmedid}_${JOBNAME}" | cut -c 1-16`
    echo $sname

    # sleep a random amount of time (to break up the identical stacks of jobs)
    sleep $[ 3 + $[ RANDOM % 10 ]]

    # look through qstat until you find the name
    echo "qstat -u $PBS_O_LOGNAME | grep $sname | wc -l"
    combinedstatus=`qstat -u $PBS_O_LOGNAME | grep $sname | wc -l`

    # if we didn't find it, go ahead and race to make the successor job ourselves
    # and start it in a held state
    if [ $combinedstatus -lt 1 ]
    then
        # check if someone else is already in charge.
        if [ ! -f $TARGETDIR/$sname.* ]
        then
            # throw my hat in the ring
            touch $TARGETDIR/${sname}.${PBS_ARRAYID}
            sleep 5
            # ooh, it's a race.
            if [ `ls $TARGETDIR/$sname.* | sort | head -1` == $TARGETDIR/$sname.${PBS_ARRAYID} ]
            then
                ## it's me!

                corrected_lstring=`echo $LSTRING | tr " " ","`

                echo qsub -h -l $corrected_lstring -N $sname -o ${DEST_DIR}/${JOBNAME}_message.log -t $JOBSEEDS -v STARTSEED="${STARTSEED}",TARGETDIR="${TARGETDIR}",JOBNAME="${JOBNAME}",DEST_DIR="${DEST_DIR}",JOBSEEDS="${JOBSEEDS}",LSTRING="$LSTRING",CPR=1,EMAILSCRIPT="$EMAILSCRIPT" /mnt/research/devolab/dist_qsub/dist_longjob.sh
                qsub -h -l $corrected_lstring -N $sname -o ${DEST_DIR}/${JOBNAME}_message.log -t $JOBSEEDS -v STARTSEED="${STARTSEED}",TARGETDIR="${TARGETDIR}",JOBNAME="${JOBNAME}",DEST_DIR="${DEST_DIR}",JOBSEEDS="${JOBSEEDS}",LSTRING="$LSTRING",CPR=1,EMAILSCRIPT="$EMAILSCRIPT" /mnt/research/devolab/dist_qsub/dist_longjob.sh

                sleep 10

                rm $TARGETDIR/$sname.* # clean up
            else
                # oop, lost the race
                echo "Lost the race, letting winner do the thing."
                sleep 10
            fi
        else
            echo "Someone else is already in charge, letting leader do the thing."
            # someone else is already doing it.
            sleep 10
        fi
    fi

    # now, find the ID of the successor job
    # trim it down so we can send messages to it.
    echo "qstat -u $PBS_O_LOGNAME | grep "$sname" | awk '{print \$1}' | rev | cut -d[ -f2- | rev"
    sid=`qstat -u $PBS_O_LOGNAME | grep "$sname" | awk '{print \$1}' | rev | cut -d[ -f2- | rev`

    # delete all the finished jobs we know about (for sanity)
    while read p || [[ -n $p ]]
    do
        qdel -t $p ${sid}[]
    done <${TARGETDIR}/${JOBNAME}_done_arrayjobs.txt

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

## JOB completed! And by itself, not because of checkpoint!

#Kill timeout timer
kill ${timeout} # prevent it from doing anything dumb.

echo "Oh, hey, we finished before the timeout!"

## mark our job as being complete, so it gets cleaned up in later iterations.
echo $PBS_ARRAYID >> $TARGETDIR/${JOBNAME}_done_arrayjobs.txt

## clean up old checkpoints, burn and salt the body to avoid necromancy
## ("CPR=2")
rm checkpoint.blcr~
rm checkpoint.blcr

## delete our successor job, should there be one
sid=`qstat -u $PBS_O_LOGNAME | grep "$sname" | awk '{print \$1}' | rev | cut -d[ -f2- | rev`
echo "Deleting unneeded successor subjob:" $sid
qdel -t $PBS_ARRAYID ${sid}[]

#Email the user that the job has completed
$EMAILSCRIPT $PBS_JOBID $USER " " $JOBNAME
#	 qstat -f ${PBS_JOBID} | mail -s "JOB COMPLETE" ${USER}@msu.edu
echo "Job completed with exit status ${RET}"
qstat -f ${PBS_JOBID} | grep "used"
export RET