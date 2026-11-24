# HSF3 Pipelined Floating Point Fused Multiply-Adder (FPFMA-PIPE)

HSF3 is a pipelined parameterized ANY-precision floating point fused multiply-adder designed for high-performance computing applications.
It can be configured to support various floating point formats by adjusting the parameters for exponent and mantissa widths.

This IP is pipelined to achieve high throughput, making it suitable for applications requiring fast floating point arithmetic operations.

## Update in Nov 24, 2026

We moved mantissa multiplication to stage II (MALU).
Stage I (Preproc) detects special values and normalizes subnormal inputs.
Stage II compares the raw product exponent and the exponent of `C` to determine the alignment shift in parallel with multiplication.

We merged the alignment shifters into one radix-4 right shifter in stage III (AALU), so stage II can forward the narrow, unaligned mantissa of `C`.
The shifter aligns the operand with the smaller base exponent and folds discarded bits into its low bit.
For close exponents, a fixed-slice magnitude comparison runs alongside the shift so the adder can negate the smaller operand in place for subtraction.

We split result renormalization across two stages.
Stage IV (Renorm) uses the sum's leading-zero count and exponent limit to select a coarse window and save a sticky bit for the bits below it.
Stage V (Round and Pack) uses a three-bit offset to extract the mantissa and complete the GRS bits before rounding.

The shared alignment shifter and narrower registered `C` path reduce area.
Computing the exponent difference alongside multiplication and splitting result renormalization across two stages shorten the critical combinational paths and increase fMax.

## Features
- Fully pipelined architecture w/ II = 1
- Parameterized exponent and mantissa widths
- Parameterized rounding modes, supporting multiple IEEE 754 rounding modes, including:
    - Round to Nearest Even
    - Round towards Zero
    - Round towards Positive Infinity
    - Round towards Negative Infinity
- Exception compatible: NaN/Infinity input and output

## Getting Started
### FuseSoC and Cocotb Requirements
This IP organized with [FuseSoC](https://github.com/olofk/fusesoc), a package manager and build system for HDL code.
To build and simulate the IP core, you need to have following requirements installed:
- fusesoc
- pytest
- cocotb

You can simply use `uv` or other Python virtual environment tools to create a new environment,
then install the requirements with `pip`:
```
uv pip install fusesoc pytest cocotb
```
You also need GNU Make, `flock`, and Cadence Xcelium available on your `PATH`.

### RTL Infrastructure Dependencies
This IP core depends on the [RTL Infrastructure Library](https://github.com/hasu-ic-club/hasunosora-hdl-infra) provided by Hasunosora IC Design Club.

The git URL of the library is already registered in the FuseSoC configuration file `fusesoc.conf` of the repository. So if you have set up FuseSoC correctly, it can automatically fetch the library when building the IP core.

### Building and Simulating the IP Core

The Makefile uses FuseSoC's simulation flow to build the IP core and run the cocotb testbench with Cadence Xcelium. Run the commands below from the repository root.

For a single configuration, use `make run`. The default is FP32 with round-to-nearest-even. You can select a different exponent width, mantissa width, or rounding mode on the command line.

```sh
make run
make run EXPONENT_WIDTH=3 MANTISSA_WIDTH=6 FP_ROUND_MODE=3
```

Use `FP_ROUND_MODE` to select the rounding mode.

| Rounding Mode | Number |
|---------------|--------|
| To nearest, ties to even | `0` |
| Toward zero | `1` |
| Toward positive infinity | `2` |
| Toward negative infinity | `3` |

To run a single test case, set `COCOTB_TEST_FILTER`.

```sh
make run COCOTB_TEST_FILTER=directed_extremes
```

Use `make regression` to run the full matrix of ten formats and four rounding modes. To run a smaller matrix, pass `E:M` pairs in `FORMATS` and mode numbers in `ROUND_MODES`.

```sh
make regression
make regression FORMATS="8:23 4:3" ROUND_MODES="0 3"
```

Build artifacts and `results.xml` are stored separately for each configuration, for example under `build/cocotb/sim/e8m23r0/` for the default run. Make reports a failure if a test fails or cocotb produces no results.

For waveforms and RTL coverage, use the `sim_debug` target.

```sh
make run TARGET=sim_debug COCOTB_TEST_FILTER=directed_extremes
```

You can open the waveform database in Indago. For the default configuration, look under `build/cocotb/sim_debug/e8m23r0/ida.db/`.

### Using Other Simulators

The supplied Makefile is set up for Xcelium. To run the same cocotb tests with another simulator, add a simulation target in `proj/hsf3_fpfma_pipe.core` and set `flow_options.tool` and the corresponding tool options for that simulator. Keep the cocotb test module, the simulation wrapper, and its three HDL parameters so you can run the same configurations.

Use the cocotb launcher and waveform options supported by your simulator. The `sim_debug` target uses the Xcelium-specific script `proj/tb/script/xrun.tcl`. See the [FuseSoC documentation](https://fusesoc.readthedocs.io/en/stable/user/build_system/eda_flows.html) for details on configuring a simulation flow.

If you run into trouble, feel free to open an issue. Pull requests adding support for other simulators are welcome!

## Testing

Each configuration uses the same cocotb testbench to check the result bits and the NaN, infinity, and exception flags. The testbench uses the Python reference model to compute `a * b + c` with a single rounding, including for formats wider than 64 bits.

| Test Case Name | Description |
|----------------|-------------|
| `directed_extremes` | Checks signed zeros, NaNs, infinities, and boundary cases for subnormal results, cancellation, rounding, and overflow. |
| `random_binary` | Generates random operand bit patterns across the entire encoding space, including special values. |
| `random_finite` | Generates random finite operands with extra coverage near cancellation and addend alignment boundaries. Adds input gaps and output backpressure. |
| `exhaustive_small` | Checks every ordered triple of operand encodings for small formats. The default total operand width limit is 5 bits, including the sign bit. |
| `flow_control` | Checks pipeline latency, full throughput, stability under backpressure, and reset with transactions in flight. |

Use `HSF3_RANDOM_CASES` to set the number of vectors in each random test, `HSF3_SEED` to reproduce a run, and `HSF3_EXHAUSTIVE_BITS` to adjust the width limit for exhaustive testing.

## Known Issues
Currently, we have not found any known issues with this IP core. If you encounter any problems or bugs, please report them by opening an issue in this repository.

The pipeline stage partitioning and fMax of the current design still need optimization.

## License
This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Contributing
Contributions are welcome! If you find any issues or have suggestions for improvements, please open an issue or submit a pull request.
