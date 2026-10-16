#!/usr/bin/env python3
"""
Local copy of the LibreLane synthesis step (Yosys + ABC), no Docker, no full PDK.
Gives the same "area right after synthesis" as the GitHub flow within ~1%, in seconds.
Use it to try ideas quickly; confirm the winners with the full flow on GitHub.

  python3 synth_local.py <level single|full> <variant> [--period 20] [--lib PATH] [--keep DIR]

Needs (pip): librelane==3.0.14 pyosys==0.60 ; and the GF180 3.3 V typical liberty file
(scripts/get_gf180_lib.sh downloads and assembles it).
"""
import argparse, json, os, re, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCL = "gf180mcu_fd_sc_mcu7t5v0"

# GF180 synthesis settings, copied from open_pdks gf180mcu/librelane/*/config.tcl
PDK_VARS = {
    "PDK": "gf180mcuD",
    "STD_CELL_LIBRARY": SCL,
    "SYNTH_DRIVING_CELL": f"{SCL}__inv_1/ZN",
    "OUTPUT_CAP_LOAD": 72.91,
    "SYNTH_BUFFER_CELL": f"{SCL}__buf_1/I/Z",
    "SYNTH_TIEHI_CELL": f"{SCL}__tieh/Z",
    "SYNTH_TIELO_CELL": f"{SCL}__tiel/ZN",
    "MAX_TRANSITION_CONSTRAINT": 3,
    "MAX_FANOUT_CONSTRAINT": 10,
    "SYNTH_CLOCKGATE_POSEDGE_ICG": f"{SCL}__icgtp_1/E/CLK/Q",
    "SYNTH_CLOCKGATE_NEGEDGE_ICG": None,
}
# cells LibreLane removes from the library before synthesis (synth_exclude.cells + pnr_exclude.cells)
EXCLUDE = [f"{SCL}__{c}" for c in (
    "sdffq_1", "sdffq_2", "sdffq_4", "sdffrnq_1", "sdffrnq_2", "sdffrnq_4", "sdffrsnq_1",
    "sdffrsnq_2", "sdffrsnq_4", "sdffsnq_1", "sdffsnq_2", "sdffsnq_4",   # synth_exclude.cells
    "mux2_1", "oai33_2")]                                                    # pnr_exclude.cells


def synth_defaults():
    from librelane.steps.pyosys import Synthesis
    out = {}
    for v in Synthesis.config_vars:
        d = v.default
        out[v.name] = d.value if hasattr(d, "value") else d
    return out


def strip_cells(lib_in, work_dir, patterns):
    """Remove excluded cells exactly the way LibreLane does it."""
    from librelane.common import Toolbox
    return Toolbox(work_dir).remove_cells_from_lib(frozenset([lib_in]), excluded_cells=frozenset(patterns))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("level", choices=["single", "full"])
    ap.add_argument("variant")
    ap.add_argument("--period", default="20")
    ap.add_argument("--lib", default=os.path.join(ROOT, ".cache", "gf180", f"{SCL}__tt_025C_3v30.lib"))
    ap.add_argument("--mac", help="use this mac_unit.v instead of variants/mac_unit_<variant>.v")
    ap.add_argument("--keep", help="keep the work directory here")
    a = ap.parse_args()
    if not os.path.isfile(a.lib):
        sys.exit(f"liberty not found: {a.lib}\nrun: bash scripts/get_gf180_lib.sh")

    work = a.keep or tempfile.mkdtemp(prefix="synth_")
    os.makedirs(work, exist_ok=True)
    proj = os.path.join(work, "proj")
    subprocess.run(["bash", os.path.join(ROOT, "scripts", "prepare.sh"), a.level,
                    "orig" if a.mac else a.variant, a.period, proj], check=True, stdout=subprocess.DEVNULL)
    if a.mac:
        shutil.copy(a.mac, os.path.join(proj, "src", "mac_unit.v"))
    info = open(os.path.join(proj, "info.yaml")).read()
    top = re.search(r'top_module:\s*"(\w+)"', info).group(1)
    srcs = re.findall(r'^\s*-\s*"([\w.]+\.v)"', info, re.M)

    cfg = synth_defaults()
    cfg.update(PDK_VARS)
    user = json.loads(re.sub(r'^\s*"//".*$', "", open(os.path.join(proj, "src", "config.json")).read(), flags=re.M))
    cfg.update({k: v for k, v in user.items() if k.startswith("SYNTH_")})
    cfg.update({
        "DESIGN_NAME": top,
        "VERILOG_FILES": [os.path.join(proj, "src", s) for s in srcs],
        "CLOCK_PERIOD": float(a.period),
        "SYNTH_LATCH_MAP": None, "SYNTH_TRISTATE_MAP": None, "SYNTH_FA_MAP": None,
        "SYNTH_EXTRA_MAPPING_FILE": None,
    })
    step = os.path.join(work, "step"); os.makedirs(step, exist_ok=True)
    libs = strip_cells(a.lib, os.path.join(work, "tmp"), EXCLUDE)
    json.dump(cfg, open(os.path.join(step, "config.json"), "w"), default=str)
    json.dump({"blackbox_models": [], "libs_synth": libs}, open(os.path.join(step, "extra.json"), "w"))

    import librelane
    script = os.path.join(os.path.dirname(librelane.__file__), "scripts", "pyosys", "synthesize.py")
    out_nl = os.path.join(step, f"{top}.nl.v")
    env = dict(os.environ, PYTHONPATH=os.path.dirname(script))
    r = subprocess.run([sys.executable, script, "--output", out_nl,
                        "--config-in", os.path.join(step, "config.json"),
                        "--extra-in", os.path.join(step, "extra.json")],
                       cwd=step, env=env, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout[-3000:], r.stderr[-3000:]); sys.exit("synthesis failed")
    stat = json.load(open(os.path.join(step, "reports", "stat.json")))
    area = stat.get("design", {}).get("area") or stat["modules"][f"\\{top}"].get("area")
    cells = stat.get("design", {}).get("num_cells")
    print(json.dumps({"level": a.level, "variant": a.variant if not a.mac else os.path.basename(a.mac),
                      "synth_area_um2": round(float(area), 1), "cells": cells}))
    if not a.keep:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
