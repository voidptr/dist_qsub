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
export BLCR_WAIT_SEC=$(( 4 * 60 * 60 - 600 ))
#export BLCR_WAIT_SEC=30 # 90 seconds for testing

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
echo DIST_QSUB_DIR $DIST_QSUB_DIR
echo QSUB_DIR $QSUB_DIR
echo QSUB_FILE $QSUB_FILE
echo MAX_QUEUE $MAX_QUEUE


user=$(whoami)
timeout_retries=0
###### get the job going
if [ $CPR -eq "0" ] ## initial
then
    ## do the inital work
    #We have no clue where this was actually submitted from, but we know
    #the configdir is at the level below it

    # create the directory where we will do our work
    mkdir $TARGETDIR/$JOBTARGET
    echo mkdir $TARGETDIR/$JOBTARGET

    # copy the config dir
    cp -r ${CONFIGDIR}/* $TARGETDIR/$JOBTARGET
    echo cp -r ${CONFIGDIR}/* $TARGETDIR/$JOBTARGET

    # head to the tmp directory on the node
    cd $TARGETDIR/$JOBTARGET
    echo cd $TARGETDIR/$JOBTARGET


    # dump out the JOBCOMMAND
    echo "#!/bin/bash" > command.sh
    echo $JOBCOMMAND >> command.sh
    chmod 755 ./command.sh


    # Add this ID to the list of ids associated with this chunk of jobs
    trimmedid=`echo ${PBS_JOBID} | rev | cut -d[ -f2- | rev`
    echo $trimmedid >> ${QSUB_FILE}_successor_jobs.txt

    # and run it with cr_run

    cr_run ./command.sh 1> run.log 2>&1 &
    export PID=$!

else ## restart an existing job!

    # Double-check that this job isn't already done (someone might have been trying to resubmit other jobs in the array)
    isdone=`grep -w ${PBS_ARRAYID} ${QSUB_FILE}_done_arrayjobs.txt | wc -l`
    if [ $isdone -eq 1 ]
    then
        echo "Job already done"
        exit 0
    fi

    # go to the final location, where we should've stashed our checkpoint
    cd $TARGETDIR/$JOBTARGET

    # restart our job, using the pwd we saved before!
    echo "Restarting!"
    echo "HEYA RESTARTING" >> run.log
    cr_restart --no-restore-pid --run-on-fail-temp="echo temp_fail" --run-on-fail-perm="echo perm_fail" --run-on-fail-env="echo env_fail" --run-on-fail-temp="echo args_fail" --run-on-success="echo Success" --file checkpoint.blcr >> run.log 2>&1 &
    PID=$!
fi

copy_out() {
    tar czf dist_transfer.tar.gz .

    mv dist_transfer.tar.gz $TARGETDIR/$JOBTARGET
    cd $TARGETDIR/$JOBTARGET
    tar xzf dist_transfer.tar.gz
    rm dist_transfer.tar.gz
}

resubmit_array() {

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
                echo "WON THE RACE"

                corrected_lstring=`echo $LSTRING | tr " " ","`

                echo qsub -h -l $corrected_lstring -N $sname -o ${DEST_DIR}/${JOBNAME}_message.log -t $JOBSEEDS -v STARTSEED="${STARTSEED}",TARGETDIR="${TARGETDIR}",JOBNAME="${JOBNAME}",DEST_DIR="${DEST_DIR}",JOBSEEDS="${JOBSEEDS}",LSTRING="$LSTRING",CPR=1,EMAILSCRIPT="$EMAILSCRIPT",DIST_QSUB_DIR="${DIST_QSUB_DIR}",QSUB_FILE="${QSUB_FILE}",MAX_QUEUE="${MAX_QUEUE}" ${DIST_QSUB_DIR}/dist_longjob.sh
                qsub -h -l $corrected_lstring -N $sname -o ${DEST_DIR}/${JOBNAME}_message.log -t $JOBSEEDS -v STARTSEED="${STARTSEED}",TARGETDIR="${TARGETDIR}",JOBNAME="${JOBNAME}",DEST_DIR="${DEST_DIR}",JOBSEEDS="${JOBSEEDS}",LSTRING="$LSTRING",CPR=1,EMAILSCRIPT="$EMAILSCRIPT",DIST_QSUB_DIR="${DIST_QSUB_DIR}",QSUB_FILE="${QSUB_FILE}",MAX_QUEUE="${MAX_QUEUE}" ${DIST_QSUB_DIR}/dist_longjob.sh

                sleep 10

                rm $TARGETDIR/$sname.* # clean up

                ### Grab the ID of the job we just made and stuff it into the jobs file
                ### Original ID should have already been added above
                echo "qstat -u $PBS_O_LOGNAME | grep "$sname" | awk '{print \$1}' | rev | cut -d[ -f2- | rev"
                mysid=`qstat -u $PBS_O_LOGNAME | grep "$sname" | awk '{print \$1}' | rev | cut -d[ -f2- | rev`
                echo $mysid >> ${QSUB_FILE}_successor_jobs.txt
		
		# Attempt to restart any orphaned jobs (i.e. jobs that should run but that don't have any jobs around
		# that could possibly start them - this happens if the precursor dies in a weird way)
		# Start by iterating over all jobs in the current array that are still in the held state
		# (since it's suspicious that they haven't even started running and this one is already done)
		for jid in $(qselect -s H -u $PBS_O_LOGNAME | grep $trimmedid | cut -d '[' -f 2 | cut -d ']' -f 1)
		do 
		    # If this job is already completely done, go to the next iteration so we don't accidentally restart it
		    isdone=`grep -w $jid ${QSUB_FILE}_done_arrayjobs.txt | wc -l`
		    if [ $isdone -ge 1 ]
		    then
		    	continue
		    fi
		    
		    running=0
		    echo "Checking for orphaned jobs. JID:" $jid
		    while read suc || [[ -n $suc ]]
		    do 
		        # Is this job id running in any prior array? If so, it just got really far behind. No action required.
		        running=$(expr $running + `qstat -t $suc[$jid] | tail -n +3 | tr -s ' ' | cut -f 5 -d " " | grep "R" | wc -l`)
		    done <${QSUB_FILE}_successor_jobs.txt
		    
		    if [ $running -lt 1 ] 
		    then 
		        echo "Job isn't running. Restarting it"
		
			# Cleanup any jobs that were supposed to run this but never got released - we're in charge now
			while read suc || [[ -n $suc ]]
		    	do 
		            if [ $suc -ne ${mysid} ]
			    then
			    	qdel ${suc}[$jid]
			    fi
		    	done <${QSUB_FILE}_successor_jobs.txt
			
			# Run the job
			echo qrls -t $jid ${mysid}[]
			qrls -t $jid ${mysid}[]
		    fi
		done
		
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

    # send an un-hold message to our particular successor sub-job
    echo "qrls -t $PBS_ARRAYID ${sid}[]"
    qrls -t $PBS_ARRAYID ${sid}[]

    #delete all the finished jobs we know about (for sanity)
    echo "Deleting all other unneeded successor subjobs."
    while read j || [[ -n $j ]]
    do
        while read p || [[ -n $p ]]
        do
            echo qdel ${j}[$p]
            qdel ${j}[$p]
        done <${QSUB_FILE}_done_arrayjobs.txt
    done <${QSUB_FILE}_successor_jobs.txt

    echo "Done with Timeout and Checkpoint Processing"
}

checkpoint_timeout() {
    echo "Timeout. Checkpointing Job"

    # Sometimes, which checkpointing fails, it leaves behind a file called .checkpoint.blcr.tmp, which 
    # causes all future attempts to run cr_checkpoint to fail. There is no reason that a file like this
    # should exist immediately before we call cr_checkpoint, so this is a safe time to get rid of it
    # if necessary.
    if [ -f .checkpoint.blcr.tmp ]
    then
    	echo "Removing .checkpoint.blcr.tmp so it doesn't confuse cr_checkpoint"
	yes | rm .checkpoint.blcr.tmp
    fi

    time cr_checkpoint --term -f checkpoint.blcr --backup=checkpoint_safe.blcr --kmsg-warning --time 300 $PID

    if [ ! "$?" == "0" ]
    then
        echo "Failed to checkpoint."
	
	# If there were no successful checkpoints letting this get resubmitted again
	# won't help. It will have to be resubmitted manually.
	# TODO: There's probably a way to make that happen automatically
	if [ ! -f checkpoint.blcr ] && [ ! -f checkpoint_safe.blcr ]
	then
	    exit 2
	fi
        
    fi
    
    resubmit_array
}

# begin checkpoint timeout, which will go in the background.
# This will run if the job didn't finish before the timer runs out.
# Because the timeout kills the job, the wait ${PID} below will return.
# Even after the wait ${PID} below returns, the timeout may still be going,
# what with re-submitting the job, etc.
echo $BLCR_WAIT_SEC
(sleep $BLCR_WAIT_SEC; echo 'Timer Done'; checkpoint_timeout;) &
timeout=$!
echo "starting timer (${timeout}) for $BLCR_WAIT_SEC seconds"

echo "Waiting on cr_run job: $PID"
echo "ZZzzzzz"
wait ${PID}
RET=$?

###############################################################################
############### NOW WE WAIT ###################################################
###############################################################################



handle_didnt_timeout() {
# Ooh, we're executing again. Something musta happened.
# Check to see if we're moving along again because the job checkpointed
if [ "${RET}" = "143" ] #Job terminated due to cr_checkpoint
then

  # Clear repeated failure tracker
  rm last_failed 2> /dev/null
  rm last_two_failed 2> /dev/null
  
  echo "AWAKE - Job seems to have been checkpointed, waiting for checkpoint_timeout function to finish processing."
  wait ${timeout}
  echo "See you next time around..."
  exit 0
fi

echo "$timeout_retries timeouts"
# ELSE:
######################### JOB COMPLETED ##############################
# We're actually executing again because the job finished (no checkpointing).
# This could happen for a couple reasons.
#    1. Either the job legit finished,
#    2. The job crashed on checkpoint restart, as in, it never started up. :(
# Either way, we have some cleanup to do. :/

#Kill timeout timer
kill ${timeout} # prevent it from doing anything dumb.

echo "Sub-job seems to have finished. Here's the return code: "
echo ${RET}

if [ "${RET}" = "132" ] || [ "${RET}" = "139" ]  #Job terminated due to cr_checkpoint
then
    echo "CRASH - Job seems to have crashed, but it's unclear how."
    echo "Attempting crash recovery. Retries: $timeout_retries"

    #If we have a checkpoint_safe file and using it hasn't already failed
    #give that a shot
    if [ -f checkpoint.blcr ] && [ $timeout_retries -lt 2 ]
    then
      echo "Restarting..."
      mv checkpoint.blcr checkpoint_tried.blcr
      cr_restart --no-restore-pid --run-on-fail-temp="echo temp_fail" --run-on-fail-perm="echo perm_fail" --run-on-fail-env="echo env_fail" --run-on-fail-temp="echo args_fail" --run-on-success="echo Success" --file checkpoint_tried.blcr >> run.log 2>&1 &
      PID=$!

      #debugging
      touch attempted_recovery_check_$PID
      timeout_retries=$(expr $timeout_retries + 1)

      #Dividing it by 2 is probably overkill - just trying to play it safe.
      (sleep $(expr $BLCR_WAIT_SEC / 2); echo 'Timer Done'; checkpoint_timeout;) &
      timeout=$!
      echo "starting timer (${timeout}) for $BLCR_WAIT_SEC / 2 seconds"

      echo "Waiting on cr_run job: $PID"
      echo "ZZzzzzz"
      wait ${PID}
      RET=$?
      handle_didnt_timeout

    elif [ -f checkpoint_safe.blcr ] && [ $timeout_retries -lt 3 ]
    then
	    echo "Restarting..."
      mv checkpoint_safe.blcr checkpoint_safe_tried.blcr
      cr_restart --no-restore-pid --run-on-fail-temp="echo temp_fail" --run-on-fail-perm="echo perm_fail" --run-on-fail-env="echo env_fail" --run-on-fail-temp="echo args_fail" --run-on-success="echo Success" --file checkpoint_safe_tried.blcr >> run.log 2>&1 &
	    PID=$!

	    #debugging
	    touch attempted_recovery_checksafe_$PID
      timeout_retries=$(expr $timeout_retries + 1)

      #Dividing it by 2 is probably overkill - just trying to play it safe.
	    (sleep $(expr $BLCR_WAIT_SEC / 2); echo 'Timer Done'; checkpoint_timeout;) &
	    timeout=$!
	    echo "starting timer (${timeout}) for $BLCR_WAIT_SEC / 2 seconds"

	    echo "Waiting on cr_run job: $PID"
	    echo "ZZzzzzz"
	    wait ${PID}
	    RET=$?
	    handle_didnt_timeout
    fi

    #debugging
    if [ $timeout_retries -eq 3 ]
    then
	    touch array_resubmited_$PID
    	    echo "Restoring checkpoint files since it's unlikely they're both corrupted. This was probably caused by something else, like running on the wrong node"
	    mv checkpoint_safe_tried.blcr checkpoint_safe.blcr
	    mv checkpoint_tried.blcr checkpoint.blcr
	    
	    if [ -f last_failed ]
	    then
	    	
		if [ -f last_two_failed ]
		then
		    echo "Third array resubmit fail in a row... this isn't working"
		    echo "Letting this job die. Maybe it will get recovered by another job"
		    rm last_failed
		    rm last_two_failed
		    touch complete_array_resubmit_failure
		    exit 0
		fi
		echo "Hmmm... second array resubmit fail in a row. This isn't looking good."	    
	        touch last_two_failed
	    else
	        touch last_failed
	    fi
	    
	    echo "Resubmitting array... hopefully this will work next time around"
	    resubmit_array
    fi

    exit 0
fi


echo "Cleanup time"


## delete our successor job, should there be one
# trim out the excess after the [ from the jobID
echo "Cleanup - PREPPING TO DELETE UN-NEEDED SUBJOBS"
trimmedid=`echo ${PBS_JOBID} | rev | cut -d[ -f2- | rev`
echo "echo ${PBS_JOBID} | rev | cut -d[ -f2- | rev"
echo trimmedid = $trimmedid
# now, trim the completed name down to 16 characters because that's
# what'll show up on qstat
sname=`echo "${trimmedid}_${JOBNAME}" | cut -c 1-16`
echo "echo "${trimmedid}_${JOBNAME}" | cut -c 1-16"
echo sname = $sname

sid=`qstat -u $PBS_O_LOGNAME | grep "$sname" | awk '{print \$1}' | rev | cut -d[ -f2- | rev`
echo "qstat -u $PBS_O_LOGNAME | grep "$sname" | awk '{print \$1}' | rev | cut -d[ -f2- | rev"
echo Found Successor ID: $sid
if [ -n "$sid" ]
then
    echo "Deleting unneeded successor subjob:" $sid
    echo qdel -t $PBS_ARRAYID ${sid}[]
    qdel -t $PBS_ARRAYID ${sid}[]
else
    echo "No successor job found."
fi

#delete all the finished jobs we know about (for sanity)
echo "Deleting all other unneeded successor subjobs."
while read j || [[ -n $j ]]
do
    # Sucessors for jobs that have already been marked as done
    while read p || [[ -n $p ]]
    do
    	echo qdel $j[$p]
        qdel $j[$p]
    done <${QSUB_FILE}_done_arrayjobs.txt

    # Delete this job from other arrays
    if [ $j -ne $trimmedid ]
    then
	qdel $j[${PBS_ARRAYID}]
    fi

done <${QSUB_FILE}_successor_jobs.txt

#Notify the email script that we're done.
# If all sub-jobs are done, it'll email the user that
# the job has completed
$EMAILSCRIPT $PBS_JOBID $USER " " $JOBNAME
echo "Sub-job completed with exit status ${RET}"


#create task finished file
cp ${QSUB_FILE} ${QSUB_FILE}_done
echo "${QSUB_FILE} is done"

#remove lock file
rm ${QSUB_FILE}_done.lock 2> /dev/null
echo "Lock removed"

#remove original qsub file so we don't have to keep trying to submit it
rm ${QSUB_FILE} 2> /dev/null
echo "Original qsub file removed"

echo "Checking to see if there are more jobs that should be started"

qstat -f ${PBS_JOBID} | grep "used"
export RET

# Make sure not to submit too many jobs
current_jobs=$(showq -u $user | tail -2 | head -1 | cut -d " " -f 4)
echo "There are currently ${current_jobs} jobs in the queue"

if [ ! -f $QSUB_DIR/finished.txt ] # If "finished.txt" exists, no more tasks need to be done
then
    # submits the next job
    if [ $current_jobs -lt $MAX_QUEUE ]
    then
	     echo "Trying to submit another job"
	     python $DIST_QSUB_DIR/scheduler.py ${PBS_JOBID} $QSUB_DIR
    fi
fi

## mark our job as being complete, so it gets cleaned up in later iterations.
## This happens at the very end so no other jobs try to clean it up while it's still doing cleanup
echo $PBS_ARRAYID >> ${QSUB_FILE}_done_arrayjobs.txt

}

timeout_retries=$(expr $timeout_retries + 1)
handle_didnt_timeout
echo "Done with everything"
