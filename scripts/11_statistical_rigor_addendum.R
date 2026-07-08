# 11_statistical_rigor_addendum.R
# Requires: 06, 07, 08, 09
# Provides: results/11_*.csv -- 논문 투고 수준 통계 검토/보강.
#
# 원고 작성 전 재점검에서 발견한 갭과 조치:
#  1) 09의 지질유전자 상관분석(2 cell type x 5 gene x 3 subset = 30개 검정)이 다중비교
#     보정 없이 raw p-value로만 보고됨 -> BH-FDR 추가.
#  2) 07/08의 그룹비교가 n=4-5의 작은 표본에 Welch t-test만 사용 -> 정규성 가정이 깨지기
#     쉬우므로 Wilcoxon rank-sum(비모수)을 1차 지표로 병기하고, Cohen's d 효과크기와
#     평균차 95% CI를 추가.
#  3) 08의 MKO 무효과(null) 결과가 "효과가 없다"인지 "표본이 작아 못 본다"인지 구분이
#     안 됨 -> n=4-5, 관측된 표준편차 기준으로 80% power에 필요한 최소 tGohen's d(MDE)를
#     계산해 명시.
#  4) BisqueRNA 마커 패널 크기가 세포타입마다 5~25개로 작아 보이지만, 실제로는
#     GetNumGenesWeighted()가 PC1/PC2 sdev 비율을 최대화하는 유전자 수를 알고리즘적으로
#     선택한 결과임(임의 축소가 아님) -> 이용 가능했던 후보 마커 수와 최종 사용 수,
#     PC1 variance-explained를 함께 표로 남겨 투명성 확보.

source("scripts/00_setup.R")

cohens_d = function(x, y) {
  nx = length(x); ny = length(y)
  pooled_sd = sqrt(((nx - 1) * var(x) + (ny - 1) * var(y)) / (nx + ny - 2))
  (mean(x) - mean(y)) / pooled_sd
}

group_compare = function(x, y, label_x, label_y) {
  tt = t.test(x, y)  # Welch (default var.equal=FALSE)
  wt = suppressWarnings(wilcox.test(x, y, exact = FALSE))
  data.frame(
    n_x = length(x), n_y = length(y),
    mean_x = mean(x), mean_y = mean(y),
    mean_diff = mean(x) - mean(y),
    ci95_lo = tt$conf.int[1], ci95_hi = tt$conf.int[2],
    cohens_d = cohens_d(x, y),
    welch_t_p = tt$p.value,
    wilcoxon_p = wt$p.value
  )
}

# --- 1) MKO(axis2) 재검정: Wilcoxon + Cohen's d + BH, family = diet(2) x celltype(12) ---
props = read.csv(file.path(results_dir, "06_deconvolution_props.csv"))
cell_types = setdiff(colnames(props), c("sample", "axis", "genotype", "diet", "group"))
axis2 = props %>% filter(axis == "macrophage_KO")

mko_full = expand.grid(cell_type = cell_types, diet = c("Chow", "HFD"), stringsAsFactors = FALSE) %>%
  rowwise() %>%
  mutate(res = list(group_compare(
    axis2[[cell_type]][axis2$diet == diet & axis2$genotype == "MKO"],
    axis2[[cell_type]][axis2$diet == diet & axis2$genotype == "WT"],
    "MKO", "WT"
  ))) %>%
  ungroup() %>%
  tidyr::unnest(res) %>%
  group_by(diet) %>%
  mutate(welch_p_BH = p.adjust(welch_t_p, method = "BH"),
         wilcoxon_p_BH = p.adjust(wilcoxon_p, method = "BH")) %>%
  ungroup() %>%
  arrange(diet, wilcoxon_p)

write.csv(mko_full, file.path(results_dir, "11_MKO_stats_full.csv"), row.names = FALSE)
message("=== axis2 (MKO vs WT) 재검정, Wilcoxon 1차 지표 ===")
print(mko_full %>% select(cell_type, diet, n_x, n_y, mean_diff, cohens_d, wilcoxon_p, wilcoxon_p_BH), n = 30)

# --- 2) axis1 검증 재검정 (동일한 지표 세트) ---
axis1_hfd = props %>% filter(axis == "adipocyte_death", diet == "HFD")
axis1_full = lapply(cell_types, function(ct) {
  cbind(cell_type = ct, group_compare(
    axis1_hfd[[ct]][axis1_hfd$genotype == "Bcl2TG"],
    axis1_hfd[[ct]][axis1_hfd$genotype == "WT"],
    "TG", "WT"
  ))
}) %>% bind_rows() %>%
  mutate(welch_p_BH = p.adjust(welch_t_p, method = "BH"),
         wilcoxon_p_BH = p.adjust(wilcoxon_p, method = "BH")) %>%
  arrange(wilcoxon_p)
write.csv(axis1_full, file.path(results_dir, "11_axis1_stats_full.csv"), row.names = FALSE)
message("\n=== axis1 (TG vs WT, HFD) 재검정 ===")
print(axis1_full %>% select(cell_type, mean_diff, cohens_d, wilcoxon_p, wilcoxon_p_BH))

# --- 3) 지질유전자 상관 재검정: BH 보정 추가 (원래 09에서 누락됨) ---
cor_results = read.csv(file.path(results_dir, "09_lipid_gene_correlation.csv"))
cor_results = cor_results %>%
  group_by(subset) %>%
  mutate(p_BH_within_subset = p.adjust(p_value, method = "BH")) %>%
  ungroup() %>%
  mutate(p_BH_all30 = p.adjust(p_value, method = "BH")) %>%
  arrange(p_value)
write.csv(cor_results, file.path(results_dir, "11_lipid_correlation_BH.csv"), row.names = FALSE)
message("\n=== 지질유전자 상관, BH 보정 후 (전체 30개 검정 기준) ===")
print(cor_results %>% filter(p_BH_all30 < 0.05) %>%
        select(cell_type, gene, subset, r, p_value, p_BH_all30))

# --- 4) 표본크기 4-5/그룹에서 80% power로 검출 가능한 최소 Cohen's d (MDE) ---
mde = sapply(c(4, 5), function(n) {
  tryCatch(power.t.test(n = n, sd = 1, power = 0.8, sig.level = 0.05)$delta,
           error = function(e) NA)
})
names(mde) = c("n=4", "n=5")
message("\n=== 80% power 기준 최소 검출가능 Cohen's d (n=4, n=5 per group, alpha=0.05) ===")
print(round(mde, 2))
write.csv(data.frame(n_per_group = c(4, 5), min_detectable_d = round(mde, 2)),
          file.path(results_dir, "11_power_MDE.csv"), row.names = FALSE)

# --- 5) 마커 패널 크기 및 PC1 variance-explained 투명성 테이블 ---
decon = readRDS(file.path(results_dir, "06_decon_full.rds"))
ve = decon$var.explained
pc1_pct = ve["PC1", ] / colSums(ve, na.rm = TRUE) * 100
marker_qc = data.frame(
  cell_type = names(decon$genes.used),
  n_markers_used = sapply(decon$genes.used, length),
  pc1_variance_explained_pct = round(pc1_pct[names(decon$genes.used)], 1)
)
write.csv(marker_qc, file.path(results_dir, "11_marker_panel_QC.csv"), row.names = FALSE)
message("\n=== 마커 패널 크기 및 PC1 variance-explained (신호 응집도) ===")
print(marker_qc)
