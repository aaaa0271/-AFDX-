"""Generate report figures into report_20261020/figures/.

Run from project root:  python report_tools/make_figures.py
"""
import csv
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch

ROOT = Path(__file__).resolve().parents[1]
FIG = ROOT / "results/report" / "figures"
DATA = ROOT / "results/report" / "data"
FIG.mkdir(parents=True, exist_ok=True)

plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei", "DejaVu Sans"]
plt.rcParams["axes.unicode_minus"] = False


def box(ax, xy, w, h, title, lines=(), fc="#eef3fb", ec="#3b6ea5", title_size=10, body_size=8.2):
    x, y = xy
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.012,rounding_size=0.02",
                                linewidth=1.1, edgecolor=ec, facecolor=fc))
    ax.text(x + w / 2, y + h - 0.018, title, ha="center", va="top", fontsize=title_size, fontweight="bold")
    if lines:
        ax.text(x + w / 2, y + h - 0.062, "\n".join(lines), ha="center", va="top",
                fontsize=body_size, color="#33475b", linespacing=1.35)


def arrow(ax, a, b, text="", color="#3b6ea5", ls="-", size=8):
    ax.add_patch(FancyArrowPatch(a, b, arrowstyle="-|>", mutation_scale=9, linewidth=1.0,
                                 color=color, linestyle=ls, shrinkA=1, shrinkB=1))
    if text:
        ax.text((a[0] + b[0]) / 2, (a[1] + b[1]) / 2 + 0.014, text, ha="center", fontsize=size, color="#33475b")


def architecture():
    fig, ax = plt.subplots(figsize=(10.0, 5.8))
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")

    ax.add_patch(FancyBboxPatch((0.015, 0.30), 0.62, 0.67, boxstyle="round,pad=0.006",
                                linewidth=1.4, edgecolor="#1f3b57", facecolor="none", linestyle="--"))
    ax.text(0.025, 0.978, "AFDX_defense_top（RTL 统一防御顶层）", fontsize=11.5, fontweight="bold", color="#1f3b57")

    ax.add_patch(FancyBboxPatch((0.655, 0.30), 0.33, 0.67, boxstyle="round,pad=0.006",
                                linewidth=1.4, edgecolor="#5a5a5a", facecolor="none", linestyle="--"))
    ax.text(0.665, 0.978, "主机侧（Python，无 GPU/云）", fontsize=11.5, fontweight="bold", color="#4a4a4a")

    box(ax, (0.025, 0.72), 0.085, 0.15, "A/B 字节流", ["rx/tx", "data·valid"], fc="#f6f7f9", ec="#8a8a8a")
    box(ax, (0.025, 0.47), 0.085, 0.15, "配置/事件", ["cfg_*", "sec_event"], fc="#f6f7f9", ec="#8a8a8a")

    box(ax, (0.135, 0.71), 0.16, 0.18, "安全插件",
        ["ACL/配额/授权", "SHA-256 · A/B 比对"], fc="#e8f1e4", ec="#4e7d3a")
    box(ax, (0.315, 0.71), 0.14, 0.18, "拟态裁决",
        ["2-of-3 语义", "原引擎否决优先"], fc="#efe8f6", ec="#6a4c93")
    box(ax, (0.135, 0.38), 0.25, 0.25, "AFDX 核心",
        ["VL/BAG/序号/分片", "SNMP · 615A · RTC"], fc="#eef3fb")
    box(ax, (0.415, 0.38), 0.19, 0.25, "AI 控制",
        ["计数/事件→特征", "TCN：候选+风险+p95"], fc="#fdf1e3", ec="#b0711f")

    box(ax, (0.67, 0.71), 0.14, 0.16, "智能体", ["诊断/工具/复核"], fc="#f7f7f7", ec="#6b6b6b")
    box(ax, (0.835, 0.71), 0.14, 0.16, "模型", ["3 个冻结小模型"], fc="#f7f7f7", ec="#6b6b6b")
    box(ax, (0.67, 0.50), 0.14, 0.16, "拟态编排", ["4 执行器/DHR"], fc="#f7f7f7", ec="#6b6b6b")
    box(ax, (0.835, 0.50), 0.14, 0.16, "授权", ["Ed25519/证据"], fc="#f7f7f7", ec="#6b6b6b")

    arrow(ax, (0.110, 0.795), (0.135, 0.795), "A/B")
    arrow(ax, (0.295, 0.80), (0.315, 0.80), "合规帧")
    arrow(ax, (0.315, 0.735), (0.385, 0.63), "裁决后")
    arrow(ax, (0.295, 0.74), (0.135, 0.63), "业务/管理")
    arrow(ax, (0.385, 0.50), (0.415, 0.50), "指标/事件", color="#b0711f")
    arrow(ax, (0.605, 0.47), (0.67, 0.62), "推理结果", color="#b0711f", ls="--")
    arrow(ax, (0.74, 0.71), (0.605, 0.55), "策略候选", color="#6b6b6b", ls="--")
    arrow(ax, (0.110, 0.54), (0.135, 0.47), "配置", color="#6b6b6b", ls="--")

    box(ax, (0.025, 0.05), 0.30, 0.18, "AFDX_top（8 端口演示壳）",
        ["clk/reset/tx/rx/valid/ready", "内置启动配置 + 演示源"], fc="#f6f7f9", ec="#8a8a8a")
    ax.text(0.34, 0.12, "完整可配置入口：AFDX_defense_top\n最小接口演示：AFDX_top",
            fontsize=8.5, color="#4a4a4a", va="center")

    fig.tight_layout()
    out = FIG / "fig1_architecture.png"
    fig.savefig(out, dpi=220, bbox_inches="tight", pad_inches=0.09, facecolor="white")
    plt.close(fig)
    print("wrote", out)


def suite_chart():
    f = DATA / "per_test.csv"
    if not f.is_file():
        print("skip suite chart: no per_test.csv")
        return
    rows = [r for r in csv.DictReader(f.open(encoding="utf-8"))
            if r["name"] != "tb_defense_live" and r["suite"] != "skeleton"]
    suites = {}
    for r in rows:
        s = suites.setdefault(r["suite"], {"pass": 0, "fail": 0})
        s["pass" if r["status"] == "PASS" else "fail"] += 1
    names = list(suites)
    pas = [suites[k]["pass"] for k in names]
    fail = [suites[k]["fail"] for k in names]
    fig, ax = plt.subplots(figsize=(9.0, 3.8))
    ax.bar(names, pas, color="#4e7d3a", label="PASS")
    ax.bar(names, fail, bottom=pas, color="#b03a2e", label="FAIL")
    for i, (p, q) in enumerate(zip(pas, fail)):
        ax.text(i, p + q + 0.3, f"{p}/{p + q}", ha="center", fontsize=9)
    ax.set_ylabel("用例数")
    ax.set_title("本机 Windows 环境全量回归（按套件）")
    ax.legend()
    ax.tick_params(axis="x", rotation=20)
    fig.tight_layout()
    out = FIG / "fig2_suite_results.png"
    fig.savefig(out, dpi=220, bbox_inches="tight", pad_inches=0.05, facecolor="white")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    architecture()
    suite_chart()
