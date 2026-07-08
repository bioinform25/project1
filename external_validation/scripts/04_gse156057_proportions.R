# 04_gse156057_proportions.R
# Requires: 03_gse156057_qc_cluster.R (results/gse156057_annotated.rds)
# Provides: results/gse156057_S100A8hi_proportions.csv, figures/gse156057_proportions.png
#
# Identifies clusters matching the S100A8hi_macrophage signature (S100a8/S100a9 pct>0.9,
# Ly6g/Camp/Ltf/Ngp pct<0.1) vs the true neutrophil cluster (S100a8/9 AND Ly6g/Camp/Ltf/Ngp
# all high) from the pct_expr table, then computes per-sample proportions across
# SD/WD x 12/24/36-week timepoints to test whether abundance tracks western-diet duration.

source("scripts/00_setup.R")

results_dir = "external_validation/results"
fig_dir = "external_validation/figures"

obj = readRDS(file.path(results_dir, "gse156057_annotated.rds"))
pct = read.csv(file.path(results_dir, "gse156057_pct_expr_by_cluster.csv"), row.names = 1)

s100a8hi_clusters = rownames(pct)[pct$S100a8 > 0.9 & pct$S100a9 > 0.9 &
                                     pct$Ly6g < 0.1 & pct$Camp < 0.1 & pct$Ltf < 0.1 & pct$Ngp < 0.1]
neutrophil_clusters = rownames(pct)[pct$S100a8 > 0.9 & pct$S100a9 > 0.9 &
                                       pct$Ly6g > 0.5 & pct$Camp > 0.5]
kupffer_clusters = rownames(pct)[pct$Clec4f > 0.7 & pct$S100a8 < 0.2]

message("S100A8hi candidate clusters: ", paste(s100a8hi_clusters, collapse = ", "))
message("Neutrophil cluster(s): ", paste(neutrophil_clusters, collapse = ", "))
message("Kupffer-dominant clusters: ", paste(kupffer_clusters, collapse = ", "))

obj$cell_class = case_when(
  as.character(obj$seurat_clusters) %in% s100a8hi_clusters ~ "S100A8hi_macrophage",
  as.character(obj$seurat_clusters) %in% neutrophil_clusters ~ "Neutrophil",
  as.character(obj$seurat_clusters) %in% kupffer_clusters ~ "Kupffer",
  TRUE ~ "Other"
)

meta = obj@meta.data
meta$diet = factor(meta$diet, levels = c("SD", "WD"))
meta$timepoint = factor(meta$timepoint, levels = c("12w", "24w", "36w"))

props = meta %>%
  count(sample, diet, timepoint, cell_class) %>%
  group_by(sample) %>%
  mutate(total = sum(n), proportion = n / total) %>%
  ungroup()

write.csv(props, file.path(results_dir, "gse156057_S100A8hi_proportions.csv"), row.names = FALSE)

key_props = props %>% filter(cell_class %in% c("S100A8hi_macrophage", "Neutrophil", "Kupffer"))
message("\n=== S100A8hi_macrophage / Neutrophil / Kupffer proportion by sample ===")
print(key_props %>% select(sample, diet, timepoint, cell_class, n, proportion) %>% arrange(cell_class, timepoint, diet))

p = ggplot(key_props, aes(x = timepoint, y = proportion, color = diet, group = diet)) +
  geom_point(size = 3) + geom_line() +
  facet_wrap(~cell_class, scales = "free_y") +
  theme_bw() +
  labs(title = "GSE156057: cell-class proportion by diet and timepoint",
       y = "Proportion of CD45+ cells", x = "Timepoint")
ggsave(file.path(fig_dir, "gse156057_proportions.png"), p, width = 10, height = 4, dpi = 300)

message("\nDone.")
