from collections import Counter, deque

from FmaTransactions import FmaResultOutputTransaction


class FmaScoreboard:
    def __init__(self, exponent_width, mantissa_width, predictor=None, context=""):
        width = 1 + exponent_width + mantissa_width
        self.width_digits = (width + 3) // 4
        self.magnitude_mask = (1 << (width - 1)) - 1
        self.hidden = 1 << mantissa_width
        self.infinity = ((1 << exponent_width) - 1) << mantissa_width
        self.predictor = predictor
        self.context = context
        self.expected_queue = deque()
        self.coverage = Counter()
        self.checked = 0

    @property
    def pending(self):
        return len(self.expected_queue)

    def reset(self):
        self.expected_queue.clear()
        self.coverage.clear()
        self.checked = 0

    def push_expected(self, inputs, expected=None):
        if expected is None:
            assert self.predictor is not None, "No expected value or predictor supplied"
            expected = self.predictor(inputs.op_a, inputs.op_b, inputs.op_c)
        self.expected_queue.append((inputs, expected))

    def check_one(self, actual: FmaResultOutputTransaction, cycle):
        assert self.expected_queue, (
            f"{self.context}: unexpected output at cycle {cycle}: {actual.as_tuple()}"
        )
        inputs, bits = self.expected_queue.popleft()
        category = self._category(bits)
        nan, inf = int(category == "nan"), int(category == "inf")
        expected = (bits, nan, inf, nan | inf)
        actual_bits = actual.as_tuple()
        assert actual_bits == expected, (
            f"{self.context} transaction={self.checked + 1} cycle={cycle}: "
            f"{self._hex(inputs.op_a)} * {self._hex(inputs.op_b)} + {self._hex(inputs.op_c)} "
            f"got {self._hex(actual.result)} flags={actual_bits[1:]} "
            f"expected {self._hex(bits)} flags={expected[1:]} (NaN, Inf, exception)"
        )
        classes = tuple(self._category(operand) for operand in inputs.as_tuple())
        self.coverage[(*classes, category)] += 1
        self.checked += 1

    def _category(self, bits):
        magnitude = bits & self.magnitude_mask
        if magnitude >= self.infinity:
            return "nan" if magnitude > self.infinity else "inf"
        if magnitude < self.hidden:
            return "subnormal" if magnitude else "zero"
        return "normal"

    def _hex(self, bits):
        return f"0x{bits:0{self.width_digits}X}"
