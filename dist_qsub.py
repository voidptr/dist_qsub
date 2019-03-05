#!/usr/bin/python

##########################
# Read the run_list file
##########################

# system includes
import glob
import os
from optparse import OptionParser
import sys
import time
from os.path import expanduser, abspath

# Set up options
usage = """usage: %prog [options] [run_list]

In the run_list file, currently supported "set" options are:

  email - (required) the email address for HPCC messages (crashes only)
  email_when - [default: final, always] email when the whole job finishes only (default), or an email for every sub-job ("always"). Note, these emails only go to USERNAME@msu.edu. Sorry.
  class_pref - supported classes 91, 92, 95, 150 (intel14), 200 (intel16)
  walltime - ints only, in hours
  mem_request - in gigabytes
  dest_dir - (required) the path to the output directory
  cpr - [default: 0] are these jobs being restarted from existing checkpoints (can be 0 (False) or 1 (True))
  config_dir - the path to a directory that contains configuration files. Will be copied into working directory before run.
  ppn - the number of cores to request (default 1)
"""
parser = OptionParser(usage)
parser.add_option("-p", "--printonly", action="store_true", dest="printonly",
                  default = False, help = "only print the qsub file (DELETE.ME), without submitting.")
parser.add_option("-v", "--verbose", action = "store_true", dest = "verbose",
                  default = False, help = "print extra messages to stdout")
parser.add_option("-d", "--debug_messages", action = "store_true",
                  dest = "debug_messages",
                  default = False, help = "print debug messages to stdout")
parser.add_option("-c", "--checkpoint", action = "store_true",
                  dest="checkpoint", default=True, help="apply checkpointing.")
parser.add_option("--nocheckpoint", action = "store_true",
                  dest="nocheckpoint", default=False, help="do NOT apply checkpointing.")


parser.add_option("-m", "--max-queue", action = "store",
                  dest="max_queue", default=535,
    help="How many jobs should be queued before invoking additional scheduler?")
## fetch the args
(options, args) = parser.parse_args()

run_list = "run_list"
if (len(args) > 0):
    run_list = args[0]

if run_list[-3:] == ".gz":
    fd = gzip.open(run_list)
else:
    fd = open(run_list)

dist_qsub_dir = os.path.dirname(os.path.realpath(__file__))

settings = {}
processes = []
for line in fd:

    if line.find('#') > -1:
        line = line[:line.find('#')]

    line = line.strip().lstrip() ## strip off the leading and following whitespace.

    if len(line) == 0 or line[0] == "#":
        continue

    if (line[:3] == "set"):
        bits = line.split(" ");
        settings[bits[1]] = bits[2];
    else:
        processes.append(line.split(" ", 2))
if options.debug_messages:
    for command in processes:
        print command

if not "email" in settings.keys():
    parser.error("email must be defined in run_list")

if not "dest_dir" in settings.keys():
    parser.error("dest_dir must be defined in run_list")

if not "cpr" in settings.keys():
    settings["cpr"] = "0"

if not "ppn" in settings.keys():
    settings["ppn"] = "1"

for command in processes:
    bits = command[2].split(";")
    newcomm = []
    for bit in bits:
#        if options.checkpoint:
#            newcomm.append(bit.lstrip())
#        else:
        newcomm.append(bit.lstrip())

    command[2] = ";".join(newcomm)


feature_string = ""

#p_string = []
#if ('ppn' in settings.keys()):
#    p_string.append( "ppn=" + settings['ppn'] )
#if ('nodes' in settings.keys()):
#    p_string.append( "nodes=" + settings['nodes'] )
#if len(p_string) > 0:
#    l_string.append( ":".join(p_string) )

feature = []
if ('feature' in settings.keys()):
    feature = settings['feature'].split(',')

if ('class_pref' in settings.keys()):
    if settings['class_pref'] == '91': # amd05
        feature.append("amd05")
    elif settings['class_pref'] == '92': # intel07
        feature.append("intel07")
    elif settings['class_pref'] == '95': # intel10
        feature.append("intel10")
    elif settings['class_pref'] == '150': # intel14
        feature.append("css|csp|csn|csm")
    elif settings['class_pref'] == '200': # intel16
        feature.append("intel16")
    elif settings['class_pref'] == "lac": # intel16
        feature.append("lac")

if len(feature) > 0:
    feature_string = "--constraint=" + "|".join(feature)

config_dir = "config"
if ('config_dir' in settings.keys()):
    config_dir = settings['config_dir']
    config_dir.replace("~", expanduser("~"))

config_dir = os.path.abspath(config_dir)

dest_dir = settings['dest_dir']
dest_dir.replace("~", expanduser("~"))
dest_dir = os.path.abspath(dest_dir)

if ('walltime' in settings.keys()):
    hours = int(float(settings['walltime']))
    remaining_fraction = float(settings['walltime']) - hours
    minutes = int(remaining_fraction * 60)
    seconds = int(((remaining_fraction * 60) - minutes) * 60)
    walltime = str(hours) + ":" + str(minutes).zfill(2) + ":" + str(seconds).zfill(2)
else:
    walltime = "00:01:00"



if ('mem_request' in settings.keys()):
    # l_string.append( "mem=" + str(int(float(settings['mem_request']) * 1024)) + "mb" )
    mem = str(int(float(settings['mem_request']) * 1024)) + "mb"
else:
    mem = "750m"

email_when = "final"
if 'email_when' in settings.keys() and settings['email_when'] == "always":
    email_when = "always"

# Email notifications are now broken, since slurm doesn't seem to have an epilogue.
# We'll need to investigate new options

script_template_basic = """#!/bin/bash -login
#SBATCH %features%
#SBATCH -c %ppn% --mem=%mem%
#SBATCH -J %jobname%
#SBATCH --time=%time%                 # Walltime
#SBATCH --mail-user=%email_address%
#SBATCH --output=%dest_dir%/%jobname%_message.log-%a
#SBATCH --array=%job_seeds%

DIST_QSUB_DIR=%dist_qsub_dir%
QSUB_DIR=%qsub_dir%
QSUB_FILE=%qsub_file%
MAX_QUEUE=%max_queue%

TARGETDIR=%dest_dir%
STARTSEED=%start_seed%
seed=$(($STARTSEED + $SLURM_ARRAY_TASK_ID))
JOBTARGET=%jobname%"_"$seed

#echo "seed="$seed "jobtarget="$JOBTARGET "targetdir="$TARGETDIR "slurm_arrayid="$SLURM_ARRAY_TASK_ID "slurm_jobname="$SLURM_JOBNAME "tmpdir="$TMPDIR;

#change directory to the directory this was run from
cd $SLURM_SUBMIT_DIR
mkdir $TMPDIR/$JOBTARGET
cp -r %config_dir%/* $TMPDIR/$JOBTARGET
cd $TMPDIR/$JOBTARGET

%job_command%

mkdir $TARGETDIR/$JOBTARGET

gzip -r .
tar czf dist_transfer.tar.gz .

mv dist_transfer.tar.gz $TARGETDIR/$JOBTARGET
cd $TARGETDIR/$JOBTARGET
tar xzf dist_transfer.tar.gz
rm dist_transfer.tar.gz
gunzip -r .

cp ${QSUB_FILE} ${QSUB_FILE}_done
echo "${QSUB_FILE} is done"

#remove lock file
rm ${QSUB_FILE}_done.lock 2> /dev/null
echo "Lock removed"

#remove original qsub file so we don't have to keep trying to submit it
rm ${QSUB_FILE} 2> /dev/null
echo "Original qsub file removed"

echo "Checking to see if there are more jobs that should be started"

qstat -f ${SLURM_ARRAY_JOB_ID} | grep "used"
export RET

# Make sure not to submit too many jobs
current_jobs=$(showq -u `whoami` | tail -2 | head -1 | cut -d " " -f 4)
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

"""

script_template_checkpointing = """#!/bin/bash -login
 
## resource requests for task:
#SBATCH -J %jobname%                  # Job Name
#SBATCH --time=%time%                 # Walltime
#SBATCH -c %ppn% --mem=%mem%          # Requested resource
#SBATCH %features%                    # Set feature requests
#SBATCH --mail-user=%email_address% 
#SBATCH --output=%dest_dir%/%jobname%_message.log-%a
#SBATCH --array=%job_seeds%
 
export PPN=%ppn%
export MEM=%mem%
export TIME=%time%
export MAILUSER=%email_address%
export TARGETDIR=%dest_dir%
export STARTSEED=%start_seed%
export seed=$(($STARTSEED + $SLURM_ARRAY_TASK_ID))
export JOBTARGET=%jobname%"_"$seed
export JOBNAME=%jobname%
export JOBSEEDS=%job_seeds%
export DEST_DIR=%dest_dir%
export CONSTRAINT='%features%'
export JOBCOMMAND='%job_command%'
export CONFIGDIR=%config_dir%
export EMAILSCRIPT=/mnt/research/devolab/dist_qsub/email_%email_when%.sh
export USESCRATCH=%use_scratch%
export DIST_QSUB_DIR=%dist_qsub_dir%
export QSUB_DIR=%qsub_dir%
export QSUB_FILE=%qsub_file%
export MAX_QUEUE=%max_queue%
export CPR=0

%dist_qsub_dir%/dist_longjob.sh
"""

if not os.path.exists(settings['dest_dir']):
    os.makedirs(settings['dest_dir'])

def strdiff(str1, str2):
    for i in range(len(str1)):
        if str1[i] != str2[i]:
            return i

script_template = script_template_basic
if options.checkpoint and not options.nocheckpoint:
    script_template = script_template_checkpointing

script_template = script_template.replace( "%features%", feature_string)
script_template = script_template.replace( "%email_address%", settings['email'])
script_template = script_template.replace( "%email_when%", email_when)
script_template = script_template.replace( "%dest_dir%", dest_dir )
script_template = script_template.replace( "%qsub_dir%", dest_dir+"/qsub_files" )
script_template = script_template.replace( "%config_dir%", config_dir )
script_template = script_template.replace( "%dist_qsub_dir%", dist_qsub_dir)
script_template = script_template.replace( "%max_queue%", str(options.max_queue))
script_template = script_template.replace( "%cpr%", settings["cpr"])
script_template = script_template.replace( "%ppn%", settings["ppn"])
script_template = script_template.replace( "%time%", walltime)
script_template = script_template.replace( "%mem%", mem)


if not os.path.exists(dest_dir):
    os.mkdir(dest_dir)

if not os.path.exists(dest_dir+"/qsub_files"):
    os.mkdir(dest_dir+"/qsub_files")

submitted = 0

for command in processes:
    command_final = script_template
    command_final = command_final.replace( "%jobname%", command[1] )
    command_final = command_final.replace( "%job_command%", command[2] )

    job_seeds = ""
    start_seed = 0
    job_ct = 0
    if (".." in command[0]):
        (start_seed, end_seed) = [ int(v) for v in command[0].split("..") ]
        job_ct = end_seed - start_seed
        job_seeds = "0-"+str(job_ct) # inclusive

        if job_ct > 99999 or job_ct < 1:
            exit("Seeds defined in " + command[0] + " are negative or invalid")
        if job_ct > 100 and not options.nocheckpoint:
            exit("DO NOT USE CHECKPOINTING WITH ARRAYS LARGER THAN 100!!! Reduce number of treatments per condition or use the --nocheckpoint flag")

        command_final = command_final.replace( "%start_seed%", str(start_seed))
        command_final = command_final.replace( "%job_seeds%", job_seeds)
    else:
        start_seed = int(command[0])
        job_ct = 1
        job_seeds = "0"

        command_final = command_final.replace( "%start_seed%", str(start_seed))
        command_final = command_final.replace( "%job_seeds%", job_seeds)

    # clean up the target directories
    for i in range(job_ct+1):
        jobtarget = settings['dest_dir'] + "/" + command[1] + "_" + str(start_seed + i)
        if os.path.exists(jobtarget) and settings['cpr'] == "0":
            os.system("mv " + jobtarget + " " + jobtarget + "_bak")

    qsub_file = dest_dir+"/qsub_files/"+str(command[1])+"_"+str(command[0]+".qsub")

    command_final = command_final.replace("%qsub_file%", qsub_file)

    os.system("rm {0}*".format(qsub_file))
    f = open(qsub_file, "w")
    f.write(command_final)
    f.close()

    if not options.printonly and submitted <= options.max_queue:
        print "Submitting: " + command[1]
        os.system("sbatch {0}".format(qsub_file))
        with open(qsub_file+"_done.lock", "wb") as lockfile:
            lockfile.write("submitted by dist_qsub")

    time.sleep(2)
    submitted += job_ct
