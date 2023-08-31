#!/bin/sh
synoschedtask --get | grep 'Name:\|CmdArgv' | grep -B2 'dsmbackup' | grep -v 'AppName' 
