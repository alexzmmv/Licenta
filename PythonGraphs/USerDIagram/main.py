#!/usr/bin/env python3
"""
Generate a left-to-right, grayscale, publication-quality architecture diagram
for an on-device microjournaling application.

Outputs:
  - figures/architecture.pdf  (vector PDF for LaTeX)
  - figures/architecture.png  (300 DPI preview)

Dependencies:
  - Python 3
  - matplotlib
  - numpy

Run:
  python3 generate_architecture.py
"""

import os
import math
import matplotlib.pyplot as plt
import matplotlib.patches as patches
import numpy as np

OUTPUT_DIR = "figures"
PDF_NAME = "architecture.pdf"
PNG_NAME = "architecture.png"

def ensure_dir(path):
    os.makedirs(path, exist_ok=True)

def rounded_box(ax, x, y, w, h, label, fontsize=10, linewidth=1.0):
    box = patches.FancyBboxPatch(
        (x, y), w, h,
        boxstyle="round,pad=0.3",
        linewidth=linewidth,
        edgecolor="black",
        facecolor="#f2f2f2"
    )
    ax.add_patch(box)
    ax.text(x + w/2, y + h/2, label, ha="center", va="center",
            fontsize=fontsize, color="black", wrap=True)

def draw_arrow(ax, start, end, style='solid', lw=1.0):
    # Draw straight arrow with head
    dx = end[0] - start[0]
    dy = end[1] - start[1]
    ax.annotate("",
                xy=end, xytext=start,
                arrowprops=dict(arrowstyle="->",
                                linewidth=lw,
                                color="black",
                                linestyle=style,
                                shrinkA=5, shrinkB=5))

def create_diagram():
    ensure_dir(OUTPUT_DIR)

    # A4 landscape approx 11.7 x 8.3 inches
    fig_w, fig_h = 11.7, 8.3
    fig, ax = plt.subplots(figsize=(fig_w, fig_h))
    ax.set_xlim(0, 12)
    ax.set_ylim(0, 8)
    ax.axis('off')

    # Layout parameters (left-to-right)
    margin_x = 0.6
    margin_y = 0.8
    box_w = 1.6
    box_h = 0.9
    gap_x = 0.8
    center_y = 4.0

    # Positions (x, y)
    x0 = margin_x
    ui_pos = (x0, center_y - box_h/2)
    persistence_pos = (x0 + (box_w + gap_x), center_y - box_h/2)
    datastore_pos = (persistence_pos[0] + (box_w + gap_x), center_y - box_h/2)
    inference_pos = (datastore_pos[0] + (box_w + gap_x), center_y - box_h/2)
    clustering_pos = (inference_pos[0] + (box_w + gap_x), center_y - box_h/2)
    scheduler_pos = (clustering_pos[0] + (box_w + gap_x), center_y - box_h/2)
    export_pos = (scheduler_pos[0] + (box_w + gap_x), center_y - box_h/2)

    # Device Security above UI and Persistence
    sec_w = 2.2
    sec_h = 0.7
    sec_x = ui_pos[0] - 0.2
    sec_y = ui_pos[1] + box_h + 0.6
    security_pos = (sec_x, sec_y)

    # Draw boxes (grayscale, consistent)
    label_fs = 10
    rounded_box(ax, ui_pos[0], ui_pos[1], box_w, box_h, "UI\n(SwiftUI)", fontsize=label_fs)
    rounded_box(ax, persistence_pos[0], persistence_pos[1], box_w, box_h, "Persistence\n(SwiftData)", fontsize=label_fs)
    rounded_box(ax, datastore_pos[0], datastore_pos[1], box_w, box_h, "Data Store\n(Encrypted DB)", fontsize=label_fs)
    rounded_box(ax, inference_pos[0], inference_pos[1], box_w, box_h, "Inference Engine\n(Core ML)", fontsize=label_fs)
    rounded_box(ax, clustering_pos[0], clustering_pos[1], box_w, box_h, "Clustering Engine", fontsize=label_fs)
    rounded_box(ax, scheduler_pos[0], scheduler_pos[1], box_w, box_h, "Scheduler /\nBackground Worker", fontsize=label_fs)
    rounded_box(ax, export_pos[0], export_pos[1], box_w, box_h, "Export /\nBackup Module", fontsize=label_fs)
    rounded_box(ax, security_pos[0], security_pos[1], sec_w, sec_h, "Device Security\n(Biometric / PIN)", fontsize=9)

    # Draw arrows (solid = data flow, dashed = control/security)
    # UI -> Persistence
    start = (ui_pos[0] + box_w, ui_pos[1] + box_h/2)
    end = (persistence_pos[0], persistence_pos[1] + box_h/2)
    draw_arrow(ax, start, end, style='solid', lw=1.2)

    # Persistence -> Data Store
    start = (persistence_pos[0] + box_w, persistence_pos[1] + box_h/2)
    end = (datastore_pos[0], datastore_pos[1] + box_h/2)
    draw_arrow(ax, start, end, style='solid', lw=1.2)

    # Data Store -> Inference Engine (read embeddings/models)
    start = (datastore_pos[0] + box_w, datastore_pos[1] + box_h/2)
    end = (inference_pos[0], inference_pos[1] + box_h/2)
    draw_arrow(ax, start, end, style='solid', lw=1.2)

    # Inference Engine -> Persistence (store embeddings/labels)
    start = (inference_pos[0] + box_w, inference_pos[1] + box_h/2)
    end = (clustering_pos[0], clustering_pos[1] + box_h/2)  # via clustering path
    # Draw inference -> persistence via a short arrow back to datastore/persistence
    back_start = (inference_pos[0] + box_w*0.2, inference_pos[1] - box_h*0.6)
    back_end = (persistence_pos[0] + box_w*0.5, persistence_pos[1] - box_h*0.6)
    draw_arrow(ax, (inference_pos[0] + box_w, inference_pos[1] + box_h/2), (persistence_pos[0] + box_w*0.5, persistence_pos[1] + box_h/2), style='solid', lw=1.0)

    # Persistence -> Clustering Engine
    start = (persistence_pos[0] + box_w, persistence_pos[1] - box_h*0.2)
    end = (clustering_pos[0], clustering_pos[1] - box_h*0.2)
    draw_arrow(ax, start, end, style='solid', lw=1.0)

    # Clustering Engine -> Persistence (update clusters)
    start = (clustering_pos[0] + box_w, clustering_pos[1] + box_h*0.2)
    end = (persistence_pos[0] + box_w*0.5, persistence_pos[1] + box_h*0.2)
    draw_arrow(ax, start, end, style='solid', lw=1.0)

    # Scheduler -> Clustering Engine
    start = (scheduler_pos[0] + box_w, scheduler_pos[1] + box_h*0.2)
    end = (clustering_pos[0] + box_w, clustering_pos[1] + box_h*0.2)
    draw_arrow(ax, start, end, style='solid', lw=1.0)

    # Persistence -> Export/Backup Module
    start = (persistence_pos[0] + box_w, persistence_pos[1] - box_h*0.6)
    end = (export_pos[0], export_pos[1] - box_h*0.6)
    draw_arrow(ax, start, end, style='solid', lw=1.0)

    # Device Security dashed lines to UI and Persistence (control/security)
    sec_to_ui_start = (security_pos[0] + sec_w/2, security_pos[1])
    sec_to_ui_end = (ui_pos[0] + box_w/2, ui_pos[1] + box_h)
    draw_arrow(ax, sec_to_ui_start, sec_to_ui_end, style='dashed', lw=1.0)

    sec_to_pers_start = (security_pos[0] + sec_w/2, security_pos[1])
    sec_to_pers_end = (persistence_pos[0] + box_w/2, persistence_pos[1] + box_h)
    draw_arrow(ax, sec_to_pers_start, sec_to_pers_end, style='dashed', lw=1.0)

    # Add small lock icon (simple) near security box
    lock_x = security_pos[0] + sec_w - 0.25
    lock_y = security_pos[1] + sec_h - 0.18
    lock_body = patches.Rectangle((lock_x, lock_y - 0.18), 0.18, 0.18, linewidth=0.8, edgecolor='black', facecolor='white')
    ax.add_patch(lock_body)
    ax.plot([lock_x + 0.09], [lock_y - 0.09], marker='o', color='black', markersize=3)

    # Legend (top-right)
    legend_x = 9.2
    legend_y = 7.1
    ax.text(legend_x, legend_y + 0.35, "Legend", fontsize=9, fontweight='bold', ha='left')
    # Solid arrow sample
    ax.annotate("", xy=(legend_x + 0.9, legend_y + 0.25), xytext=(legend_x + 0.2, legend_y + 0.25),
                arrowprops=dict(arrowstyle="->", linewidth=1.0, color="black"))
    ax.text(legend_x + 1.05, legend_y + 0.25, "Data flow", fontsize=9, va='center')
    # Dashed arrow sample
    ax.annotate("", xy=(legend_x + 0.9, legend_y - 0.05), xytext=(legend_x + 0.2, legend_y - 0.05),
                arrowprops=dict(arrowstyle="->", linewidth=1.0, color="black", linestyle='dashed'))
    ax.text(legend_x + 1.05, legend_y - 0.05, "Control / Security", fontsize=9, va='center')

    # Caption
    ax.text(6.0, 0.45,
            "High-level system architecture for the on-device microjournaling application.",
            ha="center", va="center", fontsize=9, style="italic")

    # Tight layout and save
    pdf_path = os.path.join(OUTPUT_DIR, PDF_NAME)
    png_path = os.path.join(OUTPUT_DIR, PNG_NAME)
    plt.savefig(pdf_path, format="pdf", bbox_inches="tight")
    plt.savefig(png_path, format="png", dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(f"Saved: {pdf_path}")
    print(f"Saved: {png_path}")

if __name__ == "__main__":
    create_diagram()
