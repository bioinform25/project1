# 10_figures.R
# Requires: 03, 06, 07, 08, 09 (모든 결과 rds/csv)
# Provides: figures/10_summary_figure.png (발표/논문용 4-panel 요약 그림)

source("scripts/00_setup.R")

annotated = readRDS(file.path(results_dir, "scrna_annotated.rds"))
props = read.csv(file.path(results_dir, "06_deconvolution_props.csv"))
bulk = readRDS(file.path(results_dir, "bulk_counts.rds"))

lib_size = colSums(bulk$counts)
logcpm = log2(sweep(bulk$counts, 2, lib_size, "/") * 1e6 + 1)

panel_A = DimPlot(annotated, group.by = "cell_type", label = TRUE, repel = TRUE, label.size = 3) +
  ggtitle("A. scRNA cell types (WT + TG, HFD)") +
  theme(legend.position = "none")

axis1_hfd = props %>% filter(axis == "adipocyte_death", diet == "HFD") %>%
  mutate(genotype = factor(genotype, levels = c("WT", "Bcl2TG")))
panel_B = ggplot(axis1_hfd, aes(x = genotype, y = S100A8hi_macrophage, color = genotype)) +
  geom_boxplot(outlier.shape = NA) + geom_jitter(width = 0.1, size = 2) +
  theme_bw() + theme(legend.position = "none") +
  labs(title = "B. Validated: WT > TG (axis1)", y = "S100A8hi_macrophage score", x = NULL)

axis2 = props %>% filter(axis == "macrophage_KO") %>%
  mutate(genotype = factor(genotype, levels = c("WT", "MKO")),
         diet = factor(diet, levels = c("Chow", "HFD")))
panel_C = ggplot(axis2, aes(x = genotype, y = S100A8hi_macrophage, color = genotype)) +
  geom_boxplot(outlier.shape = NA) + geom_jitter(width = 0.1, size = 2) +
  facet_wrap(~diet) + theme_bw() + theme(legend.position = "none") +
  labs(title = "C. Applied: WT vs MKO (no sig. shift)", y = "S100A8hi_macrophage score", x = NULL)

cd36_df = props %>% filter(diet == "HFD") %>%
  left_join(as.data.frame(t(logcpm["Cd36", , drop = FALSE])) %>%
              tibble::rownames_to_column("sample"), by = "sample")
panel_D = ggplot(cd36_df, aes(x = S100A8hi_macrophage, y = Cd36)) +
  geom_point(aes(color = axis), size = 2) +
  geom_smooth(method = "lm", se = TRUE, color = "black", linewidth = 0.5) +
  theme_bw() + theme(legend.position = "bottom") +
  labs(title = "D. No bulk-level correlation w/ Cd36", y = "Cd36 log2(CPM+1)", x = "S100A8hi_macrophage score")

combined = (panel_A | panel_B) / (panel_C | panel_D) +
  plot_annotation(title = "scRNA-informed deconvolution of hepatic S100A8+ macrophages: axis1 validation -> axis2 application")

ggsave(file.path(fig_dir, "10_summary_figure.png"), combined, width = 12, height = 10, dpi = 300)
message("완료: figures/10_summary_figure.png")
