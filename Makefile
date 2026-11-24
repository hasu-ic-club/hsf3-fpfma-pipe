SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:
.DEFAULT_GOAL := run

FUSESOC ?= fusesoc
CORE ?= hasunosora:arith:fpfma_pipe:0.2
TARGET ?= sim
REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BUILD_ROOT ?= $(REPO_ROOT)/build/cocotb
EXPONENT_WIDTH ?= 8
MANTISSA_WIDTH ?= 23
FP_ROUND_MODE ?= 0

# Exponent:mantissa pairs. Mode 0/1/2/3 is RNE/RTZ/RTP/RTN.
FORMATS ?= 8:23 5:10 8:7 4:3 5:2 1:3 2:2 3:1 3:6 8:70
ROUND_MODES ?= 0 1 2 3

work_root := $(abspath $(BUILD_ROOT)/$(TARGET)/e$(EXPONENT_WIDTH)m$(MANTISSA_WIDTH)r$(FP_ROUND_MODE))

.PHONY: run regression
run:
	@cd "$(REPO_ROOT)"
	case "$(FP_ROUND_MODE)" in
	    0|1|2|3) ;;
	    *) echo "FP_ROUND_MODE must be 0, 1, 2, or 3." >&2; exit 2 ;;
	esac
	mkdir -p "$(work_root)"
	exec 9>"$(work_root)/.lock"
	flock 9

	export COCOTB_TOPLEVEL=hsf3_fpfma_duv_top
	export COCOTB_TEST_MODULES=hsf3_wrapper_test
	export COCOTB_RESULTS_FILE="$(work_root)/results.xml"
	export HSF3_EXPONENT_WIDTH="$(EXPONENT_WIDTH)"
	export HSF3_MANTISSA_WIDTH="$(MANTISSA_WIDTH)"
	export HSF3_ROUND_MODE="$(FP_ROUND_MODE)"
	libpython="$$(cocotb-config --libpython)"
	pygpi_entry="$$(cocotb-config --pygpi-entry-point)"
	export GPI_USERS="$$libpython;$$pygpi_entry"
	cocotb_python="$$(cocotb-config --python-bin)"
	export PYGPI_PYTHON_BIN="$$cocotb_python"
	: > "$$COCOTB_RESULTS_FILE"

	# Edalize 0.6.8 emits this option even for Xcelium releases older than 25.
	xrun_version="$$(xrun -version)"
	flow_make_options=()
	if [[ "$$xrun_version" =~ [[:space:]]([0-9][0-9])\.[0-9][0-9] ]] &&
	    (( 10#$${BASH_REMATCH[1]} < 25 )); then
	    hsf3_xrun_compat() {
	        local -a args=()
	        local arg
	        for arg in "$$@"; do
	            if [[ "$$arg" != -enable_cmdline_define_redefinition ]]; then
	                args+=("$$arg")
	            fi
	        done
	        command "$${args[@]}"
	    }
	    export -f hsf3_xrun_compat
	    flow_make_options=("--flow_make_options=SHELL=/bin/bash EDALIZE_LAUNCHER=hsf3_xrun_compat")
	fi

	stages=()
	if [[ "$(TARGET)" == sim_debug ]]; then
	    stages=(--setup --build)
	fi
	$(FUSESOC) --config fusesoc.conf run "$${stages[@]}" --target "$(TARGET)" \
	    --work-root "$(work_root)" "$(CORE)" "$${flow_make_options[@]}" \
	    --EXPONENT_WIDTH="$(EXPONENT_WIDTH)" --MANTISSA_WIDTH="$(MANTISSA_WIDTH)" \
	    --FP_ROUND_MODE="$(FP_ROUND_MODE)"

	# The Flow API's xrun -R does not forward -input to the simulation step.
	if [[ "$(TARGET)" == sim_debug ]]; then
	    (cd "$(work_root)" && xrun -64bit -R -input xrun_debug.tcl)
	fi

	if [[ ! -s "$$COCOTB_RESULTS_FILE" ]]; then
	    echo "cocotb did not write results to $$COCOTB_RESULTS_FILE" >&2
	    exit 1
	fi
	"$$cocotb_python" - "$$COCOTB_RESULTS_FILE" <<'PY'
	from pathlib import Path
	import sys

	from cocotb_tools.check_results import get_results

	results = Path(sys.argv[1])
	tests, failures = get_results(results)
	print(f"{results}: {tests} tests, {failures} failures")
	sys.exit(int(tests == 0 or failures != 0))
	PY

regression:
	+@for format in $(FORMATS); do
	    for mode in $(ROUND_MODES); do
	        $(MAKE) --no-print-directory run EXPONENT_WIDTH="$${format%:*}" \
	            MANTISSA_WIDTH="$${format#*:}" FP_ROUND_MODE="$$mode"
	    done
	done
