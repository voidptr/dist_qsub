dist_qsub
=========

HPCC DevoLab dist_run replacement

Before running, make sure a run_list file is in the directory along with a "config/"
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

dist_qsub can now handle an indefinite number of jobs by maintaining a pool of jobs to submit when space opens up. To add things to this pool when you've already got jobs running, put the new jobs into a run_list file and submit them (from the same directory you submitted the first set of jobs from) with:
```
% python path/to/dist_qsub/dist_qsub.py -p
```

If the number of jobs in queue (i.e. the total that shows up at the bottom of the output from showq -u [yourusername]) is low (< ~50), you can add more things by going to your `dest_dir/qsub_files` directory and manually submitting them (don't put more than ~540 total jobs in your queue) (dest_dir is the location your results are being stored in):

```
% cd dest_dir/qsub_files
% qsub [name_of_qsub_file.qsub]
```

# Resubmitting

Sometimes runs die. It is a fact of life. `resubmit.py` can help you figure out which runs died, and painlessly re-run them. It will look at your output files and make sure that that output files for all of your conditions go to the correct number of updates. By default, `resubmit.py` assumes the correct number of updates is 100,000. If you ran your experiments for a different length of time, you should use the `-u` flag to let `resubmit.py` know:

```
% python path/to/dist_qsub/resubmit.py -u [number_of_updates]
```

The full sequence of commands to resubmit runs that died:
```
% python path/to/dist_qsub/cleanup.py
% python path/to/dist_qsub/resubmit.py
% python path/to/dist_qsub/dist_qsub.py
```
(do this from the dest_dir in your original run_list)

`resubmit.py` can also be used to verify that all of your runs finished. Just run it from the directory containing all of the directories from each run (dest_dir) and if the run_list is empty, then everything is done. By default, `resubmit.py` checks that each run went to 100,000 updates. If you wanted Avida to run for a different amount of time, specify it with the `-u` flag. If any of your runs went extinct before reaching the final update (i.e. the population went to zero), their names will be stored in the file `extinct`.

Sometimes something really bad happens, and you have an entire replicate that didn't even start. In this case, `resubmit.py` can't tell you were trying to run it at all. If you want `resubmit.py` to try to make inferences about which directories are missing, you can turn on the -i (infer missing) flag. WARNING: This is super experimental. If you turn on -i, you should also how many replicates of each condition you have with the -r flag. For instance, if you have 30 replicates per condition, you can try running:

```
% python path/to/dist_qsub/resubmit.p -i -r 30
```

WARNING: `resubmit.py` is only intended to be used when runs died because of a checkpointing error or HPCC problem. You should always make sure that your runs didn't die of an error in Avida (perhaps because of your config settings), because that will just keep happening no matter how many times you resubmit.

If you accidentally submit things that you didn't mean to, your directories will be stored in backup directories, ending in "_bak". To restore them to their original names, you can use the restore_backups script:
```
% path/to/dist_qsub/restore_backups.sh
```
(run this from the directory containing the directories for all of your runs)
