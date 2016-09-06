'''
This script allows you to build configurations
using loops, with each call to the script executing
a different configuration. This expects the
underlying program to create a file marking the run complete.
Uses "lock" files to prevent a configuration from being started
once some other script has started it.

By Brian Goldman
'''
from os import path, makedirs, remove
from subprocess import call
import time
import errno
import sys

def try_run(jobid, command, task_finished_file):
    '''
    Determine if a specific command should be performed by this process.

    jobid - The unique identifier of this job
    command - The execuable call + all of its arguments to perform
    task_finished_file - This file exists only if a run was successful
    '''
    lock_file = task_finished_file + ".lock"
    # Check if the task has already been done or if someone else is doing it.
    if path.exists(task_finished_file):
        if path.exists(lock_file):
            remove(lock_file)
    elif path.exists(lock_file):
        return False
    # Attempt to grab the lock on this task
    with open(lock_file, 'w') as f:
        f.write(jobid + '\n')
        f.write(command + '\n')
    time.sleep(10)
    # Check if you successfully grabbed the lock
    with open(lock_file, "r") as f:
        saved = f.read().strip().split()[0].strip()
        if saved != jobid:
            # Some other job wrote to the lock after you did.
            print "Double starts:", jobid, saved
            return False
    print command
    # Execute the command. This is a blocking call.
    call(command.split())
    # If the task was successful, remove the lock.
    # If the task failed, the lock must be removed manually. Prevents cascade failure.
    return True

def make_sure_folders_exists(filename):
    '''
    Given a filename, create the directory structure necessary for that file to be created.
    '''
    try:
        makedirs(path.dirname(filename))
    except OSError as exception:
        if exception.errno != errno.EEXIST:
            raise

if __name__ == "__main__":
    '''
    This is my example usage of the script. Everything from here down should
    be modified by YOU to fit your application.
    '''
    import sys, os
    from glob import glob
    jobname = sys.argv[1]

    if len(sys.argv) < 3:
        qsub_dir = os.path.dirname(os.path.realpath(__file__))
    else:
        qsub_dir = sys.argv[2]

    # Iterate over each configuration I want to test
    for qsub_file in glob(qsub_dir+"/*.qsub"):
        if try_run(jobname, "qsub {0}".format(qsub_file), qsub_file+"_done"):
            print "Job Completed"
            # Remove the following line if you want a
            # single call to run multiple configurations
            sys.exit()
    print "No jobs left to run, stopping resubmissions"
    open(qsub_dir+"/finished.txt", 'w').close()
