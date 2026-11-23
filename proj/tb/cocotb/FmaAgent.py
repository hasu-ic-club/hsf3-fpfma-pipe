from cocotb.triggers import FallingEdge, ReadOnly, RisingEdge

from FmaTransactions import FmaOperandInputTransaction, FmaResultOutputTransaction


def _logic(port):
    value = port.value
    assert value.is_resolvable, f"{port._name} has unresolved value {value}"
    return int(value)


class FmaOperandInputDriver:
    def __init__(self, duv):
        self.duv = duv

    def drive(self, item: FmaOperandInputTransaction | None):
        self.duv.op_valid.value = int(item is not None)
        if item is not None:
            self.duv.op_a_in.value = item.op_a
            self.duv.op_b_in.value = item.op_b
            self.duv.op_c_in.value = item.op_c

    def is_ready(self):
        return _logic(self.duv.op_ready)


class FmaResultOutputMonitor:
    def __init__(self, duv):
        self.duv = duv

    def drive_ready(self, ready):
        self.duv.result_ready.value = int(ready)

    def is_valid(self):
        return _logic(self.duv.result_valid)

    def sample(self):
        if not self.is_valid():
            return None
        return FmaResultOutputTransaction(
            _logic(self.duv.result_out),
            _logic(self.duv.exception_out),
            _logic(self.duv.nan_out),
            _logic(self.duv.inf_out),
        )


class FmaAgent:
    def __init__(self, duv, context=""):
        self.duv = duv
        self.context = context
        self.driver = FmaOperandInputDriver(duv)
        self.monitor = FmaResultOutputMonitor(duv)
        self.cycle = 0
        self.held_input = None
        self.held_output = None
        self.duv.op_a_in.value = 0
        self.duv.op_b_in.value = 0
        self.duv.op_c_in.value = 0
        self.driver.drive(None)
        self.monitor.drive_ready(False)
        self.duv.aresetn.value = 0

    async def reset(self):
        await FallingEdge(self.duv.clk)
        self.duv.aresetn.value = 0
        self.driver.drive(None)
        self.monitor.drive_ready(False)
        await ReadOnly()
        assert not self.monitor.is_valid(), f"{self.context}: valid stayed high in reset"
        await RisingEdge(self.duv.clk)
        await FallingEdge(self.duv.clk)
        self.duv.aresetn.value = 1
        await ReadOnly()
        assert not self.monitor.is_valid(), f"{self.context}: stale output after reset"
        self.held_input = None
        self.held_output = None

    async def step(self, inputs=None, ready=True):
        input_bits = inputs.as_tuple() if inputs is not None else None
        if self.held_input is not None:
            assert input_bits == self.held_input, (
                f"{self.context}: input changed during stall at cycle {self.cycle + 1}"
            )

        await FallingEdge(self.duv.clk)
        self.driver.drive(inputs)
        self.monitor.drive_ready(ready)
        await ReadOnly()
        # Capture stable signals before the rising edge consumes them.
        accepted = inputs is not None and bool(self.driver.is_ready())
        output = self.monitor.sample()
        output_bits = output.as_tuple() if output is not None else None
        if self.held_output is not None:
            assert output_bits == self.held_output, (
                f"{self.context}: output changed during stall at cycle {self.cycle + 1}"
            )
        self.held_input = None if accepted else input_bits
        self.held_output = None if ready else output_bits
        await RisingEdge(self.duv.clk)
        self.cycle += 1
        return accepted, output
