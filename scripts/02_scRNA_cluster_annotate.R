# 02_scRNA_cluster_annotate.R
# Requires: 01_scRNA_qc.R (results/scrna_qc_list.rds)
# Provides: results/scrna_annotated.rds (클러스터링 + 세포타입 라벨 부여된 병합 Seurat 객체)
#
# 주의: 샘플이 WT 1개, TG 1개뿐이라 sample == genotype이 완전히 confound됨.
# Harmony 등으로 샘플 간 배치보정을 하면 우리가 정량하려는 바로 그 생물학적 신호
# (WT->TG 대식세포 구성 변화)까지 지워버릴 위험이 있어, 여기서는 배치보정 없이
# 단순 병합 후 공동 클러스터링만 수행한다. 주요 세포타입(간세포 vs 대식세포 vs
# 내피세포 등)의 발현 차이가 이 정도의 배치효과보다 훨씬 크므로 클러스터링 자체는
# 안정적일 것으로 기대.

source("scripts/00_setup.R")

qc_list = readRDS(file.path(results_dir, "scrna_qc_list.rds"))

merged = merge(qc_list[[1]], qc_list[[2]], add.cell.ids = names(qc_list))
merged = JoinLayers(merged)

merged = NormalizeData(merged)
merged = FindVariableFeatures(merged, nfeatures = 2000)
merged = ScaleData(merged)
merged = RunPCA(merged, npcs = 30)
merged = FindNeighbors(merged, dims = 1:30)
merged = FindClusters(merged, resolution = 0.8)
merged = RunUMAP(merged, dims = 1:30)

p_umap = DimPlot(merged, reduction = "umap", label = TRUE) + ggtitle("Clusters (res=0.8)")
p_umap_geno = DimPlot(merged, reduction = "umap", group.by = "genotype")
ggsave(file.path(fig_dir, "02_umap_clusters.png"), p_umap, width = 6, height = 5, dpi = 300)
ggsave(file.path(fig_dir, "02_umap_by_genotype.png"), p_umap_geno, width = 6, height = 5, dpi = 300)

# 간 조직 canonical marker (major lineage 구분용)
canonical_markers = c(
  "Alb", "Apoa1", "Ttr", "Cyp2e1",            # Hepatocyte
  "Clec4f", "Csf1r", "Adgre1", "Cd68",        # Kupffer/Macrophage
  "S100a8", "S100a9", "Ly6g",                 # Neutrophil / S100A8-hi myeloid
  "Ly6c2", "Ccr2",                            # Monocyte
  "Pecam1", "Stab2", "Clec4g",                # LSEC
  "Dcn", "Colec11", "Pdgfrb",                 # Stellate cell
  "Cd3e", "Cd3d",                             # T cell
  "Cd79a", "Ms4a1",                           # B cell
  "Ncr1", "Klrb1c",                           # NK cell
  "Krt19", "Epcam"                            # Cholangiocyte
)
canonical_markers = intersect(canonical_markers, rownames(merged))

p_dot = DotPlot(merged, features = canonical_markers) + RotatedAxis() +
  theme(axis.text.x = element_text(size = 8))
ggsave(file.path(fig_dir, "02_marker_dotplot.png"), p_dot, width = 12, height = 6, dpi = 300)

cluster_markers = FindAllMarkers(merged, only.pos = TRUE, min.pct = 0.25, logfc.threshold = 0.5)
write.csv(cluster_markers, file.path(results_dir, "02_cluster_markers.csv"), row.names = FALSE)

top5 = cluster_markers %>% group_by(cluster) %>% slice_max(avg_log2FC, n = 5)
write.csv(top5, file.path(results_dir, "02_cluster_top5_markers.csv"), row.names = FALSE)

cluster_sizes = table(merged$seurat_clusters, merged$genotype)
write.csv(as.data.frame.matrix(cluster_sizes), file.path(results_dir, "02_cluster_sizes_by_genotype.csv"))

saveRDS(merged, file.path(results_dir, "scrna_clustered_unannotated.rds"))

message("클러스터 수: ", length(unique(merged$seurat_clusters)))
print(top5, n = 200)
