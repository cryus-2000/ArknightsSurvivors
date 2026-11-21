"""UnityPy + 方舟 LZ4AK（块压缩标志 4 = 'LZHAM' 位，实为 LZ4 变体：token 高低半字节互换、匹配偏移大端）。"""
import UnityPy
from UnityPy.helpers import CompressionHelper
from UnityPy.enums.BundleFile import CompressionFlags


def lz4ak(data: bytes, usize: int) -> bytes:
    src = memoryview(data)
    out = bytearray()
    i = 0
    n = len(src)
    while i < n:
        tok = src[i]; i += 1
        lit = tok & 0x0F          # 方舟：低半字节 = 字面量长度
        ml = tok >> 4             # 高半字节 = 匹配长度
        if lit == 15:
            while True:
                b = src[i]; i += 1
                lit += b
                if b != 255:
                    break
        out += src[i:i + lit]; i += lit
        if i >= n:
            break
        off = (src[i] << 8) | src[i + 1]; i += 2   # 大端
        if ml == 15:
            while True:
                b = src[i]; i += 1
                ml += b
                if b != 255:
                    break
        ml += 4
        st = len(out) - off
        if off >= ml:
            out += out[st:st + ml]
        else:
            for k in range(ml):
                out.append(out[st + k])
    return bytes(out[:usize])


def install():
    CompressionHelper.DECOMPRESSION_MAP[CompressionFlags.LZHAM] = lz4ak


install()
