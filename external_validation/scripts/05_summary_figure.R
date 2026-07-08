# 05_summary_figure.R
# Builds the external-validation summary figure (Figure 5 in manuscript) from
# already-computed CSVs -- no need to reload the large Seurat objects.

source("scripts/00_setup.R")

results_dir = "external_validation/results"
fig_dir = "external_validation/figures"

## ---- Panel A: GSE156057 marker profile for candidate vs neutrophil vs Kupffer ----
pct156057 = read.csv(file.path(results_dir, "gse156057_pct_expr_by_cluster.csv"), row.names = 1)
sel_clusters = c("4", "32", "34", "39", "2", "25")
sel_labels = c("4" = "S100A8hi (4)", "32" = "S100A8hi (32)", "34" = "S100A8hi (34)",
               "39" = "Neutrophil (39)", "2" = "Kupffer (2)", "25" = "Kupffer (25)")
genes_a = c("S100a8", "S100a9", "Ly6g", "Camp", "Csf1r", "Cd68", "Clec4f")

dfA = pct156057[sel_clusters, genes_a]
dfA$cluster = factor(sel_labels[sel_clusters], levels = rev(sel_labels[sel_clusters]))
dfA_long = dfA %>% pivot_longer(-cluster, names_to = "gene", values_to = "pct")
dfA_long$gene = factor(dfA_long$gene, levels = genes_a)

pA = ggplot(dfA_long, aes(x = gene, y = cluster, size = pct, color = pct)) +
  geom_point() +
  scale_size_continuous(range = c(1, 10), limits = c(0, 1)) +
  scale_color_gradient(low = "grey85", high = "#3C5488", limits = c(0, 1)) +
  theme_bw() + theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
  labs(title = "A. GSE156057 (CD45+): candidate clusters", x = NULL, y = NULL, size = "% expr.", color = "% expr.")

## ---- Panel B: GSE156057 S100A8hi_macrophage proportion by diet/timepoint ----
props156057 = read.csv(file.path(results_dir, "gse156057_S100A8hi_proportions.csv"))
dfB = props156057 %>% filter(cell_class == "S100A8hi_macrophage") %>%
  mutate(diet = factor(diet, levels = c("SD", "WD")),
         timepoint = factor(timepoint, levels = c("12w", "24w", "36w")))

pB = ggplot(dfB, aes(x = timepoint, y = proportion, color = diet, group = diet)) +
  geom_point(size = 3) + geom_line() +
  theme_bw() +
  labs(title = "B. S100A8hi proportion (GSE156057)", x = "Timepoint", y = "Proportion of CD45+ cells")

## ---- Panel C: GSE166504 -- S100a8 as a gradient, not a discrete cluster ----
pct166504 = read.csv(file.path(results_dir, "gse166504_pct_expr_by_cluster.csv"), row.names = 1)
crosstab = read.csv(file.path(results_dir, "gse166504_cluster_vs_authorlabel.csv"), row.names = 1)
dominant = apply(crosstab, 1, function(x) colnames(crosstab)[which.max(x)])

dfC = data.frame(
  cluster = rownames(pct166504),
  S100a8_pct = pct166504$S100a8,
  Csf1r_pct = pct166504$Csf1r,
  dominant_label = dominant[rownames(pct166504)]
)
dfC$dominant_label = recode(dfC$dominant_label,
  "Kupffer.cells" = "Kupffer-dominant",
  "Monocyte.Monocyte.derived.macrophage" = "MoMF-dominant",
  "Neutrophils" = "Neutrophil-dominant"
)

pC = ggplot(dfC, aes(x = Csf1r_pct, y = S100a8_pct, color = dominant_label)) +
  geom_point(size = 3) +
  theme_bw() +
  labs(title = "C. GSE166504: S100a8 is a gradient, not a cluster",
       x = "% cells expressing Csf1r", y = "% cells expressing S100a8", color = NULL) +
  theme(legend.position = "bottom")

fig5 = (pA | (pB / pC)) + plot_layout(widths = c(1.3, 1)) +
  plot_annotation(title = "Figure 5. External validation of the S100A8-hi macrophage signature in two independent mouse liver scRNA-seq datasets")
ggsave(file.path(fig_dir, "Figure5_external_validation.png"), fig5, width = 12, height = 7, dpi = 300)
message("Saved Figure5_external_validation.png")
