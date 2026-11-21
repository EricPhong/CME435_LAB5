# Invoked by script/run.csh after compilation.
# 1. Check Tcl variable first, then shell environment variable, then fallback
if {[info exists TESTNAME] && $TESTNAME ne ""} {
    # Taken from Tcl command-line 'set TESTNAME ...'
} elseif {[info exists env(TESTNAME)] && $env(TESTNAME) ne ""} {
    set TESTNAME $env(TESTNAME)
} else {
    set TESTNAME "pdm_test_base"
}

echo "=========================================================="
echo "  RUN.DO: Launching UVM test: $TESTNAME"
echo "=========================================================="

# 2. Load the compiled DUT/UVM test and pass the standard UVM plusarg
#    Lab 5: -coverage enables coverage collection for this simulation.
#    -wlf names the wave database so waves can be reviewed after the run:
#        vsim -view waves/<test>.wlf
file mkdir coverage waves
vsim -coverage -L mtiUvm work.top +UVM_TESTNAME=$TESTNAME +UVM_NO_RELNOTES -wlf waves/$TESTNAME.wlf

# 3. Dump all signals to the WLF (batch AND GUI) so waves exist after the test
log -r /*

# Add waves to the Wave window if GUI mode was requested
if {[info exists env(PDM_GUI)] && $env(PDM_GUI) eq "1"} {
    add wave -r sim:/top/*
}

# 4. Lab 5: save the coverage database when the simulator exits.
#    Must be registered BEFORE run -all: once $finish ends the run, lines after
#    run -all may never execute.
coverage save -onexit coverage/$TESTNAME.ucdb

run -all

# 5. Exit if running in batch mode
if {![info exists env(PDM_GUI)] || $env(PDM_GUI) ne "1"} {
    quit -f
}