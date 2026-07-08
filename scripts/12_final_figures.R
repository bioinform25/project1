# 12_final_figures.R
# Requires: 06, 08, 09, 11 outputs
# Provides: figures/Figure1.png (scRNA reference characterization, supplementary-style)
#           figures/Figure2.png (axis1 validation, Wilcoxon-annotated)
#           figures/Figure3.png (axis2 MKO application, Wilcoxon-annotated)
#           figures/Figure4.png (lipid-gene correlation, BH-annotated)
# 원고에 바로 삽입할 최종 그림. 통계값은 11_statistical_rigor_addendum.R 결과에서
# 그대로 가져와 본문/그림/표 사이 수치 불일치가 없도록 한다.

source("scripts/00_setup.R")
library(ggsignif)

annotated = readRDS(file.path(results_dir, "scrna_annotated.rds"))
props = read.csv(file.path(results_dir, "06_deconvolution_props.csv"))
axis1_stats = read.csv(file.path(results_dir, "11_axis1_stats_full.csv"))
mko_stats = read.csv(file.path(results_dir, "11_MKO_stats_full.csv"))
cor_bh = read.csv(file.path(results_dir, "11_lipid_correlation_BH.csv"))
bulk = readRDS(file.path(results_dir, "bulk_counts.rds"))
lib_size = colSums(bulk$counts)
logcpm = log2(sweep(bulk$counts, 2, lib_size, "/") * 1e6 + 1)

fmt_p = function(p) if (p < 0.001) "p < 0.001" else sprintf("p = %.3f", p)

## ---------- Figure 1: scRNA reference characterization ----------
f1a = DimPlot(annotated, group.by = "cell_type", label = TRUE, repel = TRUE, label.size = 3) +
  ggtitle("A") + theme(legend.position = "none")

confirm_genes = c("S100a8", "S100a9", "Ly6g", "Camp", "Ltf", "Ngp", "Csf1r", "Adgre1", "Clec4f", "Cd68", "Trem2", "Gpnmb")
f1b = DotPlot(
  subset(annotated, subset = cell_type %in% c("Neutrophil", "S100A8hi_macrophage", "Macrophage_Kupffer")),
  features = intersect(confirm_genes, rownames(annotated)), group.by = "cell_type"
) + RotatedAxis() + ggtitle("B") + theme(axis.text.x = element_text(size = 8))

fig1 = (f1a | f1b) + plot_layout(widths = c(1.1, 1)) +
  plot_annotation(title = "Figure 1. scRNA reference and identification of a distinct S100A8-hi macrophage population")
ggsave(file.path(fig_dir, "Figure1.png"), fig1, width = 11, height = 5, dpi = 300)

## ---------- Figure 2: axis1 (WT vs Bcl2TG, HFD) validation ----------
axis1_hfd = props %>% filter(axis == "adipocyte_death", diet == "HFD") %>%
  mutate(genotype = factor(genotype, levels = c("WT", "Bcl2TG")))

get_stat = function(ct) axis1_stats %>% filter(cell_type == ct)

s_mk = get_stat("Macrophage_Kupffer")
f2a = ggplot(axis1_hfd, aes(genotype, Macrophage_Kupffer, color = genotype)) +
  geom_boxplot(outlier.shape = NA) + geom_jitter(width = 0.1, size = 2) +
  geom_signif(comparisons = list(c("WT", "Bcl2TG")),
              annotations = sprintf("Wilcoxon %s\nd = %.2f", fmt_p(s_mk$wilcoxon_p), s_mk$cohens_d),
              y_position = max(axis1_hfd$Macrophage_Kupffer) + 0.5, tip_length = 0.02) +
  theme_bw() + theme(legend.position = "none") +
  labs(title = "A. Macrophage_Kupffer", y = "Relative abundance score (PC1)", x = NULL)

s_s1 = get_stat("S100A8hi_macrophage")
f2b = ggplot(axis1_hfd, aes(genotype, S100A8hi_macrophage, color = genotype)) +
  geom_boxplot(outlier.shape = NA) + geom_jitter(width = 0.1, size = 2) +
  geom_signif(comparisons = list(c("WT", "Bcl2TG")),
              annotations = sprintf("Wilcoxon %s\nd = %.2f", fmt_p(s_s1$wilcoxon_p), s_s1$cohens_d),
              y_position = max(axis1_hfd$S100A8hi_macrophage) + 0.5, tip_length = 0.02) +
  theme_bw() + theme(legend.position = "none") +
  labs(title = "B. S100A8hi_macrophage", y = "Relative abundance score (PC1)", x = NULL)

deseq_check = read.csv(file.path(results_dir, "07_marker_gene_direction_check.csv")) %>% filter(!is.na(log2FoldChange))
f2c = ggplot(deseq_check, aes(x = reorder(gene, log2FoldChange), y = log2FoldChange, fill = cell_type)) +
  geom_col() + coord_flip() + geom_hline(yintercept = 0) +
  theme_bw() + labs(title = "C. Original bulk DESeq2 (n=5 vs n=5), TG vs WT",
                     x = NULL, y = expression(log[2]~"fold change (TG / WT)"))

fig2 = (f2a | f2b) / f2c +
  plot_annotation(title = "Figure 2. Deconvolution validates against the original, fully-replicated bulk DESeq2 result (axis 1, HFD)")
ggsave(file.path(fig_dir, "Figure2.png"), fig2, width = 9, height = 9, dpi = 300)

## ---------- Figure 3: axis2 (WT vs MKO) application ----------
axis2 = props %>% filter(axis == "macrophage_KO") %>%
  mutate(genotype = factor(genotype, levels = c("WT", "MKO")),
         diet = factor(diet, levels = c("Chow", "HFD")))

make_panel = function(ct, diet_lvl, title) {
  d = axis2 %>% filter(diet == diet_lvl)
  s = mko_stats %>% filter(cell_type == ct, diet == diet_lvl)
  ggplot(d, aes(genotype, .data[[ct]], color = genotype)) +
    geom_boxplot(outlier.shape = NA) + geom_jitter(width = 0.1, size = 2) +
    geom_signif(comparisons = list(c("WT", "MKO")),
                annotations = sprintf("%s, d=%.2f", fmt_p(s$wilcoxon_p), s$cohens_d),
                y_position = max(d[[ct]]) + 0.4, tip_length = 0.02) +
    theme_bw() + theme(legend.position = "none") +
    labs(title = title, y = "Relative abundance score (PC1)", x = NULL)
}

f3a = make_panel("S100A8hi_macrophage", "Chow", "A. S100A8hi_macrophage, Chow")
f3b = make_panel("S100A8hi_macrophage", "HFD", "B. S100A8hi_macrophage, HFD")
f3c = make_panel("Macrophage_Kupffer", "Chow", "C. Macrophage_Kupffer, Chow")
f3d = make_panel("Macrophage_Kupffer", "HFD", "D. Macrophage_Kupffer, HFD")
f3e = make_panel("Neutrophil", "HFD", "E. Neutrophil, HFD (uncorrected)")
f3f = make_panel("Mast_cell", "HFD", "F. Mast_cell, HFD (uncorrected)")

fig3 = (f3a | f3b | f3c) / (f3d | f3e | f3f) +
  plot_annotation(title = "Figure 3. Macrophage-specific S100a8 deletion (MKO) does not significantly remodel hepatic cell composition",
                   subtitle = "All comparisons BH-adjusted across 12 cell types within diet; none reach q < 0.05 (see Table S2)")
ggsave(file.path(fig_dir, "Figure3.png"), fig3, width = 13, height = 8, dpi = 300)

## ---------- Figure 4: lipid-gene correlation ----------
cd36_df = props %>% filter(diet == "HFD") %>%
  left_join(as.data.frame(t(logcpm["Cd36", , drop = FALSE])) %>% tibble::rownames_to_column("sample"), by = "sample")

r_mk = cor_bh %>% filter(cell_type == "Macrophage_Kupffer", gene == "Cd36", subset == "all_HFD")
f4a = ggplot(cd36_df, aes(Macrophage_Kupffer, Cd36)) +
  geom_point(aes(color = axis), size = 2.5) +
  geom_smooth(method = "lm", se = TRUE, color = "black", linewidth = 0.5) +
  theme_bw() + theme(legend.position = "bottom", plot.title = element_text(size = 10)) +
  labs(title = sprintf("A. Macrophage_Kupffer vs Cd36\nr=%.2f, BH q=%.3f", r_mk$r, r_mk$p_BH_all30),
       x = "Macrophage_Kupffer score", y = "Cd36 log2(CPM+1)")

r_s1 = cor_bh %>% filter(cell_type == "S100A8hi_macrophage", gene == "Cd36", subset == "all_HFD")
f4b = ggplot(cd36_df, aes(S100A8hi_macrophage, Cd36)) +
  geom_point(aes(color = axis), size = 2.5) +
  geom_smooth(method = "lm", se = TRUE, color = "black", linewidth = 0.5) +
  theme_bw() + theme(legend.position = "bottom", plot.title = element_text(size = 10)) +
  labs(title = sprintf("B. S100A8hi_macrophage vs Cd36\nr=%.2f, BH q=%.3f", r_s1$r, r_s1$p_BH_all30),
       x = "S100A8hi_macrophage score", y = "Cd36 log2(CPM+1)")

heat_df = cor_bh %>% filter(subset == "all_HFD") %>%
  mutate(sig = ifelse(p_BH_all30 < 0.05, "*", ""))
f4c = ggplot(heat_df, aes(x = gene, y = cell_type, fill = r)) +
  geom_tile() + geom_text(aes(label = sig), size = 6, vjust = 0.75) +
  scale_fill_gradient2(low = "#3C5488", mid = "white", high = "#E64B35", midpoint = 0) +
  theme_bw() + labs(title = "C. All correlations (all HFD bulk, n=19); * = BH q<0.05 (30 tests)", x = NULL, y = NULL)

fig4 = (f4a | f4b) / f4c +
  plot_annotation(title = "Figure 4. General macrophage abundance tracks lipogenic gene expression; S100A8-hi subset does not")
ggsave(file.path(fig_dir, "Figure4.png"), fig4, width = 10, height = 9, dpi = 300)

message("Figures 1-4 저장 완료.")
