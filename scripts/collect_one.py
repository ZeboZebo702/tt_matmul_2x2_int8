#!/usr/bin/env python3
"""
Collect the numbers of one LibreLane run into one small JSON file.

What is measured
  area
    logic_area_um2   area of all logic cells after placement and routing
                     (gates, flip-flops, buffers added by the tools),
                     WITHOUT filler / tap / end-cap / decap / antenna cells,
                     which only fill empty space. This is the number to compare.
    synth_area_um2   area right after synthesis (before buffers and resizing)
    seq_area_um2     part of logic_area that is flip-flops
  timing (static timing analysis after routing, real wires)
    ws_tt_ns         worst setup slack, typical corner (25 C, 3.3 V)
    ws_ss_ns         worst setup slack, slow corner (125 C, 3.0 V), the worst of nom/min/max wires
    ws_ff_ns         worst setup slack, fast corner
    slack > 0  -> the design meets the clock period with this much spare time
    fmax_*_mhz       estimate 1000 / (period - slack): the fastest clock at that corner

If the flow stopped early (for example on a timing violation), the numbers are
taken from the last step that finished, and "status" says so.
"""
import argparse, csv, glob, json, os, re, sys
from collections import Counter

PHYSICAL_ONLY = re.compile(r"__(fill|filltie|fillcap|endcap|decap|antenna|tap)", re.I)
SEQUENTIAL = re.compile(r"__(dff|sdff|latch|icgt)", re.I)
CELL_INST = re.compile(r"^\s*(gf180mcu_fd_sc_\w+)\s+\\?\S+\s*\(", re.M)


def load_metrics(run_dir):
    """Final metrics if the flow finished, otherwise those of the last finished step."""
    final = os.path.join(run_dir, "final", "metrics.json")
    if os.path.isfile(final):
        return json.load(open(final)), "final"
    steps = sorted(glob.glob(os.path.join(run_dir, "*-*", "state_out.json")),
                   key=lambda p: int(os.path.basename(os.path.dirname(p)).split("-")[0]))
    if not steps:
        return {}, None
    last = steps[-1]
    return json.load(open(last)).get("metrics", {}), os.path.basename(os.path.dirname(last))


def step_metrics(run_dir, pattern):
    hits = sorted(glob.glob(os.path.join(run_dir, f"*-{pattern}", "state_out.json")))
    return json.load(open(hits[-1])).get("metrics", {}) if hits else {}


def last_netlist(run_dir):
    cands = glob.glob(os.path.join(run_dir, "final", "nl", "*.nl.v"))
    if not cands:
        cands = sorted(glob.glob(os.path.join(run_dir, "*-*", "*.nl.v")),
                       key=lambda p: int(os.path.basename(os.path.dirname(p)).split("-")[0]))
    return cands[-1] if cands else None


def find_liberty(run_dir):
    """Typical-corner GF180 cell library: path from resolved.json, else search the PDK cache."""
    name = "gf180mcu_fd_sc_mcu7t5v0__tt_025C_3v30.lib"
    try:
        res = json.load(open(os.path.join(run_dir, "resolved.json")))
        for v in json.dumps(res).split('"'):
            if v.endswith(name) and os.path.isfile(v):
                return v
    except Exception:
        pass
    roots = [os.environ.get("PDK_ROOT", ""), os.path.expanduser("~/.ciel"), os.path.expanduser("~/.volare")]
    for r in roots:
        if r and os.path.isdir(r):
            hits = glob.glob(os.path.join(r, "**", name), recursive=True)
            if hits:
                return hits[0]
    return None


def cell_areas(lib_path):
    areas, cell = {}, None
    for line in open(lib_path, errors="ignore"):
        m = re.match(r"\s*cell\s*\(\s*\"?([\w]+)\"?\s*\)", line)
        if m:
            cell = m.group(1)
            continue
        m = re.match(r"\s*area\s*:\s*([0-9.]+)", line)
        if m and cell and cell not in areas:
            areas[cell] = float(m.group(1))
    return areas


def netlist_area(nl_path, areas):
    counts = Counter(CELL_INST.findall(open(nl_path, errors="ignore").read()))
    logic = seq = phys = 0.0
    n_logic = 0
    missing = set()
    for cell, n in counts.items():
        a = areas.get(cell)
        if a is None:
            missing.add(cell)
            continue
        if PHYSICAL_ONLY.search(cell):
            phys += a * n
        else:
            logic += a * n
            n_logic += n
            if SEQUENTIAL.search(cell):
                seq += a * n
    return dict(logic_area_um2=round(logic, 1), seq_area_um2=round(seq, 1),
                physical_only_area_um2=round(phys, 1), logic_cell_count=n_logic,
                unknown_cells=sorted(missing))


def corner_ws(metrics, kind, key="timing__setup__ws"):
    vals = [float(v) for k, v in metrics.items()
            if k.startswith(key + "__corner:") and f"_{kind}_" in k]
    return min(vals) if vals else None


def first_error(log_path):
    if not log_path or not os.path.isfile(log_path):
        return None
    for line in open(log_path, errors="ignore"):
        if re.search(r"\b(ERROR|Error|error)\b", line) and "error(s)" not in line:
            return line.strip()[:300]
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-dir", required=True)
    ap.add_argument("--level", required=True)
    ap.add_argument("--variant", required=True)
    ap.add_argument("--period", type=float, required=True)
    ap.add_argument("--status", default="ok")
    ap.add_argument("--log")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    r = dict(level=a.level, variant=a.variant, period_ns=a.period, status=a.status)
    m, source = load_metrics(a.run_dir)
    r["metrics_from"] = source

    synth = step_metrics(a.run_dir, "yosys-synthesis")
    r["synth_area_um2"] = synth.get("design__instance__area")

    r["openroad_instance_area_um2"] = m.get("design__instance__area")
    r["utilization"] = m.get("design__instance__utilization")
    r["ws_tt_ns"] = corner_ws(m, "tt")
    r["ws_ss_ns"] = corner_ws(m, "ss")
    r["ws_ff_ns"] = corner_ws(m, "ff")
    holds = [float(v) for k, v in m.items() if k.startswith("timing__hold__ws__corner:")]
    r["hold_ws_ns"] = min(holds) if holds else None
    r["setup_violations"] = m.get("timing__setup_vio__count")
    for c in ("tt", "ss"):
        ws = r[f"ws_{c}_ns"]
        r[f"fmax_{c}_mhz"] = round(1000.0 / (a.period - ws), 1) if ws is not None and a.period - ws > 0 else None

    nl = last_netlist(a.run_dir)
    lib = find_liberty(a.run_dir)
    if nl and lib:
        r.update(netlist_area(nl, cell_areas(lib)))
    else:
        r["logic_area_um2"] = None
        r["note"] = f"netlist={nl} liberty={lib}"

    if a.status != "ok":
        r["error"] = first_error(a.log)

    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    json.dump(r, open(a.out, "w"), indent=2)
    print(json.dumps(r, indent=2))


if __name__ == "__main__":
    main()
