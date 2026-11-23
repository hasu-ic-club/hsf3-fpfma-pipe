import logging
import random

from FmaAgent import FmaAgent
from FmaScoreboard import FmaScoreboard


PIPELINE_LATENCY = 5


class FmaTestbench:
    def __init__(self, duv, en_backpressure=True, backpressure_rate=0.3, *,
                 exponent_width=None, mantissa_width=None, predictor=None, seed=42, context=""):
        self.duv = duv
        if exponent_width is None:
            exponent_width = int(duv.EXPONENT_WIDTH.value)
        if mantissa_width is None:
            mantissa_width = int(duv.MANTISSA_WIDTH.value)
        self.context = context or f"E={exponent_width} M={mantissa_width} seed={seed}"
        self.log = logging.getLogger("cocotb.tb")
        self.ready_probability = backpressure_rate if en_backpressure else 1.0
        self.source = random.Random(seed ^ 0x534F5552)
        self.sink = random.Random(seed ^ 0x53494E4B)
        self.agent = FmaAgent(duv, self.context)
        self.scoreboard = FmaScoreboard(exponent_width, mantissa_width, predictor, self.context)
        self._reset_counts()

    def _reset_counts(self):
        self.accepted = self.stalled_output = self.stalled_input = 0
        self.first_input = self.first_output = self.last_output = None

    async def reset(self):
        await self.agent.reset()
        self.scoreboard.reset()
        self._reset_counts()

    async def step(self, inputs=None, ready=True, *, expected=None):
        accepted, output = await self.agent.step(inputs, ready)
        cycle = self.agent.cycle
        self.stalled_input += int(inputs is not None and not accepted)
        self.stalled_output += int(output is not None and not ready)

        if output is not None and ready:
            self.scoreboard.check_one(output, cycle)
            if self.first_output is None:
                self.first_output = cycle
            self.last_output = cycle
        if accepted:
            if self.first_input is None:
                self.first_input = cycle
            self.accepted += 1
            self.scoreboard.push_expected(inputs, expected)
        return accepted

    async def run(self, vectors, source_probability=1.0, ready_probability=None,
                  held_input=None, *, expected_values=None):
        if ready_probability is None:
            ready_probability = self.ready_probability
        if expected_values is None:
            cases = ((item, None) for item in vectors)
        else:
            cases = zip(vectors, expected_values, strict=True)
        offered = held_input is not None
        current = (held_input, None) if offered else next(cases, None)
        progress = self.agent.cycle
        while current is not None:
            inputs, expected = current
            offered = offered or self.source.random() < source_probability
            ready = self.sink.random() < ready_probability
            if await self.step(inputs if offered else None, ready, expected=expected):
                current = next(cases, None)
                offered = False
                progress = self.agent.cycle
            assert self.agent.cycle - progress < 1024, (
                f"{self.context}: input handshake stalled for 1024 cycles"
            )

        for _ in range(64):
            if not self.scoreboard.pending:
                break
            await self.step()
        assert not self.scoreboard.pending, (
            f"{self.context}: drain timeout with {self.scoreboard.pending} pending"
        )
        assert self.scoreboard.checked == self.accepted, (
            f"{self.context}: accepted={self.accepted}, checked={self.scoreboard.checked}"
        )
        for _ in range(PIPELINE_LATENCY + 1):
            await self.step()
        self.log.info("%s checked=%d input_stalls=%d output_stalls=%d operand/result classes=%s",
                      self.context, self.scoreboard.checked, self.stalled_input,
                      self.stalled_output, dict(sorted(self.scoreboard.coverage.items())))

    async def send_vectors(self, op_vecs, result_vecs):
        expected_values = (result.get_binary() for _, _, _, result in result_vecs)
        await self.run(op_vecs, expected_values=expected_values)
