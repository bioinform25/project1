# 06_origin_signature_scoring.R
# Requires: 03_gse156057_qc_cluster.R (gse156057_annotated.rds + gse156057_pct_expr_by_cluster.csv),
#           02_gse166504_cluster_annotate.R (gse166504_annotated.rds)
# Provides: external_validation/results/06_origin_scores_gse156057_stats.csv,
#           external_validation/results/06_origin_scores_gse166504_correlation.csv,
#           external_validation/figures/06_origin_scores_*.png
#
# Cross-dataset replication of scripts/13_origin_signature_scoring.R's question (does the
# S100A8-hi population look monocyte-derived or resident-Kupffer-reprogrammed?) in the two
# independent external datasets already used for signature-reproducibility validation
# (Results 3.5 of the manuscript). GSE156057 has a discrete S100A8hi cluster (like the
# primary dataset) so the same 3-group comparison applies. GSE166504 does NOT resolve a
# discrete S100A8hi cluster (only a continuous S100a8 gradient across myeloid clusters,
# per the manuscript's own finding) -- so there we test the weaker, cluster-level
# correlation question instead: across the 18 myeloid clusters, does higher S100a8 signal
# track more closely with the monocyte-recruitment score or the resident-Kupffer score?

source("scripts/00_setup.R")

results_dir = "external_validation/results"
fig_dir = "external_validation/figures"

cohens_d = function(x, y) {
  nx = length(x); ny = length(y)
  pooled_sd = sqrt(((nx - 1) * var(x) + (ny - 1) * var(y)) / (nx + ny - 2))
  (mean(x) - mean(y)) / pooled_sd
}

group_compare = function(x, y, comparison, score) {
  tt = t.test(x, y)
  wt = suppressWarnings(wilcox.test(x, y, exact = FALSE))
  data.frame(
    comparison = comparison, score = score,
    n_x = length(x), n_y = length(y),
    mean_x = mean(x), mean_y = mean(y),
    mean_diff = mean(x) - mean(y),
    cohens_d = cohens_d(x, y),
    welch_t_p = tt$p.value,
    wilcoxon_p = wt$p.value
  )
}

monocyte_sig = c("Ly6c2", "Ccr2", "Sell", "Plac8", "Chil3")
resident_sig = c("Clec4f", "Timd4", "Vsig4", "Cd5l", "Marco")

# ============================================================== GSE156057 ==
obj156 = readRDS(file.path(results_dir, "gse156057_annotated.rds"))
pct = read.csv(file.path(results_dir, "gse156057_pct_expr_by_cluster.csv"), row.names = 1)

# Same cluster-identity logic as 04_gse156057_proportions.R (cell_class was never written
# back into the saved object, only into the proportions CSV -- recomputed here identically).
s100a8hi_clusters = rownames(pct)[pct$S100a8 > 0.9 & pct$S100a9 > 0.9 &
                                     pct$Ly6g < 0.1 & pct$Camp < 0.1 & pct$Ltf < 0.1 & pct$Ngp < 0.1]
neutrophil_clusters = rownames(pct)[pct$S100a8 > 0.9 & pct$S100a9 > 0.9 &
                                       pct$Ly6g > 0.5 & pct$Camp > 0.5]
kupffer_clusters = rownames(pct)[pct$Clec4f > 0.7 & pct$S100a8 < 0.2]

obj156$cell_class = case_when(
  as.character(obj156$seurat_clusters) %in% s100a8hi_clusters ~ "S100A8hi_macrophage",
  as.character(obj156$seurat_clusters) %in% neutrophil_clusters ~ "Neutrophil",
  as.character(obj156$seurat_clusters) %in% kupffer_clusters ~ "Kupffer",
  TRUE ~ "Other"
)

mono156 = intersect(monocyte_sig, rownames(obj156))
resi156 = intersect(resident_sig, rownames(obj156))
obj156 = AddModuleScore(obj156, features = list(mono156), name = "MonocyteScore")
obj156 = AddModuleScore(obj156, features = list(resi156), name = "ResidentScore")
obj156$MonocyteScore = obj156$MonocyteScore1
obj156$ResidentScore = obj156$ResidentScore1

meta156 = obj156@meta.data
target = c("S100A8hi_macrophage", "Kupffer", "Neutrophil")
meta156_sub = meta156 %>% filter(cell_class %in% target)

comparisons156 = list(
  c("S100A8hi_macrophage", "Kupffer"),
  c("S100A8hi_macrophage", "Neutrophil")
)
stats156 = list()
for (cmp in comparisons156) {
  for (sc in c("MonocyteScore", "ResidentScore")) {
    x = meta156_sub[[sc]][meta156_sub$cell_class == cmp[1]]
    y = meta156_sub[[sc]][meta156_sub$cell_class == cmp[2]]
    stats156[[length(stats156) + 1]] = group_compare(x, y, paste(cmp[1], "vs", cmp[2]), sc)
  }
}
stats156_df = bind_rows(stats156) %>%
  mutate(welch_p_BH = p.adjust(welch_t_p, method = "BH"),
         wilcoxon_p_BH = p.adjust(wilcoxon_p, method = "BH")) %>%
  arrange(score, comparison)
write.csv(stats156_df, file.path(results_dir, "06_origin_scores_gse156057_stats.csv"), row.names = FALSE)
message("=== GSE156057: origin-signature score comparisons ===")
print(stats156_df %>% select(comparison, score, n_x, n_y, mean_diff, cohens_d, wilcoxon_p, wilcoxon_p_BH))

p156 = ggplot(meta156_sub, aes(x = factor(cell_class, levels = target), y = MonocyteScore, fill = cell_class)) +
  geom_violin(trim = TRUE) + geom_boxplot(width = 0.1, outlier.shape = NA, fill = "white") +
  theme_bw() + theme(legend.position = "none") +
  labs(title = "GSE156057: monocyte-recruitment score", x = NULL)
p156b = ggplot(meta156_sub, aes(x = factor(cell_class, levels = target), y = ResidentScore, fill = cell_class)) +
  geom_violin(trim = TRUE) + geom_boxplot(width = 0.1, outlier.shape = NA, fill = "white") +
  theme_bw() + theme(legend.position = "none") +
  labs(title = "GSE156057: resident-Kupffer score", x = NULL)
ggsave(file.path(fig_dir, "06_origin_scores_gse156057.png"), p156 + p156b, width = 10, height = 4.5, dpi = 300)

# ============================================================== GSE166504 ==
# No discrete S100A8hi cluster here (manuscript's own finding: gradient, not cluster) --
# so this dataset gets a cluster-level correlation test instead of a 3-group comparison.
obj166 = readRDS(file.path(results_dir, "gse166504_annotated.rds"))

mono166 = intersect(monocyte_sig, rownames(obj166))
resi166 = intersect(resident_sig, rownames(obj166))
obj166 = AddModuleScore(obj166, features = list(mono166), name = "MonocyteScore")
obj166 = AddModuleScore(obj166, features = list(resi166), name = "ResidentScore")
obj166$MonocyteScore = obj166$MonocyteScore1
obj166$ResidentScore = obj166$ResidentScore1
obj166$S100a8_expr = GetAssayData(obj166, layer = "data")["S100a8", ]

cluster_avg = obj166@meta.data %>%
  group_by(seurat_clusters) %>%
  summarise(S100a8_expr = mean(S100a8_expr),
            MonocyteScore = mean(MonocyteScore),
            ResidentScore = mean(ResidentScore),
            n_cells = n())

cor_mono = cor.test(cluster_avg$S100a8_expr, cluster_avg$MonocyteScore, method = "spearman")
cor_resi = cor.test(cluster_avg$S100a8_expr, cluster_avg$ResidentScore, method = "spearman")

cor166_df = data.frame(
  score = c("MonocyteScore", "ResidentScore"),
  n_clusters = nrow(cluster_avg),
  spearman_rho = c(unname(cor_mono$estimate), unname(cor_resi$estimate)),
  p_value = c(cor_mono$p.value, cor_resi$p.value)
)
write.csv(cor166_df, file.path(results_dir, "06_origin_scores_gse166504_correlation.csv"), row.names = FALSE)
write.csv(cluster_avg, file.path(results_dir, "06_origin_scores_gse166504_cluster_avg.csv"), row.names = FALSE)
message("\n=== GSE166504: cluster-level S100a8 vs origin-score correlation (18 myeloid clusters) ===")
print(cor166_df)

p166 = ggplot(cluster_avg, aes(x = MonocyteScore, y = S100a8_expr)) +
  geom_point(aes(size = n_cells)) + geom_smooth(method = "lm", se = TRUE) +
  theme_bw() + labs(title = "GSE166504: cluster-avg S100a8 vs monocyte-recruitment score")
p166b = ggplot(cluster_avg, aes(x = ResidentScore, y = S100a8_expr)) +
  geom_point(aes(size = n_cells)) + geom_smooth(method = "lm", se = TRUE) +
  theme_bw() + labs(title = "GSE166504: cluster-avg S100a8 vs resident-Kupffer score")
ggsave(file.path(fig_dir, "06_origin_scores_gse166504.png"), p166 + p166b, width = 11, height = 4.5, dpi = 300)

message("\nDone: cross-dataset origin scoring complete.")
