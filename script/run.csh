#!/bin/csh -f

# =========================================================
# 1. Directory Setup (Run safely from any directory)
# =========================================================
set SCRIPT_DIR = `dirname "$0"`
set SCRIPT_DIR = `cd "$SCRIPT_DIR" && pwd`
set PROJECT_DIR = `cd "$SCRIPT_DIR/.." && pwd`
set VERIF_DIR = "$PROJECT_DIR/verification"
set DUT_DIR = "$PROJECT_DIR/dut"

# Sourcing QuestaSim environment setup
source /CMC/scripts/siemens.questasim.2022.1_2.csh

# =========================================================
# 2. Command Line Arguments Handling
# =========================================================
set TEST_NAME = "pdm_sanity_test"
set GUI = 0
set VIEWCOV = 0

while ( $#argv > 0 )
    switch ("$argv[1]")
        # Clean temporary and build files
        case "-c":
            cd "$PROJECT_DIR"
            echo "Cleaning up generated simulation files..."
            touch dummy.wlf dummy.mpf dummy.f
            rm -rf work transcript waves *.wlf *.vcd *.mpf modelsim.ini dummy.wlf dummy.mpf dummy.f
            echo "Clean complete."
            exit 0
            breaksw

        # Archive project directory for submission
        case "-z":
            cd "$PROJECT_DIR"
            set zip_name = "lab_submission.zip"
            echo "Archiving project directory to $zip_name..."
            if ( -f "$zip_name" ) rm -f "$zip_name"
            zip -r "$zip_name" . -x "work/*" "*.wlf" "transcript"
            echo "Archive complete."
            exit 0
            breaksw

        # Explicit Batch Mode flag
        case "-b":
            set GUI = 0
            shift argv
            breaksw

        # GUI Mode flag
        case "-g":
            set GUI = 1
            shift argv
            breaksw

        # UVM Test Name flag
        case "-t":
            if ( $#argv < 2 ) then
                echo "ERROR: -t requires a test name"
                echo "Usage: csh script/run.csh [-b | -g] [-t <test_name>] [-v] [-c] [-z]"
                exit 1
            endif
            set TEST_NAME = "$argv[2]"
            shift argv
            shift argv
            breaksw

        # Lab 5: open a saved coverage database in the Questa coverage viewer
        case "-v":
            set VIEWCOV = 1
            shift argv
            breaksw

        default:
            echo "ERROR: Unknown argument '$argv[1]'"
            echo "Usage: csh script/run.csh [-b | -g] [-t <test_name>] [-v] [-c] [-z]"
            exit 1
            breaksw
    endsw
end

cd "$PROJECT_DIR"

# Lab 5: -v only opens an existing coverage database, no compile/sim
#   csh script/run.csh -v -t pdm_full_coverage_test
if ($VIEWCOV == 1) then
    if (! -f "coverage/$TEST_NAME.ucdb") then
        echo "ERROR: coverage/$TEST_NAME.ucdb not found. Run the test first."
        exit 1
    endif
    vsim -viewcov "coverage/$TEST_NAME.ucdb"
    exit $status
endif

# Lab 5: output folders from the lab template
if (! -d coverage) mkdir coverage
if (! -d waves) mkdir waves

# =========================================================
# 3. Work Library Setup
# =========================================================
if (! -d work) then
    echo "Creating work library..."
    vlib work
    if ($status != 0) exit 1
else
    echo "Directory 'work' already exists. Skipping vlib."
endif

if (! -e "$PROJECT_DIR/modelsim.ini") then
    unsetenv MODELSIM
    vmap -c
    if ($status != 0) exit 1
endif

setenv MODELSIM "$PROJECT_DIR/modelsim.ini"
vmap work work
if ($status != 0) exit 1

# =========================================================
# 4. Compilation
# =========================================================
echo "Compiling design and verification files..."
vlog -sv -L mtiUvm \
    "+incdir+$VERIF_DIR" \
    "$DUT_DIR/pdm_core.svp" \
    "$DUT_DIR/pdm_top.v" \
    "$VERIF_DIR/pdm_upstream_if.sv" \
    "$VERIF_DIR/pdm_downstream_if.sv" \
    "$VERIF_DIR/pdm_pkg.sv" \
    "$VERIF_DIR/top.sv"

if ($status != 0) then
    echo "ERROR: Compilation failed."
    exit 1
endif

# =========================================================
# 5. Simulation Execution
# =========================================================
# Export environment variables so run.do can read them
setenv TESTNAME "$TEST_NAME"
setenv PDM_GUI "$GUI"

if ($GUI == 1) then
    echo "Starting Questa Simulator in GUI mode for test: $TEST_NAME..."
    vsim -L mtiUvm -do "set TESTNAME $TEST_NAME; do $SCRIPT_DIR/run.do"
else
    echo "Starting Questa Simulator in BATCH mode for test: $TEST_NAME..."
    vsim -c -L mtiUvm -do "set TESTNAME $TEST_NAME; do $SCRIPT_DIR/run.do"
endif
set SIM_STATUS = $status

# =========================================================
# 6. Lab 5: Coverage Report (HTML)
# =========================================================
# run.do saved coverage/<test>.ucdb on exit; convert it to HTML.
# Open coverage/<test>_html/index.html in a browser for the screenshot.
if (-f "coverage/$TEST_NAME.ucdb") then
    echo "Generating HTML coverage report: coverage/${TEST_NAME}_html/index.html"
    vcover report "coverage/$TEST_NAME.ucdb" -html -details -output "coverage/${TEST_NAME}_html"
else
    echo "WARNING: coverage/$TEST_NAME.ucdb was not created."
endif

exit $SIM_STATUS