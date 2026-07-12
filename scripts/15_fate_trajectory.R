# 15_fate_trajectory.R
# Requires: 03_scRNA_annotate_finalize.R (scrna_annotated.rds), 13_origin_signature_scoring.R
#           (same refined origin-group logic), external_validation/results/
#           gse156057_S100A8hi_proportions.csv (04_gse156057_proportions.R)
# Provides: results/15_fate_neighbor_purity.csv, results/15_fate_compositional_trend.csv,
#           figures/15_fate_*.png
#
# 원 논문은 HFD 4개월 딱 한 시점만 scRNA로 봐서, S100A8hi_macrophage가 (a) 계속 유지되는
# 안정적 상태인지 (b) 시간이 지나며 다른 상태(예: LAM-유사 성숙 대식세포)로 이행하는 전이
# 상태인지 전혀 알 수 없다. 정식 pseudotime 소프트웨어(slingshot/monocle3)는 이 환경에
# 설치되어 있지 않아(계획서에 명시한 리스크) 두 가지 저위험 대안으로 접근:
#
# (a) 구성비 시간 추세: 이미 계산된 GSE156057(12/24/36주 시계열)의 S100A8hi_macrophage와
#     Kupffer 구성비가 반대 방향으로 움직이는지(성숙 모델과 부합) 아니면 독립적으로 식이만
#     따라가는지(지속 모집 모델과 부합) 검정.
# (b) 전사체적 연속성: Module 1에서 발견한 정제된 4-그룹(S100A8hi_macrophage/Kupffer_
#     resident/Macrophage_MoMF_LAM/Neutrophil)에 한정해 PCA 최근접이웃 구성을 본다.
#     S100A8hi 세포의 이웃 대부분이 S100A8hi 자신이면 안정된 별개 상태, MoMF_LAM 쪽으로
#     상당수 새어나가면(neighbor "leakage") 전이 중인 연속체에 가깝다는 뜻.

source("scripts/00_setup.R")

# ============================================== (a) GSE156057 compositional trend ==
props = read.csv(file.path("external_validation/results", "gse156057_S100A8hi_proportions.csv"))
props$timepoint_num = as.numeric(sub("w", "", props$timepoint))

trend_test = function(df, cls, diet_level) {
  d = df %>% filter(cell_class == cls, diet == diet_level)
  if (nrow(d) < 3) return(data.frame(cell_class = cls, diet = diet_level, n = nrow(d),
                                      slope = NA, p_value = NA))
  fit = lm(proportion ~ timepoint_num, data = d)
  s = summary(fit)$coefficients
  data.frame(cell_class = cls, diet = diet_level, n = nrow(d),
             slope = s["timepoint_num", "Estimate"], p_value = s["timepoint_num", "Pr(>|t|)"])
}

trend_results = expand.grid(cls = c("S100A8hi_macrophage", "Kupffer"), diet_level = c("SD", "WD"),
                             stringsAsFactors = FALSE) %>%
  purrr::pmap_dfr(function(cls, diet_level) trend_test(props, cls, diet_level))
write.csv(trend_results, file.path(results_dir, "15_fate_compositional_trend.csv"), row.names = FALSE)
message("=== GSE156057: proportion ~ timepoint slope, by cell class and diet ===")
print(trend_results)
message(
  "\nInterpretation: opposite-signed WD slopes for S100A8hi_macrophage vs Kupffer would ",
  "support a maturation (S100A8hi -> Kupffer-like) model; same-signed or flat slopes support ",
  "independent, diet-driven recruitment of both without direct conversion."
)

p_trend = props %>% filter(cell_class %in% c("S100A8hi_macrophage", "Kupffer")) %>%
  ggplot(aes(x = timepoint_num, y = proportion, color = diet)) +
  geom_point(size = 3) + geom_smooth(method = "lm", se = FALSE) +
  facet_wrap(~cell_class, scales = "free_y") + theme_bw() +
  labs(title = "GSE156057: S100A8hi_macrophage vs Kupffer proportion over time",
       x = "Timepoint (weeks)", y = "Proportion of CD45+ cells")
ggsave(file.path(fig_dir, "15_fate_compositional_trend.png"), p_trend, width = 9, height = 4.5, dpi = 300)

# ===================================== (b) transcriptional continuity (primary ref) ==
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

# Fresh PCA/neighbor graph restricted to just these 4 groups, so neighbor composition
# isn't diluted by hepatocytes/endothelial/etc.
sub = FindVariableFeatures(sub, nfeatures = 2000, verbose = FALSE)
sub = ScaleData(sub, verbose = FALSE)
sub = RunPCA(sub, npcs = 20, verbose = FALSE)
sub = RunUMAP(sub, dims = 1:20, verbose = FALSE)

pca_mat = Embeddings(sub, "pca")[, 1:20]
k = 30
nn = FNN::get.knn(pca_mat, k = k)$nn.index

origin_vec = as.character(sub$origin_group)
neighbor_composition = t(apply(nn, 1, function(idx) table(factor(origin_vec[idx], levels = target_clusters))))
neighbor_composition = as.data.frame(neighbor_composition / k)
neighbor_composition$own_group = origin_vec

purity_summary = neighbor_composition %>%
  group_by(own_group) %>%
  summarise(across(all_of(target_clusters), mean), n_cells = n()) %>%
  rename_with(~paste0("pct_neighbors_", .x), all_of(target_clusters))

write.csv(purity_summary, file.path(results_dir, "15_fate_neighbor_purity.csv"), row.names = FALSE)
message("\n=== Mean fraction of k=30 nearest PCA-space neighbors belonging to each origin group ===")
print(as.data.frame(purity_summary))
message(
  "\nInterpretation: high on-diagonal values (own group's neighbors mostly the same group) ",
  "indicate discrete, well-separated states. Substantial off-diagonal 'leakage' from ",
  "S100A8hi_macrophage into Macrophage_MoMF_LAM (or vice versa) would indicate a ",
  "transcriptional continuum consistent with an ongoing transition between the two."
)

p_umap = DimPlot(sub, group.by = "origin_group", label = TRUE, repel = TRUE) +
  ggtitle("Refined origin groups, restricted UMAP (S100A8hi/Kupffer_resident/MoMF_LAM/Neutrophil)")
lam_present = intersect(c("Trem2", "Gpnmb"), rownames(sub))
sub = AddModuleScore(sub, features = list(lam_present), name = "LamScore")
sub$LamScore = sub$LamScore1
p_lam = FeaturePlot(sub, features = "LamScore") + ggtitle("Trem2/Gpnmb (LAM) module score")
ggsave(file.path(fig_dir, "15_fate_umap_origin.png"), p_umap, width = 7, height = 5.5, dpi = 300)
ggsave(file.path(fig_dir, "15_fate_umap_lamscore.png"), p_lam, width = 6.5, height = 5.5, dpi = 300)

message("\nDone: fate/trajectory analysis complete.")
