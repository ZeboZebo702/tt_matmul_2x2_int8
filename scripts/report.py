#!/usr/bin/env python3
"""
Build the comparison report from results/*.json (one file per run).

  python3 scripts/report.py results/ report/

Writes:
  report/results.csv        all numbers, one row per run (open in Excel)
  report/report.md          tables for the letter to Matt
  report/area_<level>.png   logic area vs clock period, one line per variant
  report/fmax_<level>.png   fastest clock at the slow corner, per variant
"""
import csv, glob, json, math, os, sys

VARIANTS = ["orig", "presat", "fused", "fused_eq", "tree", "hybrid", "table"]
NAMES = {"orig": "original", "presat": "presat", "fused": "fused", "fused_eq": "fused_eq", "tree": "tree", "hybrid": "hybrid", "table": "table"}
# validated categorical palette (slots 1-4), fixed order: identity never depends on rank
COLORS = {"orig": "#2a78d6", "presat": "#eb6834", "fused": "#1baf7a", "fused_eq": "#eda100", "tree": "#e87ba4",
          "hybrid": "#008300", "table": "#4a3aa7"}
COLUMNS = ["level", "variant", "period_ns", "status", "logic_area_um2", "seq_area_um2",
           "synth_area_um2", "utilization", "ws_tt_ns", "ws_ss_ns", "ws_ff_ns", "hold_ws_ns",
           "setup_violations", "fmax_tt_mhz", "fmax_ss_mhz", "metrics_from", "error"]


def num(x):
    try:
        v = float(x)
        return None if math.isnan(v) else v
    except (TypeError, ValueError):
        return None


def pct(v, base):
    if v is None or base in (None, 0):
        return ""
    return f" ({(v - base) / base * 100:+.1f}%)"


def fmt(v, nd=0):
    return "—" if v is None else f"{v:,.{nd}f}".replace(",", " ")


def load(res_dir):
    rows = [json.load(open(p)) for p in sorted(glob.glob(os.path.join(res_dir, "**", "*.json"), recursive=True))]
    return [r for r in rows if "variant" in r and "period_ns" in r]


def level_tables(rows, level):
    rs = [r for r in rows if r["level"] == level]
    if not rs:
        return ""
    variants = [v for v in VARIANTS if any(r["variant"] == v for r in rs)]
    periods = sorted({r["period_ns"] for r in rs}, reverse=True)
    by = {(r["variant"], r["period_ns"]): r for r in rs}
    title = {"single": "One MAC unit, 1x1 tile", "full": "Whole chip tt_um_essen, only mac_unit.v replaced"}[level]
    out = [f"## {title}", ""]

    # --- area at every period
    out += ["### Logic area after place & route, µm² (change vs original)", "",
            "Marks: first = typical corner (25 °C, 3.3 V), the corner Tiny Tapeout signs off; "
            "second = slow corner (125 °C, 3.0 V). ✓ meets timing, ✗ negative slack.",
            "If the slow corner fails, the tools enlarge cells trying to fix it, so the area is inflated.", "",
            "| clock | " + " | ".join(NAMES[v] for v in variants) + " |",
            "|---|" + "---|" * len(variants)]
    for p in periods:
        base = num(by.get(("orig", p), {}).get("logic_area_um2"))
        cells = []
        for v in variants:
            r = by.get((v, p))
            if not r:
                cells.append("not run"); continue
            a = num(r.get("logic_area_um2"))
            mark = lambda x: "✓" if x is not None and x >= 0 else "✗"
            ok = mark(num(r.get("ws_tt_ns"))) + mark(num(r.get("ws_ss_ns")))
            cells.append(f"{fmt(a)}{pct(a, base) if v != 'orig' else ''} {ok}")
        out.append(f"| {p:g} ns ({1000 / p:.0f} MHz) | " + " | ".join(cells) + " |")
    out.append("")

    # --- area right after synthesis (before the tools add buffers / upsize cells for timing)
    out += ["### Area right after synthesis, µm² (before timing repair)", "",
            "| clock | " + " | ".join(NAMES[v] for v in variants) + " |",
            "|---|" + "---|" * len(variants)]
    for p in periods:
        base = num(by.get(("orig", p), {}).get("synth_area_um2"))
        cells = []
        for v in variants:
            a = num(by.get((v, p), {}).get("synth_area_um2"))
            cells.append(f"{fmt(a)}{pct(a, base) if v != 'orig' else ''}")
        out.append(f"| {p:g} ns | " + " | ".join(cells) + " |")
    out.append("")

    # --- slack at every period
    out += ["### Worst setup slack, ns: typical / slow corner", "",
            "| clock | " + " | ".join(NAMES[v] for v in variants) + " |",
            "|---|" + "---|" * len(variants)]
    for p in periods:
        cells = []
        for v in variants:
            r = by.get((v, p), {})
            cells.append(f"{fmt(num(r.get('ws_tt_ns')), 2)} / {fmt(num(r.get('ws_ss_ns')), 2)}" if r else "—")
        out.append(f"| {p:g} ns | " + " | ".join(cells) + " |")
    out.append("")

    # --- summary
    out += ["### Summary", "",
            "| variant | area at slowest clock, µm² | shortest period passing at tt / ss | fmax tt, MHz (best estimate) | fmax ss, MHz (best estimate) |",
            "|---|---|---|---|---|"]
    pmax = periods[0]
    base = num(by.get(("orig", pmax), {}).get("logic_area_um2"))
    for v in variants:
        a = num(by.get((v, pmax), {}).get("logic_area_um2"))
        def shortest(key):
            ok = [p for p in periods if num(by.get((v, p), {}).get(key)) is not None and num(by[(v, p)][key]) >= 0]
            return f"{min(ok):g} ns" if ok else "none"
        fss = [num(r.get("fmax_ss_mhz")) for r in rs if r["variant"] == v and num(r.get("fmax_ss_mhz"))]
        ftt = [num(r.get("fmax_tt_mhz")) for r in rs if r["variant"] == v and num(r.get("fmax_tt_mhz"))]
        out.append(f"| {NAMES[v]} | {fmt(a)}{pct(a, base) if v != 'orig' else ''} | "
                   f"{shortest('ws_tt_ns')} / {shortest('ws_ss_ns')} | "
                   f"{fmt(max(ftt) if ftt else None, 1)} | {fmt(max(fss) if fss else None, 1)} |")
    out.append("")
    failed = [r for r in rs if r.get("status") != "ok"]
    if failed:
        out += ["Runs where the flow stopped early (numbers taken from the last finished step):", ""]
        out += [f"- {r['variant']} @ {r['period_ns']:g} ns: {r.get('status')} — {r.get('error') or ''}" for r in failed]
        out.append("")
    return "\n".join(out)


def plots(rows, level, out_dir):
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        print("matplotlib not installed: skipping charts")
        return
    rs = [r for r in rows if r["level"] == level and num(r.get("logic_area_um2"))]
    if not rs:
        return
    variants = [v for v in VARIANTS if any(r["variant"] == v for r in rs)]
    ink, muted, grid = "#0b0b0b", "#52514e", "#e6e5e0"
    plt.rcParams.update({"font.size": 10, "axes.edgecolor": grid, "axes.labelcolor": muted,
                         "xtick.color": muted, "ytick.color": muted})

    # area vs period
    fig, ax = plt.subplots(figsize=(7.5, 4.5), dpi=150)
    for v in variants:
        pts = sorted((r["period_ns"], num(r["logic_area_um2"]), num(r.get("ws_ss_ns"))) for r in rs if r["variant"] == v)
        xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
        ax.plot(xs, ys, color=COLORS[v], linewidth=2, label=NAMES[v], zorder=2)
        for x, y, ws in pts:
            ok = ws is not None and ws >= 0
            ax.scatter([x], [y], s=40, zorder=3, color=COLORS[v] if ok else "white",
                       edgecolors=COLORS[v], linewidths=2)
    ax.set_xlabel("clock period, ns  (smaller = faster)")
    ax.set_ylabel("logic area, µm²")
    ax.grid(True, color=grid, linewidth=0.8); ax.set_axisbelow(True)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    ax.set_title({"single": "One MAC unit", "full": "Whole chip tt_um_essen"}[level]
                 + ": area vs clock period\nfilled dot = meets timing at slow corner too, hollow = slow corner fails",
                 color=ink, fontsize=11, loc="left")
    ax.legend(frameon=False, loc="upper right")
    ax.margins(x=0.12)
    fig.tight_layout(); fig.savefig(os.path.join(out_dir, f"area_{level}.png")); plt.close(fig)

    # fmax at slow corner
    fig, ax = plt.subplots(figsize=(6, 3.6), dpi=150)
    vals = []
    for v in variants:
        f = [num(r.get("fmax_ss_mhz")) for r in rs if r["variant"] == v and num(r.get("fmax_ss_mhz"))]
        vals.append(max(f) if f else 0)
    bars = ax.bar([NAMES[v] for v in variants], vals, color=[COLORS[v] for v in variants], width=0.55)
    for b, val in zip(bars, vals):
        ax.annotate(f"{val:.0f} MHz", (b.get_x() + b.get_width() / 2, val), xytext=(0, 4),
                    textcoords="offset points", ha="center", color=ink, fontsize=9)
    ax.set_ylabel("MHz")
    ax.grid(True, axis="y", color=grid, linewidth=0.8); ax.set_axisbelow(True)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    ax.set_title("Fastest clock at slow corner (ss, 125 °C, 3.0 V), best estimate",
                 color=ink, fontsize=11, loc="left")
    fig.tight_layout(); fig.savefig(os.path.join(out_dir, f"fmax_{level}.png")); plt.close(fig)


def main():
    res_dir = sys.argv[1] if len(sys.argv) > 1 else "results"
    out_dir = sys.argv[2] if len(sys.argv) > 2 else "report"
    os.makedirs(out_dir, exist_ok=True)
    rows = load(res_dir)
    if not rows:
        sys.exit(f"no results in {res_dir}")
    with open(os.path.join(out_dir, "results.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=COLUMNS, extrasaction="ignore")
        w.writeheader()
        for r in sorted(rows, key=lambda r: (r["level"], VARIANTS.index(r["variant"]) if r["variant"] in VARIANTS else 9, -r["period_ns"])):
            w.writerow(r)
    md = ["# MAC arithmetic: area and timing, GF180 (Tiny Tapeout flow)", "",
          "Same tools, same settings, same PDK for every run; only the arithmetic of mac_unit.v differs.", ""]
    for level in ("single", "full"):
        t = level_tables(rows, level)
        if t:
            md.append(t)
            plots(rows, level, out_dir)
            if os.path.exists(os.path.join(out_dir, f"area_{level}.png")):
                md += [f"![area {level}](area_{level}.png)", "", f"![fmax {level}](fmax_{level}.png)", ""]
    open(os.path.join(out_dir, "report.md"), "w").write("\n".join(md))
    print("\n".join(md))


if __name__ == "__main__":
    main()
