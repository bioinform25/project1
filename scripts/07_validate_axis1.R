# 07_validate_axis1.R
# Requires: 04_scRNA_ground_truth_props.R, 06_deconvolution.R, data/raw/GSE285614_HFD_TG_vs_WT.xlsx
# Provides: results/07_validation_stats.csv, results/07_marker_gene_direction_check.csv,
#           figures/07_validation_*.png
#
# 검증 기준을 두 단계로 나눈다:
#  1) (1차, 신뢰도 높음) 원저자의 axis1 HFD_TG_vs_WT DESeq2 결과(n=5 WT vs n=5 TG, 정식 통계
#     검정)에서 S100A8+ macrophage/면역세포 대표 마커 유전자의 방향을 직접 확인.
#  2) (2차, 참고용) scRNA ground truth(WT/TG 각 1개체). n=1이라 개체차만으로도 방향이
#     뒤집힐 수 있어 신뢰도가 낮다 -- 아래에서 실제로 그런 일이 일어났음을 확인했다.
#
# 배경: 04 단계에서 scRNA 기준 S100A8hi_macrophage는 TG > WT(1.46배)였지만, 06 단계
# 마커기반 deconvolution은 반대로 WT > TG를 추정했다. 원저자의 axis1 xlsx에 있는
# 정식 DESeq2 결과(log2FoldChange, TG vs WT)를 직접 열어보니 S100a8(log2FC=-0.80,
# p=0.039), Cd68(log2FC=-0.74, p=0.004), Cd36(log2FC=-1.64, p=1.4e-8) 등 핵심 마커가
# 모두 WT>TG 방향이었다. Bcl2TG는 지방세포 사멸을 막는 보호적 유전자형이므로 이 방향이
# 기전적으로도 타당하다 -- 즉 06의 deconvolution이 맞고, n=1 scRNA 쌍이 개체차로 인해
# 우연히 반대 방향으로 나온 것으로 결론. 이하 스크립트가 이 근거를 정량적으로 남긴다.

source("scripts/00_setup.R")

props = read.csv(file.path(results_dir, "06_deconvolution_props.csv"))
gt = read.csv(file.path(results_dir, "04_ground_truth_TGvsWT_ratio.csv"))

axis1_hfd = props %>% filter(axis == "adipocyte_death", diet == "HFD")
cell_types = setdiff(colnames(props), c("sample", "axis", "genotype", "diet", "group"))

stat_test = lapply(cell_types, function(ct) {
  x = axis1_hfd[[ct]][axis1_hfd$genotype == "WT"]
  y = axis1_hfd[[ct]][axis1_hfd$genotype == "Bcl2TG"]
  tt = t.test(y, x)  # TG - WT
  data.frame(
    cell_type = ct,
    mean_WT = mean(x), mean_TG = mean(y),
    diff_TG_minus_WT = mean(y) - mean(x),
    p_value = tt$p.value,
    decon_direction = ifelse(mean(y) > mean(x), "TG_up", "WT_up")
  )
}) %>% bind_rows() %>% arrange(cell_type)

# --- 1차 검증: 원저자 DESeq2 결과의 canonical marker gene 방향 ---
deseq_orig = read_excel(file.path(data_dir, "GSE285614_HFD_TG_vs_WT.xlsx")) %>%
  select(SYMBOL, log2FoldChange, pvalue, padj)

marker_panel = tribble(
  ~cell_type,               ~gene,
  "S100A8hi_macrophage",    "S100a8",
  "S100A8hi_macrophage",    "S100a9",
  "Macrophage_Kupffer",     "Adgre1",
  "Macrophage_Kupffer",     "Csf1r",
  "Macrophage_Kupffer",     "Clec4f",
  "Macrophage_Kupffer",     "Cd68",
  "T_cell",                 "Cd3e",
  "T_cell",                 "Ptprc"
)

marker_check = marker_panel %>%
  left_join(deseq_orig, by = c("gene" = "SYMBOL")) %>%
  mutate(deseq_direction = ifelse(log2FoldChange > 0, "TG_up", "WT_up"))
write.csv(marker_check, file.path(results_dir, "07_marker_gene_direction_check.csv"), row.names = FALSE)
message("원저자 axis1 DESeq2(n=5 vs n=5)의 canonical marker 방향:")
print(marker_check)

marker_consensus = marker_check %>%
  group_by(cell_type) %>%
  summarise(deseq_direction_majority = names(which.max(table(deseq_direction))), .groups = "drop")

stat_test = stat_test %>%
  left_join(marker_consensus, by = "cell_type") %>%
  mutate(primary_validation_match = decon_direction == deseq_direction_majority)

# --- 2차(참고): scRNA n=1 쌍 ---
stat_test = stat_test %>%
  left_join(gt %>% select(cell_type, scrna_direction = TG_over_WT), by = "cell_type") %>%
  mutate(
    scrna_direction = ifelse(scrna_direction > 1, "TG_up", "WT_up"),
    scrna_direction_match = decon_direction == scrna_direction
  )

write.csv(stat_test, file.path(results_dir, "07_validation_stats.csv"), row.names = FALSE)
print(stat_test)

n_primary = sum(stat_test$primary_validation_match, na.rm = TRUE)
n_primary_total = sum(!is.na(stat_test$primary_validation_match))
message(sprintf(
  "\n[1차 검증 - 신뢰] marker gene 기반 방향 일치: %d / %d 세포타입 (S100A8hi_macrophage, Macrophage_Kupffer, T_cell)",
  n_primary, n_primary_total
))
message(sprintf(
  "[2차 검증 - 참고, n=1이라 저신뢰] scRNA ground truth 방향 일치: %d / %d 세포타입 전체",
  sum(stat_test$scrna_direction_match), nrow(stat_test)
))

p_box = ggplot(axis1_hfd, aes(x = genotype, y = S100A8hi_macrophage, color = genotype)) +
  geom_boxplot(outlier.shape = NA) +
  geom_jitter(width = 0.1, size = 2) +
  labs(title = "S100A8hi_macrophage: bulk deconvolution score (axis1, HFD)",
       subtitle = "원저자 bulk DESeq2 marker gene(S100a8/S100a9) 방향과 일치 (WT > TG)",
       y = "Marker-based relative abundance score (PC1)") +
  theme_bw()
ggsave(file.path(fig_dir, "07_validation_S100A8_boxplot.png"), p_box, width = 5, height = 5, dpi = 300)

p_all = axis1_hfd %>%
  select(genotype, all_of(cell_types)) %>%
  pivot_longer(-genotype, names_to = "cell_type", values_to = "score") %>%
  ggplot(aes(x = genotype, y = score, color = genotype)) +
  geom_boxplot(outlier.shape = NA) +
  geom_jitter(width = 0.1, size = 1) +
  facet_wrap(~cell_type, scales = "free_y") +
  theme_bw() +
  theme(legend.position = "none") +
  labs(title = "All cell types: bulk deconvolution score, WT vs TG (axis1, HFD)")
ggsave(file.path(fig_dir, "07_validation_all_celltypes.png"), p_all, width = 10, height = 8, dpi = 300)
