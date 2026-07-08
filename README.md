# project1: scRNA-informed deconvolution of the hepatic S100A8+ macrophage bulk cohort

## Background

Source data: Guan et al., "Adipocyte death drives fat redistribution from adipocytes to
hepatocytes in steatotic liver disease via S100A8+ macrophages" (GEO accessions
**GSE285614**, bulk liver RNA-seq, and **GSE285615**, liver scRNA-seq). Mouse model,
male, liver tissue.

The published mechanism: adipocyte death (via a Bcl2 transgene that blocks it, "TG")
→ hepatic S100A8+ macrophage accumulation → CCN3 suppression → CD36 upregulation →
hepatocyte lipid storage → MASLD. A second, independent cohort deletes *S100a8*
specifically in macrophages (`S100a8^fl/fl;Cx3cr1-Cre`, "MKO") to test whether removing
the macrophage effector blocks the same phenotype.

GSE285614 contains **two genotype axes**, each with matched chow/HFD raw counts:

| Axis | Genotypes | Samples | scRNA reference available? |
|---|---|---|---|
| 1 (adipocyte death) | WT vs Bcl2TG | 16 (chow + HFD) | Yes — GSE285615 (WT, TG) |
| 2 (macrophage KO) | S100a8^fl/fl vs S100a8^fl/fl;Cx3cr1-Cre (MKO) | 18 (chow + HFD) | No |

## Research question

The original paper tracks the CD36/CCN3 mechanism through single-gene bulk DEGs only.
It never asks whether deleting *S100a8* in macrophages reshapes the **broader hepatic
cell-type landscape** (immune infiltrate composition, not just single-gene expression) —
and it couldn't easily ask this for axis 2, since that cohort has no scRNA-seq of its own.

This project builds a cell-type signature from the axis-1 scRNA reference (WT, TG),
**validates** it against axis-1 bulk, and — only after validation passed — **applies**
the same signature to axis-2 (WT vs MKO) to estimate hepatic cell-type composition
where no scRNA reference exists. Composition estimates are then correlated against
Cd36/lipid-handling gene expression in the same bulk samples.

## Method limitation (stated explicitly)

The scRNA reference has **one biological replicate per genotype** (n=2 total: one WT,
one TG sample). Subject-variance-aware deconvolution methods (MuSiC, Bisque's full
`ReferenceBasedDecomposition`) require multiple reference subjects per cell type to
estimate cross-subject variance, which this dataset cannot support. We therefore use
`BisqueRNA::MarkerBasedDecomposition`, a marker-gene/signature-based method that only
needs a stable per-cell-type expression signature. Composition estimates from this
method are relative, marker-driven abundance scores (first PC of a marker-gene
sub-matrix) — not absolute proportions that sum to 1 — so they are only meaningful for
comparing the *same* cell type across samples/groups, not for comparing magnitude
*between* cell types.

**A pitfall we hit and corrected:** we first tried validating axis-1 deconvolution
against cell-type proportions counted directly from the n=1-per-genotype scRNA pair.
That "ground truth" showed TG > WT for S100A8hi_macrophage, while deconvolution said
the opposite (WT > TG) — an apparent validation failure. Before discarding the method,
we checked the original authors' own axis-1 bulk DESeq2 result (properly replicated,
n=5 WT vs n=5 TG, `data/raw/GSE285614_HFD_TG_vs_WT.xlsx`) for the same marker genes:
S100a8 (log2FC=-0.80, p=0.039), Cd68 (log2FC=-0.74, p=0.004), and other macrophage
markers are all **WT > TG**, matching the deconvolution and matching the expected
biology (Bcl2TG blocks adipocyte death, so it should be *protective*, i.e. lower
immune infiltration than WT under HFD). The single scRNA pair was the unreliable
signal here (n=1 cannot establish population-level direction), not the deconvolution.
See `scripts/07_validate_axis1.R` for the full reasoning and both checks kept side by
side.

## Data provenance

Raw files in `data/raw/` (gitignored, not tracked) were downloaded from GEO
(GSE285614, GSE285615) and are documented here for reproducibility:

- `GSM8705804_WT_filtered_feature_bc_matrix.h5`, `GSM8705805_TG_filtered_feature_bc_matrix.h5`
  — 10x Genomics filtered feature-barcode matrices, liver, WT and Bcl2TG, HFD.
- `GSE285614_HFD_TG_vs_WT.xlsx` — axis-1 bulk RNA-seq, 14,629 genes x 16 samples,
  per-sample raw counts embedded alongside DESeq2 summary stats.
- `GSE285614_MKO_HFD_vs_WT_HFD.xlsx` — axis-2 bulk RNA-seq, 14,031 genes x 18 samples,
  per-sample raw counts embedded alongside DESeq2 summary stats.

## Results summary

**scRNA annotation** (`scripts/01`-`03`): 18,167 QC-passed liver cells (WT + TG, HFD),
28 clusters at res=0.8, collapsed into 12 cell types. Critically, the clustering cleanly
separated **S100A8hi_macrophage** (S100a8/S100a9 positive, Ly6g negative, modest
Csf1r/Cd68/Adgre1 — monocyte/macrophage-lineage) from **Neutrophil** (S100a8/S100a9
*and* Ly6g/Camp/Ltf/Ngp all positive — mature granulocyte) — two populations that would
be trivially confounded by S100a8/9 alone.

**Validation (axis 1, WT vs Bcl2TG, HFD)**: marker-based deconvolution recovers
**WT > TG** for S100A8hi_macrophage and Macrophage_Kupffer, concordant (3/3 cell types
checked) with the original authors' properly-replicated bulk DESeq2 marker-gene
directions — see the pitfall/correction note above. Within our own n=5-vs-5 resample,
Macrophage_Kupffer reaches Wilcoxon p=0.012 (BH q=0.024, Cohen's d=-2.86); the
S100A8hi_macrophage subset itself trends the same direction (d=-0.92) but does not
reach significance at this n (Wilcoxon p=0.30) — see the power analysis below for why.

**Application (axis 2, WT vs MKO, macrophage-specific S100a8 knockout)**: no
statistically significant composition shift in S100A8hi_macrophage or
Macrophage_Kupffer between WT and MKO, in either chow or HFD (all BH q > 0.42,
Wilcoxon, `results/11_MKO_stats_full.csv`). Nominally significant (uncorrected)
shifts appear in Neutrophil (down in MKO, d=-2.42, p=0.037) and Mast_cell (up,
d=2.36, p=0.037) under HFD only, but neither survives BH correction across the 12
cell types tested (q=0.22) — hypothesis-generating, not conclusive.

**Power check** (`scripts/11`): at n=4-5/group, this cohort is only powered (80%,
alpha=0.05) to detect Cohen's d >= ~2.0-2.4. The MKO null result should be read as
*underpowered for moderate effects*, not as evidence of no effect; the Neutrophil/
Mast_cell nominal hits (d>2.3) are exactly the effect sizes this design *can* detect,
making them the most credible leads for a follow-up with adequate replication.

**Lipid-gene correlation** (`scripts/09`, BH-corrected across all 30 tests in
`scripts/11`): **Macrophage_Kupffer** correlates with Cd36 (r=0.74, q=0.006),
Pparg (q=0.006), Scd1 (q=0.006), and Plin2 (q=0.021) across all 19 HFD bulk samples,
surviving correction. **S100A8hi_macrophage** shows no correlation with any lipid
gene in any subset (all q>0.4) — a clean, reproducible null.

**Marker-panel transparency** (`scripts/11`): panel sizes (5-25 genes/cell type) are
not an arbitrary cutoff — `BisqueRNA::GetNumGenesWeighted()` selects the gene count
that maximizes the PC1/PC2 eigenvalue ratio for each cell type (an internal scree-like
criterion), not simply "as many as available." PC1 explains 73-78% of marker-panel
variance for Macrophage_Kupffer, S100A8hi_macrophage and NK_cell (coherent signal)
but only 34-39% for T_cell, Mast_cell and Neutrophil (noisier; interpret with more
caution) — see `results/11_marker_panel_QC.csv`.

See `figures/Figure1.png`-`Figure4.png` for the manuscript-ready figures (statistics
annotated on-figure, sourced directly from `results/11_*.csv` so numbers in text,
figures, and tables never diverge), and `manuscript.docx` for the full write-up.

## Repo structure

```
scripts/    00-10, run in numeric order (each file's header states inputs/outputs)
figures/    final publication-style figures
results/    intermediate RDS/CSV artifacts (signature matrix, proportion tables, stats)
data/raw/   source files (gitignored — see Data provenance above)
```

## Environment

R 4.5.2. Key packages: Seurat, hdf5r, Biobase, BisqueRNA, DESeq2, limma, tidyverse,
readxl, pheatmap, ggplot2, ggpubr, rstatix. Full session info captured at the end of
the pipeline run.
