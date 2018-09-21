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

# sbatch automatically exports variables

echo TARGETDIR $TARGETDIR
echo STARTSEED $STARTSEED
seed=$(($STARTSEED + $SLURM_ARRAY_TASK_ID))
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
echo CONSTRAINT $CONSTRAINT
echo PPN $PPN
echo MEM $MEM
echo MAILUSER $MAILUSER
echo TIME $TIME


user=$(whoami)
timeout_retries=0


# Double-check that this job isn't already done (someone might have been trying to resubmit other jobs in the array)
if [ -f ${QSUB_FILE}_done_arrayjobs.txt ]
then 
    isdone=`grep -w ${SLURM_ARRAY_TASK_ID} ${QSUB_FILE}_done_arrayjobs.txt | wc -l`
    if [ $isdone -eq 1 ]
    then
        echo "Job already done"
        exit 0
    fi
fi


checkpoint_finished=0


###### get the job going
# if ls $TARGETDIR/$JOBTARGET/ckpt_*.dmtcp 1> /dev/null 2>&1;    # if no ckpt file exists, it is first time run, use dmtcp_launch
if [ $CPR -ne "0" ] ## initial
then


    ## restart an existing job!
    
    # go to the final location, where we should've stashed our checkpoint
    cd $TARGETDIR/$JOBTARGET

    ######################## start dmtcp_coordinator #######################
    # current working directory shuld have source code dmtcp1.c
    # cd ${SLURM_SUBMIT_DIR}

    fname=port.$SLURM_JOBID                                                                 # to store port number 
    dmtcp_coordinator --daemon --exit-on-last -p 0 --port-file $fname $@ 1>/dev/null 2>&1   # start coordinater
    h=`hostname`                                                                            # get coordinator's host name 
    p=`cat $fname`                                                                          # get coordinator's port number 
    export DMTCP_COORD_HOST=$h                                                  # save coordinators host info in an environment variable
    export DMTCP_COORD_PORT=$p                                                  # save coordinators port info in an environment variable
    
    #rm $fname
    
    echo "coordinator is on host $DMTCP_COORD_HOST "
    echo "port number is $DMTCP_COORD_PORT "
    echo " working directory: "
    pwd 
    echo " job script is $SLURM_JOBSCRIPT "


    # restart our job, using the pwd we saved before!
    echo "Restarting!"
    echo "HEYA RESTARTING" >> run.log
    dmtcp_restart -h $DMTCP_COORD_HOST -p $DMTCP_COORD_PORT ckpt_*.dmtcp >> run.log 2>&1 &
    # ./dmtcp_restart_script.sh >> run.log 2>&1 &
    PID=$!
    echo "Restarted" >> run.log

else 
    ## do the inital work
    #We have no clue where this was actually submitted from, but we know
    #the configdir is at the level below it

    echo "Starting new run!"

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

    ######################## start dmtcp_coordinator #######################
    # current working directory shuld have source code dmtcp1.c
    # cd ${SLURM_SUBMIT_DIR}

    fname=port.$SLURM_JOBID                                                                 # to store port number 
    dmtcp_coordinator --daemon --exit-on-last -p 0 --port-file $fname $@ 1>/dev/null 2>&1   # start coordinater
    h=`hostname`                                                                            # get coordinator's host name 
    p=`cat $fname`                                                                          # get coordinator's port number 
    export DMTCP_COORD_HOST=$h                                                  # save coordinators host info in an environment variable
    export DMTCP_COORD_PORT=$p                                                  # save coordinators port info in an environment variable
    
    #rm $fname
    
    echo "coordinator is on host $DMTCP_COORD_HOST "
    echo "port number is $DMTCP_COORD_PORT "
    echo " working directory: "
    pwd 
    echo " job script is $SLURM_JOBSCRIPT "


    # Add this ID to the list of ids associated with this chunk of jobs
    trimmedid=${SLURM_ARRAY_JOB_ID}
    echo $trimmedid >> ${QSUB_FILE}_successor_jobs.txt

    # and run it with cr_run

    dmtcp_launch -h $DMTCP_COORD_HOST -p $DMTCP_COORD_PORT --rm --ckpt-open-files ./command.sh 1> run.log 2>&1 &
    PID=$!
    echo "Started!" >> run.log

fi


resubmit_array() {

    echo ""
    echo "Resubmitting array!"
    echo ""

    ## calculate what the successor job's name should be

    # trim out the excess after the [ from the jobID
    trimmedid=${SLURM_ARRAY_JOB_ID}

    # now, trim the completed name down to 16 characters because that's
    # what'll show up on qstat
    sname=`echo "${trimmedid}_${JOBNAME}" | cut -c 1-16`
    echo $sname

    echo "Sleeping to break race condition"
    # sleep a random amount of time (to break up the identical stacks of jobs)
    sleep $[ 3 + $[ RANDOM % 10 ]]

    # look through qstat until you find the name
    echo "squeue -l -u $SLURM_JOB_USER | grep $sname | wc -l"
    combinedstatus=`squeue -l -u $SLURM_JOB_USER | grep $sname | wc -l`

    # if we didn't find it, go ahead and race to make the successor job ourselves
    # and start it in a held state
    if [ $combinedstatus -lt 1 ]
    then
        # check if someone else is already in charge.
        if [ ! -f $TARGETDIR/$sname.* ]
        then
            # throw my hat in the ring
            touch $TARGETDIR/${sname}.${SLURM_ARRAY_TASK_ID}
            sleep 5
            # ooh, it's a race.
            if [ `ls $TARGETDIR/$sname.* | sort | head -1` == $TARGETDIR/$sname.${SLURM_ARRAY_TASK_ID} ]
            then
                ## it's me!
                echo "WON THE RACE"

                corrected_lstring=`echo $LSTRING | tr " " ","`

                echo sbatch -H $CONSTRAINT -J $sname --output=${DEST_DIR}/${JOBNAME}_message.log-%a --array=$JOBSEEDS -c $PPN --mem=$MEM --time=$TIME --mail-user=$MAILUSER --export=CPR=0,ALL ${DIST_QSUB_DIR}/dist_longjob.sh
                sbatch -H $CONSTRAINT -J $sname --output=${DEST_DIR}/${JOBNAME}_message.log-%a --array=$JOBSEEDS -c $PPN --mem=$MEM --time=$TIME --mail-user=$MAILUSER --export=CPR=0,ALL ${DIST_QSUB_DIR}/dist_longjob.sh

                sleep 10

                rm $TARGETDIR/$sname.* # clean up

                ### Grab the ID of the job we just made and stuff it into the jobs file
                ### Original ID should have already been added above
                echo "squeue -u $SLURM_JOB_USER -o"%A %j" | grep "$sname" | cut -d " " -f 1"
                mysid=`squeue -u $SLURM_JOB_USER -o"%A %j" | grep "$sname" | cut -d " " -f 1`
                echo $mysid >> ${QSUB_FILE}_successor_jobs.txt
		        
                # Attempt to restart any orphaned jobs (i.e. jobs that should run but that don't have any jobs around
                # that could possibly start them - this happens if the precursor dies in a weird way)
                # Start by iterating over all jobs in the current array that are still in the held state
                # (since it's suspicious that they haven't even started running and this one is already done)
                # This grep selects lines with the correct trimmedid and priority of 0 (meaning they are held)
                
                echo "Restarting orphaned jobs"

                for jid in $(squeue -r -u $SLURM_JOB_USER -o"%A %j %K %p" | grep -E "^$trimmedid.*0\.0+$" | cut -d ' ' -f 3)
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
                        running=$(expr $running + `squeue -j $suc_$jid -o"%t" | grep "R" | wc -l`)
                    done <${QSUB_FILE}_successor_jobs.txt
                    
                    if [ $running -lt 1 ] 
                    then 
                        echo "Job isn't running. Restarting it"
                
                        # Cleanup any jobs that were supposed to run this but never got released - we're in charge now
                        while read suc || [[ -n $suc ]]
                            do 
                                if [ $suc -ne ${mysid} ]
                            then
                                scancel ${suc}_$jid
                            fi
                            done <${QSUB_FILE}_successor_jobs.txt
                        
                        # Run the job
                        echo scontrol release ${mysid}_$jid
                        scontrol release ${mysid}_$jid
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

    echo "Successor array created!"

    # now, find the ID of the successor job
    # trim it down so we can send messages to it.
    echo "squeue -u $SLURM_JOB_USER -o"%A %j" | grep "$sname" | cut -d " " -f 1"
    mysid=`squeue -u $SLURM_JOB_USER -o"%A %j" | grep "$sname" | cut -d " " -f 1`

    # send an un-hold message to our particular successor sub-job
    echo "scontrol release ${mysid}_${SLURM_ARRAY_TASK_ID}"
    scontrol release ${mysid}_${SLURM_ARRAY_TASK_ID}

    #delete all the finished jobs we know about (for sanity)
    echo "Deleting all other unneeded successor subjobs."
    while read j || [[ -n $j ]]
    do
        while read p || [[ -n $p ]]
        do
            # TODO: ADD CHECK HERE TO SEE IF JOB EXISTS!
            echo scancel ${j}_$p
            scancel ${j}_$p
        done <${QSUB_FILE}_done_arrayjobs.txt
    done <${QSUB_FILE}_successor_jobs.txt

    echo "Done with Timeout and Checkpoint Processing"
    exit 0
}

handle_didnt_timeout() {
# Ooh, we're executing again. Something musta happened.

    if [ "$checkpoint_finished" -eq "1" ]
    then
        # Psych, we did time out
        echo "Already checkpointed. Going back to sleep"
        exit 0
    fi

    if dmtcp_command -h $DMTCP_COORD_HOST -p $DMTCP_COORD_PORT -s 1>/dev/null 2>&1
    then
        echo "Something has gone wrong - the job is still running"
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

    if [ "${RET}" = "99" ]   #DMTCP Error
    then
        echo "CRASH - There was an error with DMTCP. Not sure what it was."
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

    echo "Cleanup - PREPPING TO DELETE UN-NEEDED SUBJOBS"
    trimmedid=${SLURM_ARRAY_JOB_ID}
    echo trimmedid = $trimmedid
    # now, trim the completed name down to 16 characters because that's
    # what'll show up on qstat
    sname=`echo "${trimmedid}_${JOBNAME}" | cut -c 1-16`
    echo "echo "${trimmedid}_${JOBNAME}" | cut -c 1-16"
    echo sname = $sname

    sid=`squeue -u $SLURM_JOB_USER -o"%A %j" | grep "$sname" | cut -d " " -f 1`
    echo "squeue -u $SLURM_JOB_USER -o"%A %j" | grep "$sname" | cut -d " " -f 1"
    echo Found Successor ID: $sid
    if [ -n "$sid" ]
    then
        echo "Deleting unneeded successor subjob:" $sid
        echo scancel ${sid}_$SLURM_ARRAY_TASK_ID
        scancel ${sid}_$SLURM_ARRAY_TASK_ID
    else
        echo "No successor job found."
    fi

    #delete all the finished jobs we know about (for sanity)
    echo "Deleting all other unneeded successor subjobs."
    if [ -f ${QSUB_FILE}_done_arrayjobs.txt ]
    then
        while read j || [[ -n $j ]]
        do
            # Sucessors for jobs that have already been marked as done
            while read p || [[ -n $p ]]
            do
                # TODO: CHECK TO SEE IF THESE EXIST BEFORE WE CANCEL THEM!
                echo scancel $j_$p
                scancel $j_$p
            done <${QSUB_FILE}_done_arrayjobs.txt

            # Delete this job from other arrays
            if [ $j -ne $trimmedid ]
            then
                scancel $j_${SLURM_ARRAY_TASK_ID}
            fi

        done <${QSUB_FILE}_successor_jobs.txt
    fi
    #Notify the email script that we're done.
    # If all sub-jobs are done, it'll email the user that
    # the job has completed
    $EMAILSCRIPT $SLURM_ARRAY_JOB_ID $USER " " $JOBNAME
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

    # qstat -f ${SLURM_ARRAY_JOB_ID} | grep "used"
    # export RET

    # Make sure not to submit too many jobs
    current_jobs=`expr $(squeue -u $user | wc -l) - 1`
    echo "There are currently ${current_jobs} jobs in the queue"

    if [ ! -f $QSUB_DIR/finished.txt ] # If "finished.txt" exists, no more tasks need to be done
    then
        # submits the next job
        if [ $current_jobs -lt $MAX_QUEUE ]
        then
            echo "Trying to submit another job"
            python $DIST_QSUB_DIR/scheduler.py ${SLURM_ARRAY_JOB_ID} $QSUB_DIR
        fi
    fi

    ## mark our job as being complete, so it gets cleaned up in later iterations.
    ## This happens at the very end so no other jobs try to clean it up while it's still doing cleanup
    echo $SLURM_ARRAY_TASK_ID >> ${QSUB_FILE}_done_arrayjobs.txt

}


# begin checkpoint timeout, which will go in the background.
# This will run if the job didn't finish before the timer runs out.
# Because the timeout kills the job, the wait ${PID} below will return.
# Even after the wait ${PID} below returns, the timeout may still be going,
# what with re-submitting the job, etc.
echo "Sleeping for $BLCR_WAIT_SEC seconds"
sleep $BLCR_WAIT_SEC


###############################################################################
############### NOW WE WAIT ###################################################
###############################################################################

if dmtcp_command -h $DMTCP_COORD_HOST -p $DMTCP_COORD_PORT -s 1>/dev/null 2>&1
then  
    # clean up old ckpt files before start checkpointing
    rm -r ckpt_*.dmtcp

    # checkpointing the job
    echo "About to checkpoint"
    dmtcp_command -h $DMTCP_COORD_HOST -p $DMTCP_COORD_PORT --ckpt-open-files -bc

    if [ ! "$?" == "0" ]
    then
        echo "Checkpoint issue 1"
        
        # # If there were no successful checkpoints letting this get resubmitted again
        # # won't help. It will have to be resubmitted manually.
        # # TODO: There's probably a way to make that happen automatically
        # if [ ! -f checkpoint.blcr ] && [ ! -f checkpoint_safe.blcr ]
        # then
        #     exit 2
        # fi
        
    fi

    echo "About to kill running program"
    # kill the running program and quit
    dmtcp_command -h $DMTCP_COORD_HOST -p $DMTCP_COORD_PORT --quit

    if [ "$?" -ne "0" ]
    then
        echo "Checkpoint issue 2"
    fi

    wait ${PID}
    RET=$?

    if [ "$RET" -ne "0" ]
    then
        echo "Something went wrong with the command $RET"
    fi

    # resubmit this script to slurm
    #sbatch $SLURM_JOBSCRIPT

    # Clear repeated failure tracker
    rm last_failed 2> /dev/null
    rm last_two_failed 2> /dev/null
    checkpoint_finished=1
    resubmit_array

else

    echo "We didn't time out!"
    wait ${PID}
    RET=$?
    timeout_retries=$(expr $timeout_retries + 1)
    handle_didnt_timeout
    echo "Done with everything"

fi
