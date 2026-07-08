# 04_scRNA_ground_truth_props.R
# Requires: 03_scRNA_annotate_finalize.R (results/scrna_annotated.rds)
# Provides: results/04_ground_truth_proportions.csv, figures/04_ground_truth_barplot.png
#
# WT/TG 각 1개 샘플의 scRNA에서 직접 관찰한 세포타입 구성비. 이후 07 단계에서
# axis-1(WT vs TG) bulk deconvolution 추정치와 대조할 "ground truth"로 사용.

source("scripts/00_setup.R")

annotated = readRDS(file.path(results_dir, "scrna_annotated.rds"))

props = annotated@meta.data %>%
  count(genotype, cell_type) %>%
  group_by(genotype) %>%
  mutate(n_total = sum(n), proportion = n / n_total) %>%
  ungroup()

write.csv(props, file.path(results_dir, "04_ground_truth_proportions.csv"), row.names = FALSE)

wide = props %>%
  select(genotype, cell_type, proportion) %>%
  pivot_wider(names_from = genotype, values_from = proportion) %>%
  mutate(TG_over_WT = TG / WT) %>%
  arrange(desc(TG_over_WT))
write.csv(wide, file.path(results_dir, "04_ground_truth_TGvsWT_ratio.csv"), row.names = FALSE)
message("WT->TG 세포타입 구성비 변화 (TG/WT ratio 내림차순):")
print(wide, n = 20)

p_bar = ggplot(props, aes(x = reorder(cell_type, -proportion), y = proportion, fill = genotype)) +
  geom_col(position = "dodge") +
  coord_flip() +
  labs(x = NULL, y = "Proportion of cells", title = "scRNA-observed cell-type composition, WT vs TG (ground truth)") +
  theme_bw()
ggsave(file.path(fig_dir, "04_ground_truth_barplot.png"), p_bar, width = 8, height = 5, dpi = 300)

s100a8_row = wide %>% filter(cell_type == "S100A8hi_macrophage")
message(sprintf(
  "S100A8hi_macrophage proportion: WT=%.3f%%, TG=%.3f%%, TG/WT fold=%.2f",
  100 * s100a8_row$WT, 100 * s100a8_row$TG, s100a8_row$TG_over_WT
))
