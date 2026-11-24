"""Parameterized HSF3 regression for a single elaborated DUT.

The launcher selects E, M, and the rounding mode. HSF3_EXPONENT_WIDTH,
HSF3_MANTISSA_WIDTH, and HSF3_ROUND_MODE can supply parameters hidden by VPI.
HSF3_SEED, HSF3_RANDOM_CASES, and HSF3_EXHAUSTIVE_BITS control run size.
"""

import logging
import os
import random
from dataclasses import dataclass
from itertools import chain, product

import cocotb
import pytest
from cocotb.clock import Clock

from FloatingPoint import FloatingPoint, FloatingPointRoundingMode as Rounding
from FmaTestbench import FmaTestbench, PIPELINE_LATENCY
from FmaTransactions import FmaOperandInputTransaction as InputTransaction


LOG = logging.getLogger(f"cocotb.{__name__}")
TIMEOUT = {"timeout_time": 50, "timeout_unit": "ms"}


def _mode_number(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        name = str(value).split("::")[-1].removeprefix("FP_ROUND_MODE_")
        if name == "TIES_TO_EVEN":
            return Rounding.NEAREST_EVEN.value
        try:
            return Rounding[name].value
        except KeyError as error:
            raise ValueError(f"Unknown rounding mode {value!r}") from error


def _parameter(dut, name, env, parse=int):
    configured = os.getenv(env)
    setting = parse(configured) if configured is not None else None
    try:
        actual = parse(getattr(dut, name).value)
    except (AttributeError, TypeError, ValueError) as error:
        if setting is not None:
            return setting
        raise AssertionError(f"Cannot read {name} from DUT. Set {env} to its elaborated value.") from error
    assert setting is None or actual == setting, f"{name}={actual} disagrees with {env}={setting}"
    return actual


@dataclass(frozen=True)
class Format:
    e: int
    m: int
    mode: Rounding

    @property
    def width(self):
        return 1 + self.e + self.m

    @property
    def exp_max(self):
        return (1 << self.e) - 1

    @property
    def hidden(self):
        return 1 << self.m

    @property
    def sign_bit(self):
        return 1 << (self.e + self.m)

    @property
    def inf(self):
        return self.exp_max << self.m

    def power(self, biased_exp):
        if 1 <= biased_exp < self.exp_max:
            return biased_exp << self.m
        if 1 - self.m <= biased_exp <= 0:
            return self.hidden >> (1 - biased_exp)
        return 0


def _read_format(dut):
    fmt = Format(
        _parameter(dut, "EXPONENT_WIDTH", "HSF3_EXPONENT_WIDTH"),
        _parameter(dut, "MANTISSA_WIDTH", "HSF3_MANTISSA_WIDTH"),
        Rounding(_parameter(dut, "FP_ROUND_MODE", "HSF3_ROUND_MODE", _mode_number)),
    )
    assert 1 <= fmt.e <= 32 and 1 <= fmt.m <= 128, f"Unsupported RTL format {fmt}"
    for port in (dut.op_a_in, dut.op_b_in, dut.op_c_in, dut.result_out):
        assert len(port) == fmt.width, f"Port width {len(port)} disagrees with {fmt}"
    return fmt



def _expected(fmt, a, b, c):
    if fmt.width > 64:
        return FloatingPoint.fma_bits(fmt.m, fmt.e, a, b, c, fmt.mode)
    x = FloatingPoint(fmt.m, fmt.e, a)
    y = FloatingPoint(fmt.m, fmt.e, b)
    z = FloatingPoint(fmt.m, fmt.e, c)
    return FloatingPoint.fma(x, y, z, fmt.mode).get_binary()


def _make_testbench(dut, fmt=None):
    if fmt is None:
        fmt = _read_format(dut)
    seed = int(os.getenv("HSF3_SEED", "42"), 0)
    context = f"E={fmt.e} M={fmt.m} mode={fmt.mode.name} seed={seed}"
    bench = FmaTestbench(
        dut, en_backpressure=False, exponent_width=fmt.e, mantissa_width=fmt.m,
        predictor=lambda a, b, c: _expected(fmt, a, b, c), seed=seed, context=context,
    )
    Clock(dut.clk, 10, unit="ns").start(start_high=False)
    LOG.info("%s oracle=FloatingPoint", context)
    return bench, fmt, seed


def _directed_vectors(fmt):
    largest = fmt.inf - 1
    magnitudes = {0, 1, fmt.hidden - 1, largest, fmt.inf, fmt.inf | 1, fmt.inf | (fmt.hidden - 1)}
    if fmt.exp_max > 1:
        magnitudes.update((fmt.hidden, fmt.hidden + 1, largest - 1))
        one = fmt.power(fmt.exp_max // 2)
        magnitudes.update((one - 1, one, one + 1))
    signed = sorted(magnitudes | {value | fmt.sign_bit for value in magnitudes})
    for a, b, c in product(signed, repeat=3):
        yield InputTransaction(a, b, c)

    if fmt.exp_max == 1:
        return

    bias = fmt.exp_max // 2
    half, one, two = (fmt.power(bias + offset) for offset in (-1, 0, 1))
    next_one = one | 1
    next_down_one = one - 1
    one_minus_ulp = one - (2 if bias > 1 else 1)
    one_and_half = one | (fmt.hidden >> 1)
    cases = {
        (one, one, one),                                  # exact cancellation when C is negative
        (next_one, one_minus_ulp, one),                    # low product bits survive cancellation
        (next_one, next_one, one),
        (largest, next_one, largest),                     # cancellation can rescue an overflowing product
        (largest, two, 0),
        (largest, one, largest),                          # overflow from the addition
        (fmt.hidden, next_down_one, 0),                   # subnormal rounding and promotion
        (fmt.hidden - 1, one, 1),
        (1, half, 0),                                    # half of the smallest subnormal
        (next_one, one_and_half, 0),                      # midpoint with and without a tiny addend
        (next_one, one_and_half, 1),
        (one, one, fmt.power(bias - fmt.m - 1)),            # half an ulp at one
        (next_one, one, fmt.power(bias - fmt.m - 1)),
    }
    aligned_width = 2 * fmt.m + 4
    for gap, direction in product((1, aligned_width - 1, aligned_width, aligned_width + 1), (-1, 1)):
        addend = fmt.power(bias + direction * gap)
        if addend:
            cases.add((next_one, next_one, addend))

    for (a, b, c), sign_a, sign_b, sign_c in product(
            sorted(cases), (0, fmt.sign_bit), (0, fmt.sign_bit), (0, fmt.sign_bit)):
        yield InputTransaction(a | sign_a, b | sign_b, c | sign_c)
        if a != b or sign_a != sign_b:
            yield InputTransaction(b | sign_b, a | sign_a, c | sign_c)


def _random_finite_vectors(fmt, rng, count):
    max_exp = fmt.exp_max - 1
    bias = fmt.exp_max // 2
    edges = sorted({0, min(1, max_exp), bias, max(0, max_exp - 1), max_exp})
    aligned_width = 2 * fmt.m + 4
    gaps = (0, 1, 2, aligned_width - 1, aligned_width, aligned_width + 1)
    for index in range(count):
        exp_a, exp_b, exp_c = (rng.randint(0, max_exp) for _ in range(3))
        sign_a, sign_b, sign_c = (rng.choice((0, fmt.sign_bit)) for _ in range(3))
        if index % 4 == 1:
            exp_a, exp_b, exp_c = (rng.choice(edges) for _ in range(3))
        elif index % 4 in (2, 3):
            # Bias the addend toward cancellation or the shift-jam boundary.
            prod_exp = max(1, exp_a) + max(1, exp_b) - bias
            if index % 4 == 2:
                exp_c = prod_exp + rng.choice((-1, 0, 1, 2))
                sign_c = sign_a ^ sign_b ^ fmt.sign_bit
            else:
                exp_c = prod_exp + rng.choice((-1, 1)) * rng.choice(gaps)
            exp_c = max(0, min(max_exp, exp_c))
        a = (exp_a << fmt.m) | rng.getrandbits(fmt.m)
        b = (exp_b << fmt.m) | rng.getrandbits(fmt.m)
        c = (exp_c << fmt.m) | rng.getrandbits(fmt.m)
        yield InputTransaction(a | sign_a, b | sign_b, c | sign_c)


def _random_count():
    count = int(os.getenv("HSF3_RANDOM_CASES", "20000"), 0)
    assert count > 0, "HSF3_RANDOM_CASES must be positive"
    return count


@cocotb.test(**TIMEOUT)
async def directed_extremes(dut):
    bench, fmt, _ = _make_testbench(dut)
    await bench.reset()
    await bench.run(_directed_vectors(fmt))


@cocotb.test(**TIMEOUT)
async def random_binary(dut):
    bench, fmt, seed = _make_testbench(dut)
    rng = random.Random(seed ^ 0x42494E)
    vectors = (InputTransaction(*(rng.getrandbits(fmt.width) for _ in range(3)))
               for _ in range(_random_count()))
    await bench.reset()
    await bench.run(vectors)


@cocotb.test(**TIMEOUT)
async def random_finite(dut):
    bench, fmt, seed = _make_testbench(dut)
    rng = random.Random(seed ^ 0x46494E)
    await bench.reset()
    await bench.run(_random_finite_vectors(fmt, rng, _random_count()),
                    source_probability=0.85, ready_probability=0.70)


@cocotb.test(**TIMEOUT)
async def exhaustive_small(dut):
    fmt = _read_format(dut)
    limit = int(os.getenv("HSF3_EXHAUSTIVE_BITS", "5"), 0)
    assert 0 <= limit <= 7, "HSF3_EXHAUSTIVE_BITS must be between 0 and 7"
    if fmt.width > limit:
        pytest.skip(f"{fmt.width} bits exceeds the {limit}-bit exhaustive limit")
    bench, _, _ = _make_testbench(dut, fmt)
    await bench.reset()
    await bench.run(InputTransaction(a, b, c) for a, b, c in product(range(1 << fmt.width), repeat=3))


@cocotb.test(**TIMEOUT)
async def flow_control(dut):
    bench, fmt, seed = _make_testbench(dut)
    stall_vectors = [
        InputTransaction(fmt.inf, 0, 1),
        InputTransaction(fmt.inf, 1, fmt.inf | fmt.sign_bit),
        InputTransaction(1, 1, 0),
        InputTransaction(1, 0, 1 | fmt.sign_bit),
        InputTransaction(fmt.inf | 1, 1, 0),
        InputTransaction(0, 0, fmt.inf),
    ]

    await bench.reset()
    await bench.run(_random_finite_vectors(fmt, random.Random(seed), 32))
    assert bench.scoreboard.checked == 32 and bench.stalled_input == 0, bench.context
    assert bench.first_output - bench.first_input == PIPELINE_LATENCY, bench.context
    assert bench.last_output - bench.first_output + 1 == bench.scoreboard.checked, bench.context

    await bench.reset()
    vectors = iter(stall_vectors)
    pending = next(vectors)
    for _ in range(PIPELINE_LATENCY + 9):
        if await bench.step(pending, ready=False):
            pending = next(vectors, None)
    assert bench.accepted == PIPELINE_LATENCY and bench.stalled_input and bench.stalled_output, bench.context
    await bench.run(chain(vectors, (InputTransaction(0, 0, 0),)), held_input=pending)
    assert bench.scoreboard.checked == len(stall_vectors) + 1, bench.context

    await bench.reset()
    for vector in stall_vectors[:PIPELINE_LATENCY]:
        assert await bench.step(vector, ready=False), bench.context
    assert bench.scoreboard.pending == PIPELINE_LATENCY and bench.scoreboard.checked == 0, bench.context
    await bench.reset()
    await bench.run([
        InputTransaction(0, 0, 0), InputTransaction(1 | fmt.sign_bit, 0, 0),
        InputTransaction(fmt.inf | 1, 1, 0),
    ])
    assert bench.scoreboard.checked == 3, bench.context
