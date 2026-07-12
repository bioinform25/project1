# 14_tf_activity_inference.R
# Requires: 05_bulk_load_merge.R (bulk_counts.rds), 06_deconvolution.R (06_deconvolution_props.csv),
#           03_scRNA_annotate_finalize.R (scrna_annotated.rds)
# Provides: results/14_tf_bulk_correlation.csv, results/14_tf_scrna_percluster.csv,
#           results/14_tf_scrna_stats.csv, figures/14_tf_*.png
#
# 원 논문 Discussion이 명시적으로 제안했지만 테스트하지 않은 가설: "PA나 사멸 지방세포 유래
# EV가 C/EBP나 AP-1을 통해 S100A8 발현을 조절하는지 테스트해보면 흥미로울 것"
# ("It would be interesting to test whether PA or EVs...upregulate S100A8...by regulating
# C/EBP and AP-1").
#
# 원래 계획은 decoupleR + CollecTRI/DoRothEA 마우스 regulon으로 정식 TF activity inference
# (타겟 유전자 발현 기반)를 시도하는 것이었으나, OmnipathR 3.18.4 / decoupleR 2.16.0 조합에서
# 서버 데이터 스키마 변경으로 get_collectri()/get_dorothea()/import_transcriptional_
# interactions() 모두 "argument is of length zero" 오류로 실패 (패키지 버전 비호환, 이
# 환경에서 재현 확인, 별도 조치 없이는 해결 불가). 계획에 명시된 대체 방안대로 전환:
# 정식 activity score 대신 C/EBP(Cebpa/Cebpb/Cebpd) vs AP-1(Fos/Fosb/Jun/Junb/Jund/Atf3)
# 계열 TF 자체의 mRNA 발현을 직접 사용한다. AP-1 계열은 특히 immediate-early gene이라 자기
# 발현량 자체가 경로 활성화의 표준 readout으로 흔히 쓰이므로, 완전한 대체는 아니지만 타당한
# 근사치다. 이는 상관관계이지 인과관계 증명이 아님을 명시한다.

source("scripts/00_setup.R")

cohens_d = function(x, y) {
  nx = length(x); ny = length(y)
  pooled_sd = sqrt(((nx - 1) * var(x) + (ny - 1) * var(y)) / (nx + ny - 2))
  (mean(x) - mean(y)) / pooled_sd
}
group_compare = function(x, y, comparison, score) {
  tt = t.test(x, y)
  wt = suppressWarnings(wilcox.test(x, y, exact = FALSE))
  data.frame(comparison = comparison, score = score, n_x = length(x), n_y = length(y),
             mean_x = mean(x), mean_y = mean(y), mean_diff = mean(x) - mean(y),
             cohens_d = cohens_d(x, y), welch_t_p = tt$p.value, wilcoxon_p = wt$p.value)
}

cebp_genes = c("Cebpa", "Cebpb", "Cebpd")
ap1_genes = c("Fos", "Fosb", "Jun", "Junb", "Jund", "Atf3")

# ============================================================ 1) BULK RNA-seq ==
bulk = readRDS(file.path(results_dir, "bulk_counts.rds"))
props = read.csv(file.path(results_dir, "06_deconvolution_props.csv"))

lib_size = colSums(bulk$counts)
logcpm = log2(sweep(bulk$counts, 2, lib_size, "/") * 1e6 + 1)

tf_genes = intersect(c(cebp_genes, ap1_genes), rownames(logcpm))
message("TF genes present in bulk data: ", paste(tf_genes, collapse = ", "))

tf_expr = as.data.frame(t(logcpm[tf_genes, , drop = FALSE]))
tf_expr$sample = rownames(tf_expr)
merged = props %>% left_join(tf_expr, by = "sample")
# S100a8 itself was dropped from the 12,505-gene axis1/axis2 common-gene intersection
# (05_bulk_load_merge.R) -- not present in this bulk count matrix. S100a9 (its obligate
# heterodimer partner, used jointly with S100a8 to define S100A8hi_macrophage throughout
# this project) is present and used as the bulk expression proxy instead.
merged$S100a9_expr = logcpm["S100a9", merged$sample]

targets = c("S100a9_expr", "S100A8hi_macrophage")
subsets = c("all34", "HFD19")

bulk_cor = expand.grid(tf_gene = tf_genes, target = targets, subset = subsets, stringsAsFactors = FALSE) %>%
  rowwise() %>%
  mutate(
    tf_family = ifelse(tf_gene %in% cebp_genes, "C/EBP", "AP-1"),
    dat = list(if (subset == "HFD19") merged %>% filter(diet == "HFD") else merged),
    r = cor(dat[[tf_gene]], dat[[target]], method = "spearman"),
    p_value = cor.test(dat[[tf_gene]], dat[[target]], method = "spearman")$p.value,
    n = nrow(dat)
  ) %>%
  ungroup() %>% select(-dat) %>%
  group_by(subset, target) %>%
  mutate(p_BH = p.adjust(p_value, method = "BH")) %>%
  ungroup() %>%
  arrange(subset, target, p_value)

write.csv(bulk_cor, file.path(results_dir, "14_tf_bulk_correlation.csv"), row.names = FALSE)
message("\n=== Bulk: TF mRNA vs S100a9 expression / S100A8hi_macrophage score (Spearman, BH within subset x target) ===")
print(bulk_cor %>% filter(target == "S100a9_expr", subset == "all34") %>%
        select(tf_family, tf_gene, r, p_value, p_BH), n = 20)

p_bulk = merged %>%
  select(sample, diet, S100a9_expr, all_of(tf_genes)) %>%
  tidyr::pivot_longer(all_of(tf_genes), names_to = "tf_gene", values_to = "tf_expr") %>%
  mutate(tf_family = ifelse(tf_gene %in% cebp_genes, "C/EBP", "AP-1")) %>%
  ggplot(aes(x = tf_expr, y = S100a9_expr, color = tf_family)) +
  geom_point(alpha = 0.6) + geom_smooth(method = "lm", se = FALSE) +
  facet_wrap(~tf_gene, scales = "free_x") + theme_bw() +
  labs(title = "Bulk (all 34 samples): TF mRNA vs S100a9 expression", x = "TF log2(CPM+1)", y = "S100a9 log2(CPM+1)")
ggsave(file.path(fig_dir, "14_tf_bulk_correlation.png"), p_bulk, width = 11, height = 7, dpi = 300)

# ======================================================== 2) scRNA (primary ref) ==
# 동일한 정제된 4-그룹 origin 설계(Module 1) 재사용: S100A8hi_macrophage / Kupffer_resident
# (클러스터 18+10) / Macrophage_MoMF_LAM (클러스터 5+11) / Neutrophil (클러스터 23).
annotated = readRDS(file.path(results_dir, "scrna_annotated.rds"))
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

tf_present = intersect(c(cebp_genes, ap1_genes), rownames(sub))
message("\nTF genes present in scRNA data: ", paste(tf_present, collapse = ", "))

pct = sapply(tf_present, function(g) tapply(GetAssayData(sub, layer = "data")[g, ], sub$origin_group, function(x) mean(x > 0)))
avg = sapply(tf_present, function(g) tapply(GetAssayData(sub, layer = "data")[g, ], sub$origin_group, mean))
panel = data.frame(origin_group = rownames(pct), pct[, tf_present]) %>%
  left_join(data.frame(origin_group = rownames(avg), avg[, tf_present], check.names = FALSE),
            by = "origin_group", suffix = c("_pct", "_avg"))
write.csv(panel, file.path(results_dir, "14_tf_scrna_percluster.csv"), row.names = FALSE)
message("\n=== scRNA: pct expressing TF genes, by refined origin group ==="); print(round(pct, 3))

cebp_present = intersect(cebp_genes, rownames(sub))
ap1_present = intersect(ap1_genes, rownames(sub))
sub = AddModuleScore(sub, features = list(cebp_present), name = "CebpScore")
sub = AddModuleScore(sub, features = list(ap1_present), name = "Ap1Score")
sub$CebpScore = sub$CebpScore1
sub$Ap1Score = sub$Ap1Score1
meta = sub@meta.data

comparisons = list(
  c("S100A8hi_macrophage", "Kupffer_resident"),
  c("S100A8hi_macrophage", "Macrophage_MoMF_LAM"),
  c("S100A8hi_macrophage", "Neutrophil")
)
all_stats = list()
for (cmp in comparisons) {
  for (sc in c("CebpScore", "Ap1Score")) {
    x = meta[[sc]][meta$origin_group == cmp[1]]
    y = meta[[sc]][meta$origin_group == cmp[2]]
    all_stats[[length(all_stats) + 1]] = group_compare(x, y, paste(cmp[1], "vs", cmp[2]), sc)
  }
}
stats_df = bind_rows(all_stats) %>%
  mutate(welch_p_BH = p.adjust(welch_t_p, method = "BH"),
         wilcoxon_p_BH = p.adjust(wilcoxon_p, method = "BH")) %>%
  arrange(score, comparison)
write.csv(stats_df, file.path(results_dir, "14_tf_scrna_stats.csv"), row.names = FALSE)
message("\n=== scRNA: C/EBP-score and AP1-score composite comparisons (BH within this 6-test family) ===")
print(stats_df %>% select(comparison, score, n_x, n_y, mean_diff, cohens_d, wilcoxon_p, wilcoxon_p_BH))

p_dot = DotPlot(sub, features = tf_present, group.by = "origin_group") + RotatedAxis() +
  ggtitle("C/EBP and AP-1 family TF mRNA by refined origin group")
ggsave(file.path(fig_dir, "14_tf_scrna_dotplot.png"), p_dot, width = 9, height = 4.5, dpi = 300)

message("\nDone: TF mRNA-expression proxy analysis complete (decoupleR/CollecTRI unavailable in this environment).")
