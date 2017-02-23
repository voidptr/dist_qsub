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
  class_pref - supported classes 91, 92, 95, 150
  walltime - ints only, in hours
  mem_request - in gigabytes
  dest_dir - (required) the path to the output directory

Currently unsupported, but planned options:
  config_dir

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
    help="How many jobs should be queued beforeinvoking additional scheduler?")
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

for command in processes:
    bits = command[2].split(";")
    newcomm = []
    for bit in bits:
#        if options.checkpoint:
#            newcomm.append(bit.lstrip())
#        else:
        newcomm.append(bit.lstrip() + " 2>&1 | cat >> run.log")

    command[2] = ";".join(newcomm)


l_string = []

#p_string = []
#if ('ppn' in settings.keys()):
#    p_string.append( "ppn=" + settings['ppn'] )
#if ('nodes' in settings.keys()):
#    p_string.append( "nodes=" + settings['nodes'] )
#if len(p_string) > 0:
#    l_string.append( ":".join(p_string) )

feature = []
if ('feature' in settings.keys()):
    feature_str = settings['feature'].split(',')
    for ftr in feature_str:
        feature.append("feature=" + ftr)

if ('class_pref' in settings.keys()):
    if settings['class_pref'] == '91': # amd05
        feature.append("feature=amd05")
    elif settings['class_pref'] == '92': # intel07
        feature.append("feature=intel07")
    elif settings['class_pref'] == '95': # intel10
        feature.append("feature=intel10")
    elif settings['class_pref'] == '150': # intel14
        feature.append("feature=intel14")

if len(feature) > 0:
    l_string.append(":".join(feature))

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
    l_string.append( "walltime=" + str(hours) + ":" + str(minutes).zfill(2) + ":" + str(seconds).zfill(2) )
if ('mem_request' in settings.keys()):
    l_string.append( "mem=" + str(int(float(settings['mem_request']) * 1024)) + "mb" )

email_when = "final"
if 'email_when' in settings.keys() and settings['email_when'] == "always":
    email_when = "always"


script_template_basic = """
#!/bin/bash -login
#PBS -q main
#PBS -l %lstring%
#PBS -N %jobname%
#PBS -o %dest_dir%/%jobname%_message.log
#PBS -j oe
#PBS -t %job_seeds%
#PBS -M %email_address%
#PBS -l epilogue=/mnt/research/devolab/dist_qsub/email_%email_when%.sh

TARGETDIR=%dest_dir%
STARTSEED=%start_seed%
seed=$(($STARTSEED + $PBS_ARRAYID))
JOBTARGET=%jobname%"_"$seed

#echo "seed="$seed "jobtarget="$JOBTARGET "targetdir="$TARGETDIR "pbs_arrayid="$PBS_ARRAYID "pbs_jobname="$PBS_JOBNAME "tmpdir="$TMPDIR;

#change directory to the directory this was run from
cd $PBS_O_WORKDIR
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
"""

script_template_checkpointing = """
#!/bin/bash -login
#PBS -q main
#PBS -l %lstring%
#PBS -N %jobname%
#PBS -o %dest_dir%/%jobname%_message.log
#PBS -j oe
#PBS -t %job_seeds%
#PBS -M %email_address%

export TARGETDIR=%dest_dir%
export STARTSEED=%start_seed%
export seed=$(($STARTSEED + $PBS_ARRAYID))
export JOBTARGET=%jobname%"_"$seed
export JOBNAME=%jobname%
export JOBSEEDS=%job_seeds%
export DEST_DIR=%dest_dir%
export LSTRING="%lstring_spaces%"
export JOBCOMMAND="%job_command%"
export CPR=%cpr%
export CONFIGDIR=%config_dir%
export EMAILSCRIPT=/mnt/research/devolab/dist_qsub/email_%email_when%.sh
export USESCRATCH=%use_scratch%
export DIST_QSUB_DIR=%dist_qsub_dir%
export QSUB_DIR=%qsub_dir%
export QSUB_FILE=%qsub_file%
export MAX_QUEUE=%max_queue%

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

script_template = script_template.replace( "%lstring%", ",".join(l_string))
script_template = script_template.replace( "%lstring_spaces%", " ".join(l_string))
script_template = script_template.replace( "%email_address%", settings['email'])
script_template = script_template.replace( "%email_when%", email_when)
script_template = script_template.replace( "%dest_dir%", dest_dir )
script_template = script_template.replace( "%qsub_dir%", dest_dir+"/qsub_files" )
script_template = script_template.replace( "%config_dir%", config_dir )
script_template = script_template.replace( "%dist_qsub_dir%", dist_qsub_dir)
script_template = script_template.replace( "%max_queue%", str(options.max_queue))
script_template = script_template.replace( "%cpr%", settings["cpr"])


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
        os.system("qsub {0}".format(qsub_file))
        with open(qsub_file+"_done.lock", "wb") as lockfile:
            lockfile.write("submitted by dist_qsub")

    time.sleep(2)
    submitted += job_ct
