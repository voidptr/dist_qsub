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

(do this from the location you submitted the jobs from)

To resubmit runs that died:
```
% python path/to/dist_qsub/cleanup.py
% python path/to/dist_qsub/resubmit.py
% python path/to/dist_qsub/dist_qsub.py
```
(do this from the dest_dir in your original run_list)

dist_qsub can now handle an indefinite number of jobs by maintaining a pool of jobs to submit when space opens up. To add things to this pool when you've already got jobs running, put the new jobs into a run_list file and submit them (from the same directory you submitted the first set of jobs from) with:
```
% python python path/to/dist_qsub/dist_qsub.py -p
```

If you accidentally submit things that you didn't mean to, your directories will be stored in backup directories, ending in "_bak". To restore them to their original names, you can use the restore_backups script:
```
% python path/to/dist_qsub/restore_backups.sh
```
(run this from the directory containing the directories for all of your runs)
