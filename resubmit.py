import glob, os, re, sys, shutil
from optparse import OptionParser
#This script searches the current working directory for runs that did not
#get to the number of updates specified by the first command-line argument
#and creates a new run_list file to resubmit all of them. If any runs ended
#early due to natural causes (i.e. the population went to 0), they are not
#resubmitted and are instead recorded in the "extinct" file.

parser = OptionParser()

parser.add_option("-u", "--updates", action="store", dest="updates", default="100000", type="string", help="The number of updates each run should have gone for (default: 100000)")
parser.add_option("-r", "--reps", action="store", dest="reps", default=10, type="int", help="The number of random seeds runs per condition (default: 10)")
parser.add_option("-c", "--checkpoint", action="store_true", dest="cpr", default=False, help="Restart from checkpoint? WARNING: Only resubmits runs with valid checkpoint")
parser.add_option("-n", "--nocheckpoint", action="store_true", dest="nocpr", default=False, help="Only include runs without a checkpoint - i.e. those missed by running this with the -c flag")
parser.add_option("-i", "--infer-missing", action="store_true", dest="infer", default=False, help="Use specified number of reps to find probably missing runs. Experimental.")

(options, args) = parser.parse_args()

run_list = open("run_list", "wb")
extinct = open("extinct", "wb")

header = "set description conservation\nset email dolsonem@msu.edu\nset email_when final\nset class_pref 95\nset walltime 4\nset mem_request 4\nset config_dir config\nset dest_dir " + os.getcwd() + "\n"

if options.cpr == 1:
    header += "set cpr 1\n"

header += "\n"

run_list.write(header)

conditions = {}

run_logs = glob.glob("./*/run.log")
extinct_list = []
not_resubmitted = []

for run in run_logs:
    if "_bak" in run:
        continue

    with open(run) as logfile:
        end = logfile.readlines()[-1].split()            
        pop = end[-1]
        ud = end[1]

        rep = run.split("/")[-2]
        split_condition = rep.split("_")
        seed = split_condition[-1]
        condition = "_".join(split_condition[:-1])
        condition = condition.strip("./ ")

        if condition in conditions:
            conditions[condition]["found_seeds"].append(int(seed))
        else:
            conditions[condition] = {}
            conditions[condition]["seeds"] = []
            conditions[condition]["found_seeds"] = [int(seed)]
            conditions[condition]["name"] = condition

            command_file = open(rep+"/command.sh")
            command = command_file.readlines()[1]
            split_command = command.split()
            split_command[2] = "$seed"
            command = " ".join(split_command)
            command_file.close()

            conditions[condition]["command"] = command

        if ud != options.updates: 
            if pop == "0":
                extinct_list.append(rep)
                continue
        
            if os.path.exists(rep+"/checkpoint_safe.blcr") and options.cpr:
                shutil.copy(rep+"/checkpoint_safe.blcr", rep+"/checkpoint.blcr")
            elif options.cpr:
                print "Not resubmitting", rep, "because there's no checkpoint."
                not_resubmitted.append(rep)
                continue
            elif os.path.exists(rep+"/checkpoint_safe.blcr") and options.nocpr:
                print "Not resubmitting", rep, "because there's a checkpoint."
                not_resubmitted.append(rep)
                continue

            print "resubmit: ", rep      
            conditions[condition]["seeds"].append(int(seed))


                
for condition in conditions:

    found_seeds = conditions[condition]["found_seeds"]
    seeds = conditions[condition]["seeds"]
    name = conditions[condition]["name"]
    command = conditions[condition]["command"]

    if options.infer and len(found_seeds) < options.reps:
        found_seeds.sort()
        print len(found_seeds), options.reps, found_seeds

        all_seeds = range(found_seeds[0], found_seeds[-1]+1)

        if len(all_seeds) < options.reps:
            #Ewww, we have to do this the hard way
            print "Warning: Speculative inference for", condition
            best = max(conditions.values(), key=lambda x: len(x["found_seeds"]))
            best = best["found_seeds"]
            if len(best) < options.reps:
                #Well this isn't going to work
                print "Inference failed for", condition, " - no conditions have the right number of directories"
            else:
                best.sort()
                if min(best) > all_seeds[-1]:
                    curr = min(best)
                    while curr > all_seeds[-1]:
                        curr -= options.reps
                    all_seeds = range(curr, curr+options.reps)
                else:
                    curr = max(best)
                    while curr < all_seeds[0]:
                        curr += options.reps
                    all_seeds = range(curr-options.reps+1, curr+1)
                
        add_seeds = set(all_seeds) - set(found_seeds)
        print "Inferred missing seeds:", condition, add_seeds

        seeds += add_seeds
    
    elif len(found_seeds) != options.reps:
        print "Warning! Wrong number of reps found for", condition, "Expected:", options.reps, "Found:", len(found_seeds)

                

    seeds.sort()
    first = 0
    second = 0
    while second < len(seeds) and first < len(seeds):
        second = first
        while second < len(seeds) - 1 and int(seeds[second])+1 == int(seeds[second+1]):
            second += 1
            
        #We have isolated a chunk of numbers

        if second == first:
            run_list.write(str(seeds[first]) + " " + name + " " + command + "\n")
        else:
            run_list.write(str(seeds[first])+".."+str(seeds[second]) + " " + name + " " + command + "\n")
                        
        first = second + 1

extinct.write("\n".join(extinct_list))
