#!/usr/bin/env python3
"""
gen_pla.py — генератор таблиц истинности (формат PLA) для целочисленной
арифметики: умножение, сложение, вычитание, умножение-со-сложением (FMA).

Числа: знаковые (дополнительный код) или беззнаковые, любая разрядность.
Переполнение: насыщение (sat), обрезка (wrap) или точный результат (full).

Отдельный режим `system` строит набор таблиц, который ТОЧНО повторяет
вычисление одного элемента матрицы 2x2 в чипе tt_um_essen (Systolic_MAC_with_DFT).

Запуск:  python3 gen_pla.py --help
"""
import argparse, itertools, os, sys

# ----------------------------------------------------------------------------
# Диапазоны и перевод чисел в биты
# ----------------------------------------------------------------------------
def rng(width, signed):
    """Наименьшее и наибольшее число для данной разрядности."""
    if signed:
        return -(1 << (width - 1)), (1 << (width - 1)) - 1
    return 0, (1 << width) - 1

def to_bits(value, width):
    """Число -> строка бит (старший бит слева). Отрицательные — в доп. коде."""
    return format(value & ((1 << width) - 1), "0{}b".format(width))

def min_width(lo, hi, signed):
    """Сколько бит нужно, чтобы без потерь записать все числа из [lo, hi]."""
    w = 1
    while True:
        a, b = rng(w, signed)
        if a <= lo and hi <= b:
            return w
        w += 1

# ----------------------------------------------------------------------------
# Операции. Каждая получает кортеж входных чисел и возвращает точный результат.
# ----------------------------------------------------------------------------
OPS = {
    "mul": (2, lambda x: x[0] * x[1],        "R = A*B"),
    "add": (2, lambda x: x[0] + x[1],        "R = A+B"),
    "sub": (2, lambda x: x[0] - x[1],        "R = A-B"),
    "fma": (3, lambda x: x[0] * x[1] + x[2], "R = A*B+C"),
}

def exact_range(op, widths, signed):
    """Диапазон точного результата. Для mul/add/sub/fma крайние значения
    достигаются в 'углах' (входы равны своим min или max) — перебираем углы."""
    f = OPS[op][1]
    corners = itertools.product(*[rng(w, signed) for w in widths])
    vals = [f(c) for c in corners]
    return min(vals), max(vals)

def finish(value, mode, out_w, signed):
    """Приводим точный результат к выходной разрядности."""
    lo, hi = rng(out_w, signed)
    if mode == "sat":                 # насыщение: зажимаем в диапазон
        return max(lo, min(hi, value))
    return value                      # wrap/full: просто берём младшие биты

# ----------------------------------------------------------------------------
# Запись PLA
# ----------------------------------------------------------------------------
def write_pla(path, op, widths, names, out_w, out_name, mode, signed, comment=""):
    nin = len(widths)
    lo_in = [rng(w, signed) for w in widths]
    f = OPS[op][1]
    n_in_bits = sum(widths)
    rows = 1 << n_in_bits

    # Готовые строки бит для каждого возможного значения каждого входа
    # (перебор идёт по битовому коду 0..2^w-1, как в обычной таблице истинности)
    def code_to_val(code, w):
        if signed and code >= (1 << (w - 1)):
            return code - (1 << w)
        return code
    tables = [[(format(c, "0{}b".format(w)), code_to_val(c, w)) for c in range(1 << w)]
              for w in widths]

    ilb = " ".join("{}{}".format(n, i) for n, w in zip(names, widths)
                   for i in range(w - 1, -1, -1))
    ob = " ".join("{}{}".format(out_name, i) for i in range(out_w - 1, -1, -1))
    lo, hi = rng(out_w, signed)

    out = open(path, "w") if path != "-" else sys.stdout
    kind = "signed, two's complement" if signed else "unsigned"
    ins = ", ".join("{}: {}-bit".format(n.upper(), w) for n, w in zip(names, widths))
    out.write("# {} ({}), mode={}\n".format(OPS[op][2], kind, mode))
    out.write("# inputs {};  output {}-bit, range [{}, {}]\n".format(ins, out_w, lo, hi))
    if comment:
        for line in comment.strip().splitlines():
            out.write("# " + line + "\n")
    out.write(".i {}\n.o {}\n.ilb {}\n.ob {}\n.type fr\n.p {}\n".format(
        n_in_bits, out_w, ilb, ob, rows))
    for combo in itertools.product(*tables):
        bits = "".join(c[0] for c in combo)
        r = finish(f(tuple(c[1] for c in combo)), mode, out_w, signed)
        out.write(bits + " " + to_bits(r, out_w) + "\n")
    out.write(".e\n")
    if out is not sys.stdout:
        out.close()
    return rows

# ----------------------------------------------------------------------------
# Проверка: читаем PLA и сверяем каждую строку с эталоном
# ----------------------------------------------------------------------------
def check_pla(path, op, widths, out_w, mode, signed):
    f = OPS[op][1]
    def val(bits):
        v = int(bits, 2)
        return v - (1 << len(bits)) if signed and bits[0] == "1" else v
    bad = n = 0
    for line in open(path):
        line = line.strip()
        if not line or line[0] in "#.":
            continue
        ib, ob = line.split()
        xs, pos = [], 0
        for w in widths:
            xs.append(val(ib[pos:pos + w])); pos += w
        exp = to_bits(finish(f(tuple(xs)), mode, out_w, signed), out_w)
        n += 1
        bad += (ob != exp)
    return n, bad

# ----------------------------------------------------------------------------
# Режим system: точная модель элемента матрицы 2x2 чипа tt_um_essen
#   r = clamp_n( i1*w1 + clamp_n( i0*w0 ) )
# раскладывается БЕЗ ошибок на три таблицы:
#   T1: p0 = clamp_n  (i0*w0)            (верхний блок, ему сверху приходит 0)
#   T2: p1 = clamp_n+1(i1*w1)            (нижний блок, произведение на 1 бит шире)
#   T3: r  = clamp_n  (p1 + p0)          (сложение (n+1)-битного и n-битного)
# Почему n+1 бит хватает: если |i1*w1| >= 2^n, то никакое n-битное p0 уже не
# вернёт сумму в диапазон — ответ всё равно будет насыщен.
# ----------------------------------------------------------------------------
def system(n, outdir, verify):
    os.makedirs(outdir, exist_ok=True)
    files = []
    p = os.path.join(outdir, "T1_mul_sat{}_{}bit.pla".format(n, n))
    write_pla(p, "mul", [n, n], ["a", "b"], n, "r", "sat", True,
              "T1: upper MAC unit (top input = 0): p0 = clamp_{}(a*b)".format(n)); files.append(p)
    p = os.path.join(outdir, "T2_mul_sat{}_{}bit.pla".format(n + 1, n))
    write_pla(p, "mul", [n, n], ["a", "b"], n + 1, "p", "sat", True,
              "T2: lower MAC unit, product pre-saturated to {} bits: p1 = clamp_{}(a*b)".format(n + 1, n + 1)); files.append(p)
    p = os.path.join(outdir, "T3_add_sat{}_{}p{}bit.pla".format(n, n + 1, n))
    write_pla(p, "add", [n + 1, n], ["p", "c"], n, "r", "sat", True,
              "T3: R = clamp_{}(P + C), P = output of T2, C = output of T1".format(n)); files.append(p)
    for f in files:
        print("  записан", f)
    if verify:
        print("  проверка: T3(T2(a,b), c) == clamp(a*b + c) для всех a, b, c ...")
        lo, hi = rng(n, True)
        lo1, hi1 = rng(n + 1, True)
        bad = 0
        for a in range(lo, hi + 1):
            for b in range(lo, hi + 1):
                pr = a * b
                p1 = max(lo1, min(hi1, pr))
                for c in range(lo, hi + 1):
                    if max(lo, min(hi, p1 + c)) != max(lo, min(hi, pr + c)):
                        bad += 1
        print("  ошибок:", bad)

# ----------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(
        description="Генератор таблиц истинности (PLA) для целочисленной арифметики.")
    ap.add_argument("op", choices=list(OPS) + ["system"],
                    help="mul | add | sub | fma | system (набор таблиц для элемента матрицы чипа)")
    ap.add_argument("-n", "--width", type=int, default=8, help="разрядность входов (по умолчанию 8)")
    ap.add_argument("--wa", type=int, help="разрядность A (если отличается от -n)")
    ap.add_argument("--wb", type=int, help="разрядность B")
    ap.add_argument("--wc", type=int, help="разрядность C (только для fma)")
    ap.add_argument("--unsigned", action="store_true", help="беззнаковые числа (по умолчанию — знаковые)")
    ap.add_argument("--mode", choices=["sat", "wrap", "full"], default="sat",
                    help="sat — насыщение, wrap — обрезка старших бит, full — точный результат")
    ap.add_argument("-m", "--out-width", type=int,
                    help="разрядность результата (по умолчанию: n для sat/wrap, минимально нужная для full)")
    ap.add_argument("-o", "--output", default=None, help="имя файла ('-' = в консоль); для system — папка")
    ap.add_argument("--check", action="store_true", help="после записи перепроверить каждую строку")
    ap.add_argument("--force", action="store_true", help="разрешить таблицы больше 2^20 строк")
    a = ap.parse_args()
    n = a.width

    if a.op == "system":
        if 3 * n > 24 and not a.force:
            sys.exit("n > 8: проверка займёт очень долго; добавьте --force")
        system(n, a.output or "system_{}bit".format(n), verify=True)
        return

    nargs = OPS[a.op][0]
    widths = [a.wa or n, a.wb or n] + ([a.wc or n] if nargs == 3 else [])
    names = ["a", "b", "c"][:nargs]
    signed = not a.unsigned
    lo, hi = exact_range(a.op, widths, signed)
    if a.mode == "full":
        if not signed and lo < 0:   # беззнаковое вычитание может уйти в минус
            sys.exit("беззнаковое вычитание даёт отрицательные числа: используйте sat или wrap")
        out_w = a.out_width or min_width(lo, hi, signed)
    else:
        out_w = a.out_width or n

    rows = 1 << sum(widths)
    if rows > (1 << 20) and not a.force:
        size_mb = rows * (sum(widths) + out_w + 2) / 1e6
        sys.exit("Таблица: {} строк (~{:.0f} МБ). Добавьте --force, если это нужно.".format(rows, size_mb))

    tag = "{}_{}{}_{}bit".format(a.op, a.mode, out_w, "x".join(map(str, widths)))
    if a.unsigned:
        tag += "_u"
    path = a.output or tag + ".pla"
    write_pla(path, a.op, widths, names, out_w, "r", a.mode, signed)
    if path != "-":
        print("записан {}: {} строк, вход {} бит, выход {} бит".format(path, rows, sum(widths), out_w))
        print("точный результат лежит в [{}, {}]".format(lo, hi))
        if a.check:
            cnt, bad = check_pla(path, a.op, widths, out_w, a.mode, signed)
            print("проверка: {} строк, ошибок {}".format(cnt, bad))

if __name__ == "__main__":
    main()
