# 13_origin_signature_scoring.R
# Requires: 03_scRNA_annotate_finalize.R (results/scrna_annotated.rds)
# Provides: results/13_origin_marker_panel_percluster.csv, results/13_origin_scores_primary_stats.csv,
#           figures/13_origin_marker_dotplot.png, figures/13_origin_scores_primary.png
#
# 원 논문(Guan et al., JCI 2025)이 명시적으로 미해결로 남긴 질문: S100A8+ 대식세포가
# (1) 순환 단핵구의 향상된 모집, (2) 이주 전 단핵구에서의 FFA-유도 S100A8 발현,
# (3) 간 상주 대식세포의 국소 재프로그래밍 중 무엇에서 기원하는지 저자들도 모른다고
# 명시("detailed investigations incorporating markers... will be essential").
#
# 1차 시도(문헌 기반 5유전자 monocyte-recruitment 시그니처를 합성 모듈점수로 사용)에서
# 진단(sanity check) 결과, Ly6c2/Sell/Chil3가 이 데이터셋에서 Neutrophil에도 강하게
# 발현되어 monocyte-lineage에 특이적이지 않음을 확인했다 (Neutrophil Ly6c2 avg=2.03 vs
# S100A8hi 0.19, Chil3 avg=1.95 vs 0.03 -- 단핵구 특이 마커가 아니라 일반 골수계/최근
# 이동 세포 마커로 작동). 또한 "Macrophage_Kupffer" 라벨(03에서 클러스터 5/10/11/18을
# 병합)을 유전자 수준에서 재점검한 결과 실제로는 이질적임을 발견:
#   - 클러스터 18 (n=290): Clec4f 99.7%/Vsig4 97.6%/Cd5l 100%, Ccr2 6.9% -> 진짜 상주 Kupffer
#   - 클러스터 5,11 (n=1223+543=1766, 병합군의 67%): Ccr2 74-78%/Plac8 59-93%,
#     클러스터5는 Trem2 62%/Gpnmb 41% -> 단핵구-유래/LAM-유사, 상주 마커 낮음
#   - 클러스터 10 (n=572): 중간형 (Clec4f 55%/Cd5l 56%, Ccr2 18%)
# 이에 따라 합성 점수보다 신뢰도 높은 유전자별 발현표를 1차 근거로 삼고, "Macrophage_
# Kupffer"를 origin이 뚜렷이 다른 두 하위군(Kupffer_resident = 18+10, Macrophage_MoMF_LAM
# = 5+11)으로 나눠 S100A8hi_macrophage와 비교한다. Neutrophil은 골수계 계통 음성대조.

source("scripts/00_setup.R")

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

annotated = readRDS(file.path(results_dir, "scrna_annotated.rds"))

# --- refined origin groups, replacing the single merged "Macrophage_Kupffer" label ---
cluster_to_origin = c(
  "12" = "S100A8hi_macrophage",
  "18" = "Kupffer_resident", "10" = "Kupffer_resident",
  "5"  = "Macrophage_MoMF_LAM", "11" = "Macrophage_MoMF_LAM",
  "23" = "Neutrophil"
)
annotated$origin_group = unname(cluster_to_origin[as.character(annotated$seurat_clusters)])
target_clusters = c("S100A8hi_macrophage", "Kupffer_resident", "Macrophage_MoMF_LAM", "Neutrophil")
sub = subset(annotated, subset = origin_group %in% target_clusters)
sub$origin_group = factor(sub$origin_group, levels = target_clusters)
message("Cells per refined origin group:"); print(table(sub$origin_group))

# --- 1) primary evidence: per-gene pct-expressing / avg-expr, not a composite score ---
monocyte_sig = c("Ly6c2", "Ccr2", "Sell", "Plac8", "Chil3")
resident_sig = c("Clec4f", "Timd4", "Vsig4", "Cd5l", "Marco")
lam_sig = c("Trem2", "Gpnmb")
genes = intersect(c(monocyte_sig, resident_sig, lam_sig), rownames(sub))

pct = sapply(genes, function(g) tapply(GetAssayData(sub, layer = "data")[g, ], sub$origin_group, function(x) mean(x > 0)))
avg = sapply(genes, function(g) tapply(GetAssayData(sub, layer = "data")[g, ], sub$origin_group, mean))
panel = data.frame(origin_group = rownames(pct), pct[, genes]) %>%
  left_join(data.frame(origin_group = rownames(avg), avg[, genes], check.names = FALSE),
            by = "origin_group", suffix = c("_pct", "_avg"))
write.csv(panel, file.path(results_dir, "13_origin_marker_panel_percluster.csv"), row.names = FALSE)
message("\n=== pct expressing, by refined origin group ==="); print(round(pct, 3))

p_dot = DotPlot(sub, features = genes, group.by = "origin_group") + RotatedAxis() +
  ggtitle("Origin/identity marker panel by refined group (S100A8hi vs resident-Kupffer vs MoMF/LAM vs Neutrophil)")
ggsave(file.path(fig_dir, "13_origin_marker_dotplot.png"), p_dot, width = 9, height = 4.5, dpi = 300)

# --- 2) composite module scores, reported alongside the per-gene panel (not in place of it) ---
mono_present = intersect(monocyte_sig, rownames(sub))
resi_present = intersect(resident_sig, rownames(sub))
sub = AddModuleScore(sub, features = list(mono_present), name = "MonocyteScore")
sub = AddModuleScore(sub, features = list(resi_present), name = "ResidentScore")
sub$MonocyteScore = sub$MonocyteScore1
sub$ResidentScore = sub$ResidentScore1
meta = sub@meta.data

comparisons = list(
  c("S100A8hi_macrophage", "Kupffer_resident"),
  c("S100A8hi_macrophage", "Macrophage_MoMF_LAM"),
  c("S100A8hi_macrophage", "Neutrophil"),
  c("Macrophage_MoMF_LAM", "Kupffer_resident")
)
all_stats = list()
for (cmp in comparisons) {
  for (sc in c("MonocyteScore", "ResidentScore")) {
    x = meta[[sc]][meta$origin_group == cmp[1]]
    y = meta[[sc]][meta$origin_group == cmp[2]]
    all_stats[[length(all_stats) + 1]] = group_compare(x, y, paste(cmp[1], "vs", cmp[2]), sc)
  }
}
stats_df = bind_rows(all_stats) %>%
  mutate(welch_p_BH = p.adjust(welch_t_p, method = "BH"),
         wilcoxon_p_BH = p.adjust(wilcoxon_p, method = "BH")) %>%
  arrange(score, comparison)
write.csv(stats_df, file.path(results_dir, "13_origin_scores_primary_stats.csv"), row.names = FALSE)
message("\n=== Composite module-score comparisons (secondary evidence; BH within this 8-test family) ===")
print(stats_df %>% select(comparison, score, n_x, n_y, mean_diff, cohens_d, wilcoxon_p, wilcoxon_p_BH))

p1 = ggplot(meta, aes(x = origin_group, y = MonocyteScore, fill = origin_group)) +
  geom_violin(trim = TRUE) + geom_boxplot(width = 0.1, outlier.shape = NA, fill = "white") +
  theme_bw() + theme(legend.position = "none", axis.text.x = element_text(angle = 30, hjust = 1)) +
  ggtitle("Monocyte-recruitment score (Ccr2/Plac8/Ly6c2/Sell/Chil3 composite)")
p2 = ggplot(meta, aes(x = origin_group, y = ResidentScore, fill = origin_group)) +
  geom_violin(trim = TRUE) + geom_boxplot(width = 0.1, outlier.shape = NA, fill = "white") +
  theme_bw() + theme(legend.position = "none", axis.text.x = element_text(angle = 30, hjust = 1)) +
  ggtitle("Resident-Kupffer score (Clec4f/Timd4/Vsig4/Cd5l/Marco composite)")
ggsave(file.path(fig_dir, "13_origin_scores_primary.png"), p1 + p2, width = 11, height = 5, dpi = 300)

message("\nDone: primary-dataset origin scoring complete (refined 4-group design).")
