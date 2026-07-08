# 08_apply_axis2_MKO.R
# Requires: 06_deconvolution.R (검증은 07에서 완료)
# Provides: results/08_MKO_stats.csv, figures/08_MKO_*.png
#
# 연구 질문: 대식세포 특이적 S100a8 결손(MKO)이 -- CD36/CCN3 단일 유전자 기전을 넘어서 --
# 간 전체 세포 구성(면역세포 침윤 정도)까지 바꾸는가? axis2에는 scRNA가 없으므로 07에서
# 검증한 marker-based deconvolution을 그대로 적용해 WT(S100a8 fl/fl) vs MKO를 chow/HFD
# 각각에서 비교한다.

source("scripts/00_setup.R")

props = read.csv(file.path(results_dir, "06_deconvolution_props.csv"))
cell_types = setdiff(colnames(props), c("sample", "axis", "genotype", "diet", "group"))

axis2 = props %>% filter(axis == "macrophage_KO")

mko_stats = expand.grid(cell_type = cell_types, diet = c("Chow", "HFD"), stringsAsFactors = FALSE) %>%
  rowwise() %>%
  mutate(
    x_WT = list(axis2[[cell_type]][axis2$diet == diet & axis2$genotype == "WT"]),
    x_MKO = list(axis2[[cell_type]][axis2$diet == diet & axis2$genotype == "MKO"]),
    mean_WT = mean(unlist(x_WT)),
    mean_MKO = mean(unlist(x_MKO)),
    diff_MKO_minus_WT = mean_MKO - mean_WT,
    p_value = t.test(unlist(x_MKO), unlist(x_WT))$p.value
  ) %>%
  ungroup() %>%
  select(-x_WT, -x_MKO) %>%
  group_by(diet) %>%
  mutate(p_adj_BH = p.adjust(p_value, method = "BH")) %>%
  ungroup() %>%
  arrange(diet, p_value)

write.csv(mko_stats, file.path(results_dir, "08_MKO_stats.csv"), row.names = FALSE)
message("axis2 (WT vs MKO) 세포타입별 비교, diet별:")
print(mko_stats, n = 30)

message("\n[핵심] S100A8hi_macrophage, Macrophage_Kupffer 관련 결과:")
print(mko_stats %>% filter(cell_type %in% c("S100A8hi_macrophage", "Macrophage_Kupffer")))

p_key = axis2 %>%
  select(genotype, diet, S100A8hi_macrophage, Macrophage_Kupffer) %>%
  pivot_longer(c(S100A8hi_macrophage, Macrophage_Kupffer), names_to = "cell_type", values_to = "score") %>%
  mutate(genotype = factor(genotype, levels = c("WT", "MKO")),
         diet = factor(diet, levels = c("Chow", "HFD"))) %>%
  ggplot(aes(x = genotype, y = score, color = genotype)) +
  geom_boxplot(outlier.shape = NA) +
  geom_jitter(width = 0.1, size = 2) +
  facet_grid(cell_type ~ diet, scales = "free_y") +
  theme_bw() +
  labs(title = "S100A8hi_macrophage / Macrophage_Kupffer composition: WT vs MKO",
       y = "Marker-based relative abundance score (PC1)")
ggsave(file.path(fig_dir, "08_MKO_key_celltypes.png"), p_key, width = 7, height = 7, dpi = 300)

p_all = axis2 %>%
  select(genotype, diet, all_of(cell_types)) %>%
  pivot_longer(all_of(cell_types), names_to = "cell_type", values_to = "score") %>%
  mutate(genotype = factor(genotype, levels = c("WT", "MKO")),
         diet = factor(diet, levels = c("Chow", "HFD"))) %>%
  ggplot(aes(x = genotype, y = score, color = genotype)) +
  geom_boxplot(outlier.shape = NA) +
  geom_jitter(width = 0.1, size = 1) +
  facet_grid(diet ~ cell_type, scales = "free_y") +
  theme_bw() +
  theme(legend.position = "none", axis.text.x = element_text(angle = 45, hjust = 1),
        strip.text.x = element_text(size = 6)) +
  labs(title = "All cell types: WT vs MKO composition, Chow vs HFD")
ggsave(file.path(fig_dir, "08_MKO_all_celltypes.png"), p_all, width = 14, height = 5, dpi = 300)
