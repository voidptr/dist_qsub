export BLCR_WAIT_SEC=$((10))

checkpoint_timeout() {
    if [ -f .checkpoint.blcr.tmp ]
    then
    	echo "Removing .checkpoint.blcr.tmp so it doesn't confuse cr_checkpoint"
    	yes | rm .checkpoint.blcr.tmp
    fi

    time cr_checkpoint --term -f checkpoint.blcr --backup=checkpoint_safe.blcr --kmsg-warning --time 300 $PID

    if [ ! "$?" == "0" ]
    then
        echo "Failed to checkpoint."        
    fi
}


for dirname in */
do
    if [ -f $dirname/command.sh ] && [ ! -f $dirname/checkpoint.blcr -a ! -f $dirname/checkpoint_safe.blcr ]
    then
        echo "Restarting $dirname"
        cd $dirname
        cr_run ./command.sh 1> run.log 2>&1 &
        export PID=$!
        (sleep $BLCR_WAIT_SEC; echo 'Timer Done'; checkpoint_timeout;) &
        timeout=$!
        wait ${PID}
        RET=$?
        cd ..    
    fi
done