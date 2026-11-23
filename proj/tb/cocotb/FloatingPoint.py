import math
import struct
from enum import Enum

class FloatingPointRoundingMode(Enum):
    NEAREST_EVEN = 0
    TOWARD_ZERO = 1
    TOWARD_POSITIVE = 2
    TOWARD_NEGATIVE = 3

class FloatingPointGRS:
    def __init__(self):
        self.guard = 0
        self.round = 0
        self.sticky = 0

    def _get_extend_mantissa(self, mantissa):
        mantissa = mantissa << 3
        extMantissa = mantissa | (self.guard << 2) | (self.round << 1) | self.sticky
        return extMantissa

    def set_grs_from_ext_mantissa(self, ext_mantissa):
        self.guard = (ext_mantissa >> 2) & 0x1
        self.round = (ext_mantissa >> 1) & 0x1
        self.sticky = ext_mantissa & 0x1

        return ext_mantissa >> 3

    def get_shiftable_mantissa(self, mantissa):
        return self._get_extend_mantissa(mantissa) >> 1

    @staticmethod
    def rshift_jam(value, shift):
        if shift >= value.bit_length():
            return int(value != 0)
        lostBitsMask = (1 << shift) - 1
        return (value >> shift) | (1 if (value & lostBitsMask) != 0 else 0)

    def rshift_with_grs(self, mantissa, shift):
        return self.set_grs_from_ext_mantissa(
            self.rshift_jam(
                self._get_extend_mantissa(mantissa), shift
            )
        )

    def lshift_with_grs(self, mantissa, shift):
        extMantissa = self._get_extend_mantissa(mantissa)
        extMantissa <<= shift
        return self.set_grs_from_ext_mantissa(extMantissa)

    def subtract_with_grs(self, substracted, mantissa):
        ext_sub = substracted << 3
        ext_mantissa = self._get_extend_mantissa(mantissa)
        result = ext_sub - ext_mantissa

        return self.set_grs_from_ext_mantissa(result)

    def clear_grs(self):
        self.guard = 0
        self.round = 0
        self.sticky = 0

    def apply_grs_rounding(self, mantissa, sign, rounding_mode: FloatingPointRoundingMode):
        if rounding_mode == FloatingPointRoundingMode.NEAREST_EVEN:
            if self.guard == 1:
                if self.round == 1 or self.sticky == 1 or (mantissa & 0x1) == 1:
                    mantissa += 1
        elif rounding_mode == FloatingPointRoundingMode.TOWARD_ZERO:
            pass
        elif rounding_mode == FloatingPointRoundingMode.TOWARD_POSITIVE:
            if sign == 0 and (self.guard == 1 or self.round == 1 or self.sticky == 1):
                mantissa += 1
        elif rounding_mode == FloatingPointRoundingMode.TOWARD_NEGATIVE:
            if sign == 1 and (self.guard == 1 or self.round == 1 or self.sticky == 1):
                mantissa += 1
        else:
            raise ValueError("Unsupported rounding mode.")
        return mantissa

class FloatingPoint:
    def __init__(self, M: int = 23, E: int = 8, data = 0):
        assert E > 0 and M > 0 and (E + M + 1) <= 64, "Invalid floating point format specification."

        self.M = M  # Number of mantissa bits
        self.E = E  # Number of exponent bits

        # Constant masks and values
        self.EXPONENT_ALL_ONES_MASK = (1 << E) - 1
        self.MANTISSA_HIDDEN_BIT_MASK = (1 << M)
        self.MANTISSA_ALL_ONES_MASK = (1 << M) - 1
        self.EXPONENT_BIAS = (1 << (E - 1)) - 1
        self.SIGN_BIT_MASK = (1 << (E + M))
        self.MAXIMUM_EXP = (1 << E) - 2 - self.EXPONENT_BIAS
        self.MINIMUM_EXP = 1 - self.EXPONENT_BIAS
        self.MINIMUM_SUBNORMALIZED_EXP = self.MINIMUM_EXP - M

        self.data = data

    def set_value(self, sign = 0, exponent = 0, mantissa = 0):
        self.data = ((sign & 0x1) << (self.E + self.M)) | ((exponent & self.EXPONENT_ALL_ONES_MASK) << self.M) | (mantissa & self.MANTISSA_ALL_ONES_MASK)

    def set_binary(self, binary):
        self.data = binary

    def get_binary(self):
        return self.data

    def get_sign(self):
        return (self.data >> (self.E + self.M)) & 0x1

    def get_exponent(self):
        return (self.data >> self.M) & self.EXPONENT_ALL_ONES_MASK

    def get_mantissa(self):
        return self.data & self.MANTISSA_ALL_ONES_MASK

    def is_zero(self):
        return self.get_exponent() == 0 and self.get_mantissa() == 0

    def is_sub_normalized(self):
        return self.get_exponent() == 0 and self.get_mantissa() != 0

    def is_normalized(self):
        exp = self.get_exponent()
        return exp != 0 and exp != self.EXPONENT_ALL_ONES_MASK

    def is_infinity(self):
        return self.get_exponent() == self.EXPONENT_ALL_ONES_MASK and self.get_mantissa() == 0

    def is_nan(self):
        return self.get_exponent() == self.EXPONENT_ALL_ONES_MASK and self.get_mantissa() != 0

    def MAX_NORMALIZED_VALUE(self):
        try:
            return math.ldexp(2.0 - pow(2, -self.M), self.MAXIMUM_EXP)
        except OverflowError:
            return float('inf')

    def MIN_NORMALIZED_VALUE(self):
        return pow(2, self.MINIMUM_EXP)

    def MIN_SUBNORMALIZED_VALUE(self):
        return pow(2, self.MINIMUM_SUBNORMALIZED_EXP)

    @staticmethod
    def ZERO(M, E, sign=0):
        return FloatingPoint(M, E, 0 if sign == 0 else (1 << (M + E)))

    @staticmethod
    def NaN(M, E):
        fp = FloatingPoint(M, E)
        fp.set_value(0, fp.EXPONENT_ALL_ONES_MASK, 1)
        return fp

    def to_float(self):
        if self.is_nan():
            return float('nan')
        if self.is_infinity():
            return float('-inf') if self.get_sign() == 1 else float('inf')
        if self.is_zero():
            return -0.0 if self.get_sign() == 1 else 0.0

        sign = -1.0 if self.get_sign() == 1 else 1.0
        exponent = self.get_exponent()
        mantissa = self.get_mantissa()

        if self.is_sub_normalized():
            exp_value = 1 - self.EXPONENT_BIAS
            mantissa_value = mantissa / (1 << self.M)
        else:
            exp_value = exponent - self.EXPONENT_BIAS
            mantissa_value = 1.0 + (mantissa / (1 << self.M))

        return sign * mantissa_value * (2 ** exp_value)

    def to_float_str(self):
        return f"{self.to_float()}({self.get_binary():08X})"

    @staticmethod
    def from_fp32(value: float):
        b = struct.pack("!f", value)
        fp = FloatingPoint(23, 8)
        fp.set_binary(struct.unpack('!I', b)[0])
        return fp

    def __neg__(self):
        fp = FloatingPoint(self.M, self.E, self.data)
        fp.set_value(1 - self.get_sign(), self.get_exponent(), self.get_mantissa())
        return fp

    def __add__(self, other):
        return FloatingPoint.add(self, other, FloatingPointRoundingMode.NEAREST_EVEN)

    @staticmethod
    def add(a, b, rounding_mode: FloatingPointRoundingMode = FloatingPointRoundingMode.NEAREST_EVEN):
        assert a.M == b.M and a.E == b.E, "Floating point formats must match for addition."
        M = a.M
        E = a.E

        # NaN, Infinity, Zero handling
        #  1. NaN + ANY = NaN
        if a.is_nan() or b.is_nan(): return FloatingPoint.NaN(M, E)

        signA = a.get_sign()
        signB = b.get_sign()

        #  2.  Infinity + -Infinity = NaN
        if a.is_infinity() and b.is_infinity() and (signA != signB):
            return FloatingPoint.NaN(M, E)
        if a.is_infinity():
            return FloatingPoint(M, E, a.get_binary())
        if b.is_infinity():
            return FloatingPoint(M, E, b.get_binary())
        
        #  3. 0 + 0, check the sign
        if a.is_zero() and b.is_zero():
            sign = signA if signA == signB else int(rounding_mode == FloatingPointRoundingMode.TOWARD_NEGATIVE)
            return FloatingPoint.ZERO(M, E, sign)
        
        #  4. 0 + ANY = ANY
        if a.is_zero(): return FloatingPoint(M, E, b.get_binary())
        if b.is_zero(): return FloatingPoint(M, E, a.get_binary())

        # Extract mantissas with hidden bits. Subnormals use signed internal exponents.
        mantissa_a = a.get_mantissa()
        exp_a = a.get_exponent()
        if exp_a == 0: # Sub-normalized
            lz_a = (M + 1) - mantissa_a.bit_length()
            mantissa_a <<= lz_a
            exp_a = 1 - lz_a
        else:
            mantissa_a |= a.MANTISSA_HIDDEN_BIT_MASK

        mantissa_b = b.get_mantissa()
        exp_b = b.get_exponent()
        if exp_b == 0: # Sub-normalized
            lz_b = (M + 1) - mantissa_b.bit_length()
            mantissa_b <<= lz_b
            exp_b = 1 - lz_b
        else:
            mantissa_b |= b.MANTISSA_HIDDEN_BIT_MASK

        # Map the larger magnitude to X and the smaller magnitude to Y.
        if (exp_a < exp_b) or ((exp_a == exp_b) and (mantissa_b > mantissa_a)):
            mantissa_x = mantissa_b
            mantissa_y = mantissa_a
            exp_x = exp_b
            exp_y = exp_a
            sign_x = signB
            sign_y = signA
        else:
            mantissa_x = mantissa_a
            mantissa_y = mantissa_b
            exp_x = exp_a
            exp_y = exp_b
            sign_x = signA
            sign_y = signB

        # Reserve three low bits for G/R/S and align the mantissas.
        hidden_bit = M + 3
        exp_diff = exp_x - exp_y
        ext_mantissa_x = mantissa_x << 3
        ext_mantissa_y = mantissa_y << 3
        ext_mantissa_y = FloatingPointGRS.rshift_jam(ext_mantissa_y, exp_diff)

        # Add or subtract extended mantissas.
        if sign_x == sign_y:
            sum_value = ext_mantissa_x + ext_mantissa_y
        else:
            sum_value = ext_mantissa_x - ext_mantissa_y
        res_exponent = exp_x
        res_sign = sign_x

        if sum_value == 0:
            if rounding_mode == FloatingPointRoundingMode.TOWARD_NEGATIVE:
                res_sign = 1
            else:
                res_sign = 0
            return FloatingPoint.ZERO(M, E, res_sign)

        # Select the normalized exponent from the carry or leading-zero count.
        sum_hidden = sum_value >> hidden_bit
        if sum_hidden & 0b10:
            res_exponent += 1
        elif sum_hidden == 0:
            total_bits = hidden_bit + 1
            leading_zeros = total_bits - sum_value.bit_length()
            res_exponent -= leading_zeros

        # Use exponent 1 for subnormal scaling, then apply the net shift once.
        if res_exponent < 1:
            res_exponent = 1
        sft_to_grs = res_exponent - exp_x
        if sft_to_grs > 0:
            sum_value = FloatingPointGRS.rshift_jam(sum_value, sft_to_grs)
        elif sft_to_grs < 0:
            sum_value <<= -sft_to_grs

        grs = FloatingPointGRS()
        sum_value = grs.set_grs_from_ext_mantissa(sum_value)
        sum_value = grs.apply_grs_rounding(sum_value, res_sign, rounding_mode)

        # Realign after rounding and select the output exponent field.
        sum_hidden = sum_value >> M
        if sum_hidden & 0b10:
            sum_value >>= 1
            res_exponent += 1
        elif sum_hidden == 0:
            res_exponent = 0

        # Select the overflow result before packing the fields.
        max_finite_exp = a.EXPONENT_ALL_ONES_MASK - 1
        if res_exponent > max_finite_exp:
            if (
                rounding_mode == FloatingPointRoundingMode.NEAREST_EVEN
                or (rounding_mode == FloatingPointRoundingMode.TOWARD_POSITIVE and res_sign == 0)
                or (rounding_mode == FloatingPointRoundingMode.TOWARD_NEGATIVE and res_sign == 1)
            ):
                res_exponent = a.EXPONENT_ALL_ONES_MASK
                sum_value = 0
            else:
                res_exponent = max_finite_exp
                sum_value = a.MANTISSA_ALL_ONES_MASK

        # Result construction
        result_mantissa = sum_value & a.MANTISSA_ALL_ONES_MASK
        fp_result = FloatingPoint(M, E)
        fp_result.set_value(res_sign, res_exponent, result_mantissa)
        return fp_result

    @staticmethod
    def mul(a, b, rounding_mode: FloatingPointRoundingMode = FloatingPointRoundingMode.NEAREST_EVEN):
        assert a.M == b.M and a.E == b.E, "Floating point formats must match for multiplication."
        M = a.M
        E = a.E

        # NaN, Infinity, Zero handling
        if a.is_nan() or b.is_nan():
            return FloatingPoint.NaN(M, E)
        if (a.is_infinity() and b.is_zero()) or (b.is_infinity() and a.is_zero()):
            return FloatingPoint.NaN(M, E)

        res_sign = a.get_sign() ^ b.get_sign()
        if a.is_infinity() or b.is_infinity():
            fp_result = FloatingPoint(M, E)
            fp_result.set_value(res_sign, a.EXPONENT_ALL_ONES_MASK, 0)
            return fp_result
        if a.is_zero() or b.is_zero():
            return FloatingPoint.ZERO(M, E, res_sign)

        # Extract mantissas with hidden bits. Subnormals use signed internal exponents.
        mantissa_a = a.get_mantissa()
        exp_a = a.get_exponent()
        if exp_a == 0:
            lz_a = (M + 1) - mantissa_a.bit_length()
            mantissa_a <<= lz_a
            exp_a = 1 - lz_a
        else:
            mantissa_a |= a.MANTISSA_HIDDEN_BIT_MASK

        mantissa_b = b.get_mantissa()
        exp_b = b.get_exponent()
        if exp_b == 0:
            lz_b = (M + 1) - mantissa_b.bit_length()
            mantissa_b <<= lz_b
            exp_b = 1 - lz_b
        else:
            mantissa_b |= b.MANTISSA_HIDDEN_BIT_MASK

        # Form the full product and select the normalized exponent.
        product = mantissa_a * mantissa_b
        product_exponent = exp_a + exp_b - a.EXPONENT_BIAS
        hidden_bit = 2 * M
        normalization_shift = product.bit_length() - 1 - hidden_bit
        res_exponent = product_exponent + normalization_shift

        # Use exponent 1 for subnormal scaling, then shift once for G/R/S.
        if res_exponent < 1:
            res_exponent = 1
        sft_to_grs = res_exponent - product_exponent + hidden_bit - M - 3
        if sft_to_grs > 0:
            product = FloatingPointGRS.rshift_jam(product, sft_to_grs)
        elif sft_to_grs < 0:
            product <<= -sft_to_grs

        grs = FloatingPointGRS()
        product = grs.set_grs_from_ext_mantissa(product)
        product = grs.apply_grs_rounding(product, res_sign, rounding_mode)

        # Realign after rounding and select the output exponent field.
        product_hidden = product >> M
        if product_hidden & 0b10:
            product >>= 1
            res_exponent += 1
        elif product_hidden == 0:
            res_exponent = 0

        # Select the overflow result before packing the fields.
        max_finite_exp = a.EXPONENT_ALL_ONES_MASK - 1
        if res_exponent > max_finite_exp:
            if (
                rounding_mode == FloatingPointRoundingMode.NEAREST_EVEN
                or (rounding_mode == FloatingPointRoundingMode.TOWARD_POSITIVE and res_sign == 0)
                or (rounding_mode == FloatingPointRoundingMode.TOWARD_NEGATIVE and res_sign == 1)
            ):
                res_exponent = a.EXPONENT_ALL_ONES_MASK
                product = 0
            else:
                res_exponent = max_finite_exp
                product = a.MANTISSA_ALL_ONES_MASK

        # Result construction
        result_mantissa = product & a.MANTISSA_ALL_ONES_MASK
        fp_result = FloatingPoint(M, E)
        fp_result.set_value(res_sign, res_exponent, result_mantissa)
        return fp_result

    @staticmethod
    def fma(a, b, c, rounding_mode: FloatingPointRoundingMode = FloatingPointRoundingMode.NEAREST_EVEN):
        assert a.M == b.M == c.M and a.E == b.E == c.E, "Floating point formats must match for FMA."
        result = FloatingPoint.fma_bits(
            a.M, a.E, a.get_binary(), b.get_binary(), c.get_binary(), rounding_mode
        )
        return FloatingPoint(a.M, a.E, result)

    @staticmethod
    def fma_bits(M, E, a, b, c,
                 rounding_mode: FloatingPointRoundingMode = FloatingPointRoundingMode.NEAREST_EVEN):
        """Compute a * b + c with one rounding, also for packed formats wider than 64 bits."""
        sign_shift = E + M
        sign_bit = 1 << sign_shift
        hidden = 1 << M
        exp_max = (1 << E) - 1
        infinity = exp_max << M
        toward_negative = rounding_mode == FloatingPointRoundingMode.TOWARD_NEGATIVE
        a_mag, b_mag, c_mag = (operand & (sign_bit - 1) for operand in (a, b, c))
        prod_sign = ((a ^ b) >> sign_shift) & 1
        c_sign = (c >> sign_shift) & 1
        prod_zero = a_mag == 0 or b_mag == 0

        # Match MultiplyAdd's canonical NaN, infinities, and signed zeros.
        if max(a_mag, b_mag, c_mag) > infinity:
            return infinity | 1
        if a_mag == infinity or b_mag == infinity:
            if prod_zero or (c_mag == infinity and prod_sign != c_sign):
                return infinity | 1
            return (prod_sign << sign_shift) | infinity
        if c_mag == infinity or (prod_zero and c_mag != 0):
            return (c_sign << sign_shift) | c_mag
        if prod_zero:
            zero_sign = prod_sign if prod_sign == c_sign else int(toward_negative)
            return zero_sign << sign_shift

        def decode(magnitude):
            exponent, fraction = divmod(magnitude, hidden)
            if exponent:
                return exponent, hidden | fraction
            shift = M + 1 - fraction.bit_length()
            return 1 - shift, fraction << shift

        # Place the full product and C at the same hidden-bit index.
        a_exp, a_mantissa = decode(a_mag)
        b_exp, b_mantissa = decode(b_mag)
        product = a_mantissa * b_mantissa
        hidden_index = 2 * M + 2
        prod_carry = product >> (hidden_index - 1)
        prod_exp = a_exp + b_exp - exp_max // 2 + prod_carry
        large = (prod_exp, product << (2 - prod_carry), prod_sign)
        small = (prod_exp, 0, c_sign)
        if c_mag:
            c_exp, c_mantissa = decode(c_mag)
            small = (c_exp, c_mantissa << (M + 2), c_sign)
        if large[:2] < small[:2]:
            large, small = small, large

        base_exp, large_mantissa, sign = large
        small_exp, small_mantissa, small_sign = small
        aligned = FloatingPointGRS.rshift_jam(small_mantissa, base_exp - small_exp)
        total = large_mantissa + aligned if sign == small_sign else large_mantissa - aligned
        if total == 0:
            return sign_bit if toward_negative else 0

        # Use exponent 1 for subnormal scaling and round the fused sum once.
        result_exp = max(1, base_exp + total.bit_length() - 1 - hidden_index)
        shift_to_grs = result_exp - base_exp + hidden_index - M - 3
        if shift_to_grs > 0:
            total = FloatingPointGRS.rshift_jam(total, shift_to_grs)
        elif shift_to_grs < 0:
            total <<= -shift_to_grs

        grs = FloatingPointGRS()
        mantissa = grs.set_grs_from_ext_mantissa(total)
        mantissa = grs.apply_grs_rounding(mantissa, sign, rounding_mode)
        if mantissa >= 2 * hidden:
            mantissa >>= 1
            result_exp += 1
        if mantissa < hidden:
            result_exp = 0

        result_sign = sign << sign_shift
        if result_exp >= exp_max:
            to_infinity = (
                rounding_mode == FloatingPointRoundingMode.NEAREST_EVEN
                or (rounding_mode == FloatingPointRoundingMode.TOWARD_POSITIVE and sign == 0)
                or (toward_negative and sign == 1)
            )
            return result_sign | (infinity if to_infinity else infinity - 1)
        return result_sign | (result_exp << M) | (mantissa & (hidden - 1))

def simple_test_fp32(f_a, f_b, f_c, expected):
    b_a, b_b, b_c, expected_binary = (
        FloatingPoint.from_fp32(value).get_binary() for value in (f_a, f_b, f_c, expected)
    )
    raw_test_fp32(b_a, b_b, b_c, FloatingPointRoundingMode.NEAREST_EVEN, expected_binary)

def raw_test_fp32(b_a, b_b, b_c, rm, expected_binary):
    fp_a = FloatingPoint(23, 8, b_a)
    fp_b = FloatingPoint(23, 8, b_b)
    fp_c = FloatingPoint(23, 8, b_c)
    fp_expected = FloatingPoint(23, 8, expected_binary)
    fp_result = FloatingPoint.fma(fp_a, fp_b, fp_c, rounding_mode=rm)

    print(f"{fp_a.to_float_str()} * {fp_b.to_float_str()} + {fp_c.to_float_str()}")
    print(f"Expected {fp_expected.to_float_str()}")
    print(f"Actual   {fp_result.to_float_str()}")
    assert fp_result.get_binary() == expected_binary


if __name__ == '__main__':
    simple_test_fp32(1.0, -1.5, 0.5, -1.0)

    rounding = FloatingPointRoundingMode
    cases = [
        # (1 + 2^-23) * (1 - 2^-23) - 1 = -2^-46 with fused rounding.
        (0x3F800001, 0x3F7FFFFE, 0xBF800000, rounding.NEAREST_EVEN, 0xA8800000),
        # The rounding mode selects the sign of (-0) + (+0).
        (0x00000000, 0xBF800000, 0x00000000, rounding.NEAREST_EVEN, 0x00000000),
        (0x00000000, 0xBF800000, 0x00000000, rounding.TOWARD_NEGATIVE, 0x80000000),
        # An infinity multiplied by zero produces the canonical NaN.
        (0x7F800000, 0x00000000, 0x3F800000, rounding.NEAREST_EVEN, 0x7F800001),
        # Positive overflow rounds to the largest finite value or infinity.
        (0x7F7FFFFF, 0x40000000, 0x3F800000, rounding.TOWARD_ZERO, 0x7F7FFFFF),
        (0x7F7FFFFF, 0x40000000, 0x3F800000, rounding.TOWARD_POSITIVE, 0x7F800000),
    ]
    for a, b, c, mode, expected in cases:
        print("\n@", mode)
        raw_test_fp32(a, b, c, mode, expected)
