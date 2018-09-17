dist_qsub: HPCC DevoLab dist_run replacement
===========================================

# Installation

dist_qsub is not installed on the HPCC by default. To use it, clone this repository to your HPCC account with the command:

```
git clone https://github.com/emilydolson/dist_qsub.git
```

# Creating a run_list file

A run_list file is a series of runs of experiments that you want to run on the HPCC. It starts with a header, which specifies various settings:

```
  email - (required) the email address for HPCC messages (crashes only)

  email_when - [default: final, always] email when the whole job finishes only (default), or an email for every sub-job ("always"). Note, these emails only go to USERNAME@msu.edu. Sorry.

  class_pref - Set this to 200 unless you know what you're doing. Supported classes 91, 92, 95, 150 (intel14), 200 (intel16).

  walltime - ints only, in hours. If you're using checkpointing, this should be 4.

  mem_request - in gigabytes

  dest_dir - (required) the path to the output directory. All of the results will be placed in sub-directories within this directory.

  config_dir - the path to a directory that contains configuration files. Will be copied into working directory before run.

  cpr - [default: 0] Set to 1 if you are resubmitting jobs that have already been checkpointed.

  ppn - the number of cores to request (default 1)

```

After the header, provide a list of experiments to run, each one on its own line. The format is:

```
[first_random_seed]..[last_random_seed] name_of_experiment command to run
```

If you aren't doing multiple replicates, and so only want a single random seed, you can specify it like this:
```
[random_seed] name_of_experiment command to run
```

The name of the experiment, in combination with the random seed, will be used to name the directory that its results are stored in, so make sure to give each one a unique name. In the command section, you can use `$seed` to use whatever the random seed for an individual run is.

For example, the line:

```
101..200 MyAvidaExperiment ./avida -s $seed -set WORLD_GEOMETRY 1 -set EVENT_FILE events_example.cfg
```
Would run Avida 100 times, using the random seeds 101-200. Avida would be run with the specified command-line arguments, which in this case happen to change the geometry of the world and use a non-default events file. The results would be stored in 100 different directories, named MyAvidaExperiment_101 through MyAvidaExperiment_200.

# Running dist_qsub

Before running, make sure a run_list file (see previous section) is in the directory along with a "config/"
directory with the content of the run. This is the same setup as the old dist_run
method.

To run:
```
% python ./dist_qsub.py [run_list]
```

To clean up after a run (critical if you're re-submitting jobs):
```
% python path/to/dist_qsub/cleanup.py
```

(do this from the directory containing your run_list, the directory containing your results, or use -l to specify the path to your run_list)

dist_qsub can handle an indefinite number of jobs by maintaining a pool of jobs to submit when space opens up. To add things to this pool when you've already got jobs running, put the new jobs into a run_list file and submit them (from the same directory you submitted the first set of jobs from) with:
```
% python path/to/dist_qsub/dist_qsub.py -p
```

If the number of jobs in queue (i.e. the total that shows up at the bottom of the output from showq -u [yourusername]) is low (< ~50), you can add more things by going to your `dest_dir/qsub_files` directory and manually submitting them (don't put more than ~540 total jobs in your queue) (dest_dir is the location your results are being stored in):

```
% cd dest_dir/qsub_files
% qsub [name_of_qsub_file.qsub]
```

## Full list of command-line options:

- **-h** - display help
- **-p** - print only mode (write qsub files without submitting them)
- **-v** - verbose mode. Prints extra information.
- **-d** - debug_messages. Prints debugging messages
- **--nocheckpoint** - Do not use checkpointing (can be simpler if you aren't running long jobs)
- **-m [number]** - Specify the maximum number of jobs dist_qsub should put in the queue.

# Checkpointing

By default, dist_qsub uses checkpointing to break your experiments into small pieces so they can run faster. After the walltime in your run_list header has elasped, the state of your experiment will be saved, the HPCC job running it will be killed, and a new one will be resubmitted in its place to pick up where it left off. If you do this, you should set your wall time to 4 hours, as this allows experiments to use the short jobs queue.


However, there can occasionally be problems with checkpointing. To turn off checkpointing, use the `--nocheckpoint` flag:

```
% python path/to/dist_qsub/dist_qsub.py --nocheckpoint
```
Note that, for efficiency, this will keep all data associated with the experiment on the compute node where it's being run until the end, at which point it will be transferred to `dest_dir`. This means that you will not be able to view the output until the job is over (and if you specify an inadequate walltime, the job will run out of time before it can copy anything and you will not be able to see any results).


## Checkpoint errors: when should you worry?

dist_qsub will do everything in its power to recover from failed attempts to make a checkpoint. You should only step in if:

- The last thing in run.log file is an error like this: `“Failed to open(checkpoint.blcr, O_RDONLY): No such file or directory”`. That means something went wrong before the first checkpoint was successfully made. If this happens, the first step is to make sure your program didn't encounter an internal error. Once you are sure that this is not the case, you can recover from this scenario by running the `dist_qsub/fix_early_fails.sh` script in `dest_dir`. This command will take a while - it is running the first 10 seconds of your program in every directory where checkpointing failed to create a checkpoint file to restart from. Once you have done this, assuming other jobs in the array are still running, the auto-recovery mechanisms should take over.
- All of the jobs from a given array are dead (figure this out with the command in "Get a list of qsub files without any jobs running" under the "Useful bash commands" section of this readme). If this happens, you should re-submit that set of jobs with `cpr` set to 1 (again, do this only if you are sure the error was the fault of your cluster not your code).
- An individaul job has failed to restart for 8 or more hours. This points to a problem with that specific job.

# Resubmitting

Sometimes runs die. It is a fact of life. `resubmit.py` can help you figure out which runs died, and painlessly re-run them (although if you are using checkpointing, be aware that there are a lot of auto-recovery mechanisms in place). It will look at your output files and make sure that that output files for all of your conditions go to the correct number of updates. By default, `resubmit.py` assumes the correct number of updates is 100,000. If you ran your experiments for a different length of time, you should use the `-u` flag to let `resubmit.py` know:

```
% python path/to/dist_qsub/resubmit.py -u [number_of_updates]
```

This will create a new run_list file called `run_list_resubmit` that you can submit with dist_qsub.py to re-run jobs that failed.

The full sequence of commands to resubmit runs that died:
```
% python path/to/dist_qsub/cleanup.py
% python path/to/dist_qsub/resubmit.py
% python path/to/dist_qsub/dist_qsub.py run_list_resubmit
```
(do this from the dest_dir in your original run_list)

If your experiments were almost done before they died (and you were using checkpointing), you might want to attempt to restart them from checkpoint files. To do this, add the `-c` flag (e.g. `% python path/to/dist/qsub/resubmit-py -c`). This will create a run_list_resubmit file that only includes jobs for directories that have checkpoint files. It also sets "cpr" in the header of that run_list to 1 to tell dist_qsub to restart from existing checkpoints. Note that if there is something wrong with your checkpoint file, your runs will fail again. If you also have jobs that failed before creating checkpoints, you can make a complementary run_list that only includes runs that didn't finish and do not have checkpoints by running resubmit.py with the `-n` flag.

`resubmit.py` can also be used to verify that all of your runs finished. Just run it from the directory containing all of the directories from each run (dest_dir) and if the run_list is empty, then everything is done. By default, `resubmit.py` checks that each run went to 100,000 updates. If you wanted Avida to run for a different amount of time, specify it with the `-u` flag. If any of your runs went extinct before reaching the final update (i.e. the population went to zero), their names will be stored in the file `extinct`.

Sometimes something really bad happens, and you have an entire replicate that didn't even start. In this case, `resubmit.py` can't tell you were trying to run it at all. If you want `resubmit.py` to try to make inferences about which directories are missing, you can turn on the -i (infer missing) flag. WARNING: This is super experimental. If you turn on -i, you should also how many replicates of each condition you have with the -r flag. For instance, if you have 30 replicates per condition, you can try running:

```
% python path/to/dist_qsub/resubmit.py -i -r 30
```

WARNING: `resubmit.py` is only intended to be used when runs died because of a checkpointing error or HPCC problem. You should always make sure that your runs didn't die of an error in Avida (perhaps because of your config settings), because that will just keep happening no matter how many times you resubmit.


If you accidentally resubmit things that you didn't mean to, your directories will be stored in backup directories, ending in "_bak". To restore them to their original names, you can use the restore_backups script:
```
% path/to/dist_qsub/restore_backups.sh
```
(run this from the directory containing the directories for all of your runs)


# Useful bash commands

There are a variety of bash commands that can be helpful in manipulating large quantities of jobs. Here are some of them (if you have more, pull requests are welcomed!):

#### Check progress

It's often nice to know how your jobs are progressing. You can get a quick status report by looking at the last lines of all of the run.log files. From the dest_dir in your run_list, run:
```
for filename in */run.log;
do
  tail -1 $filename;
done
```

Want to know which line belongs to which file? Print out the filename too:
```
for filename in */run.log;
do
  echo $filename;
  tail -1 $filename;
done
```

Have a lot of jobs and just want an over-all summary of how many are done? Combine the for loop with grep and wc (word count)! For instance, if all of your jobs output the current time step and you want them to get to time step 1000, you could use:
```
for filename in */run.log; do tail -1 $filename; done | grep 1000 | wc -l
```

Want to know if any of your runs died? This can get a little challenging, since dist_qsub can recover from most crashes that the HPCC would e-mail you about, and simply counting the number of jobs in your queue can be ineffective with all of the placeholder jobs. The most straightforward way is to append a message to the end of the run.log file and then check back later to see if its still the last line. Of course, you don't want to do this to jobs that are already done. This script will append a line that says "running" to the end of all run.log files that are not done yet. In order for it to do this, it needs you to tell it what to look for in the last line of the run.log file to know the run is done (here it is looking for "1000" - replace "1000" with whatever you want to check for). It should be run from the dest_dir in your run_list:
```
for filename in */run.log;
do
  done=`tail -1 $filename | grep 1000 | wc -l`;
  if [ $done -ne 1 ];
  then
    echo "running" > $filename;
  fi;
done
```
A bit later, you can check for any jobs that haven't written new lines to their run.log file with:

```
for filename in */run.log; do tail -1 $filename; done | grep running | wc -l
```
This will give you the count of jobs that are not currently running (assuming you waited long enough that all of your runs should have printed another line). Note that just because a job isn't currently running doesn't necessarily mean it won't recover. If, however, a job does not recover for over 4 hours, has failed before its first checkpoint, or no other jobs in its group of seeds are running then something has gone wrong and it will need to be manually restarted.

#### Delete all jobs from a specific group
Did you just learn that there's an error in your executable? Screw up your configs? There are many cases where you might want to kill all of the jobs from a specific experiment without affecting other jobs you ay be running. In these cases, you can go to the dest_dir specified in the run_list for those jobs and run the following commands (warning: this will kill all of the jobs writing to that destination directory, so make sure that's what you want):
```
cd qsub_files
for line in `cat *successor_jobs.txt` ; do echo $line[]; done | xargs qdel
```
This may produce some warnings about nonexistant job ids, but that's okay.

If you don't want to kill **all** jobs corresponding to that destination directory, you can add a more specific pattern before "`*successors_jobs.txt`". For example, if your run_list had three conditions named mutationrate_.01, mutationrate_.001, and mutationrate_.0001 and you only wanted to kill jobs from the last two, you could use ```for line in `cat mutation_rate_.00*successor_jobs.txt` ; do echo $line[]; done | xargs qdel```

Note, this will only work if you are running your jobs in checkpoint mode as it takes advantage of the extra book-keeping that checkpointing requires.

#### Get a list of qsub files without any jobs running
Recovery mechanisms only work if there is at least 1 job from an array running. To get a list of all qsub files that no longer have any associated jobs running, run this command in your `qsub_files` directory:

```
for filename in *successor_jobs.txt; 
do 
  count=0; 
  for line in `cat $filename`; 
  do 
    count=`expr $count + $(qs | grep $line | wc -l)`;
  done; 
  if [[ $count == 0 ]]; 
  then 
    echo "$filename is no longer running"; 
  fi; 
done
```

You can then compare this list against the jobs that are actually done.

#### Restore backups
When you submit jobs that write to directories that already exist, dist_qsub will move the existing directories to new directories with ```_bak``` appended to the end of their names so that you don't lose data. But sometimes you didn't mean to submit that new job in the first place and would like to rename the backup directories to have their original names. If you delete the newly created directories that you don't want, you can use the `restore_backups.sh` script in this repository to move all backup directories back to their original names. Specifically, it will move directories with names like `xyz_bak` to the corresponding original name (`xyz`, in this case) if and only if there is not already a directory with that name. restore_backups should be run from the dest_dir that has the backups you are trying to restore.

# Notes on recovering from checkpoint failures

There are a number of things that can go wrong with checkpointing. As such, there are a number of layers of recovery built in:

* Sometimes the process of creating a checkpoint fails for inexplicable reasons. This generally results in a corrupted `checkpoint.blcr` file. To combat this, dist_qsub always maintains a backup checkpoint file in `checkpoint_safe.blcr` (with the exception that there can't be a backup the first time the job is checkpointed). If restarting from the main checkpoint file fails, this backup will be tried.
* Sometimes the job restarts on a node that is not compatible with the node it was running on beforehand. This usually reuslts in a seg-fault on checkpoint restart. Setting features=intel16 or features=intel14 (accomplished by setting class_pref to 150 or 200 in the run_list file) dramatically reduces the possibility of this happening, but there are still a few different node types within those groups, some of which are incompatible. It's possible there is a more precise set of features that can be requested to prevent this. For now, if both the main checkpoint and the backup checkpoint fail, the job will resubmit itself up to two times in hopes of winding up on a more appropriate node.
* Sometimes something unexpected happens and a job just dies. To recover from this, when the new set of jobs is created at the end of four hours, dist_qsub checks for any sub-jobs that are not yet completed but are also not running. If it finds any, it restarts them.

If all of this fails, you may need to resubmit your jobs manually. You can do this using resubmit.py, as described above. You can also manually create a run_list file containing the jobs you want to resubmit. If you want these jobs to restart from existing checkpoint files, rather than starting over from the beginning, add `set cpr 1` to the header of this run_list file.

Advanced note: In some situations, it may be most expedient to just resubmit an individual qsub file generated by dist_qsub.py. If you want it to restart fro an existing checkpoint file change `export CPR=0` at the top to `export CPR=1`.

# Development notes

dist_qsub uses Berkley Labs Checkpoint Restart (BLCR) to automatically checkpoint and restart long runs of Avida. The basics of this concept are explained in [this tutorial by ICER](https://wiki.hpcc.msu.edu/pages/viewpage.action?pageId=5414426). There are three complications in simply useing the longjob.sh script developed by ICER. 1) The run_list format used by the dist_run program is what most Avida users are used to, and is also more convenient for the Avida use case specifically, 2) In Avida experiments, we almost always run chunks of jobs that differ only by random seed (so we can do stats on different treatments); it's more efficient to run these types of jobs as, in HPCC terminology, "array jobs.", and 3) users on the HPCC have a limited number of jobs that they can have in their queue at any given point in time.

dist_qsub seeks to resolve all three of these issues. The primary goal of the dist_qsub.py script is to translate `run_list`-style files into `.qsub` files, of the format accepted by the HPCC scheduler (PBS/TORQUE/Moab). These files get stored in a `qsub_files` directory inside the `dest_dir` specified in the run_list. Storing it there ensures that different experiments can't conflict with each other. For the most part, these files set some environment variables and then run a modified version of longjob.sh (dist_longjob.sh).

Based on the environment variables, dist_longjob.sh either configures the directory and starts the job, or immediately restarts from an existing checkpoint file. Then it sets a timer for just under the allowed walltime and waits. If the job finished, it records this in the dest_dir/qsub_files/qsub_file_name_donearray_jobs.txt file. If the job isn't done after the timer is up, it needs to be resubmitted. The tricky part is that whereas longjob.sh works be resubmitting a copy of itself after the time is up, dist_longjob.sh has to make sure that one new array of jobs is submitted per array that finishes. So one job in the array (generally the first to finish) is made responsible for this. All jobs in the array that don't have a finished predecessor yet are put in the "hold" state and released by the corresponding job when it finishes. As a result, it's possible for some jobs in the array to get far ahead of others, resulting in a lot of waiting jobs. The list of job ids associated with a given line in the run_list file is stored in dest_dir/qsub_files/qsub_file_name_successor_jobs.txt.

The final component of dist_qsub is a scheduler (scheduler.py) that keeps track of which arrays are completely done and which ones have yet to be run. When an array finishes, if there is space in the queue (as indicated by the MAX_QUEUE variable), a new array (i.e. a new line from the original run_list) is submitted. It's important to be conservative when determining if there is space in the queue, because creating arrays for jobs that aren't finished running yet means that a single run of avida can take up many spots in the queue. If this causes the queue to fill up, confusing errors can result. The default MAX_QUEUE is set to be the maximum number of jobs a user is allowed to have running at once (which is conveniently around half of the cap of 1000 on the number of total jobs you are allowed to have queued.
