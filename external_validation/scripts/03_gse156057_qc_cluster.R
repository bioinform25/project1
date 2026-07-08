# 03_gse156057_qc_cluster.R
# GSE156057 (Remmerie et al. 2020 Immunity): CD45+-sorted mouse liver immune cells,
# standard diet (SD) vs western diet (WD), 12/24/36 week timepoints, 1 sample each
# (6 CD45+ samples total -- pseudo-replicates across independent mice/timepoints,
# not true within-condition replicates, but CD45+ sorting gives much cleaner myeloid
# resolution than whole-liver capture). Thematically the closest external paper to
# project1's finding (they specifically report a macrophage subset distinct from
# resident Kupffer cells in fatty liver).
#
# Provides: external_validation/results/gse156057_annotated.rds, signature-check csv/figures

source("scripts/00_setup.R")

data_dir = "external_validation/data/GSE156057"
results_dir = "external_validation/results"
fig_dir = "external_validation/figures"

samples = c(
  "GSM4721496_cd45pos-sd-12w" = "SD_12w",
  "GSM4721497_cd45pos-wd-12w" = "WD_12w",
  "GSM4721498_cd45pos-sd-24w" = "SD_24w",
  "GSM4721499_cd45pos-wd-24w" = "WD_24w",
  "GSM4721500_cd45pos-sd-36w" = "SD_36w",
  "GSM4721501_cd45pos-wd-36w" = "WD_36w"
)

seurat_list = lapply(names(samples), function(gsm_prefix) {
  fpath = file.path(data_dir, paste0(gsm_prefix, "_filtered_feature_bc_matrix.h5"))
  mat = Read10X_h5(fpath)
  if (is.list(mat)) mat = mat[["Gene Expression"]]  # drop Antibody Capture modality
  obj = CreateSeuratObject(counts = mat, project = unname(samples[gsm_prefix]), min.cells = 3, min.features = 200)
  obj$sample = unname(samples[gsm_prefix])
  obj$diet = unname(sub("_.*", "", samples[gsm_prefix]))
  obj$timepoint = unname(sub(".*_", "", samples[gsm_prefix]))
  obj[["percent.mt"]] = PercentageFeatureSet(obj, pattern = "^mt-")
  obj
})
names(seurat_list) = samples

pre_counts = sapply(seurat_list, ncol)
message("Cells per sample before QC: "); print(pre_counts)

seurat_list = lapply(seurat_list, function(obj) {
  subset(obj, subset = nFeature_RNA > 200 & nFeature_RNA < 6000 & nCount_RNA < 30000 & percent.mt < 25)
})
post_counts = sapply(seurat_list, ncol)
message("Cells per sample after QC: "); print(post_counts)

merged = merge(seurat_list[[1]], seurat_list[-1], add.cell.ids = names(seurat_list))
merged = JoinLayers(merged)

merged = NormalizeData(merged)
merged = FindVariableFeatures(merged, nfeatures = 2000)
merged = ScaleData(merged)
merged = RunPCA(merged, npcs = 30)
merged = FindNeighbors(merged, dims = 1:30)
merged = FindClusters(merged, resolution = 0.8)
merged = RunUMAP(merged, dims = 1:30)

p_umap = DimPlot(merged, label = TRUE) + ggtitle("GSE156057 CD45+ clusters")
p_umap_sample = DimPlot(merged, group.by = "sample") + ggtitle("By sample")
ggsave(file.path(fig_dir, "gse156057_umap_clusters.png"), p_umap, width = 6, height = 5, dpi = 300)
ggsave(file.path(fig_dir, "gse156057_umap_sample.png"), p_umap_sample, width = 7, height = 5, dpi = 300)

sig_genes = c("S100a8", "S100a9", "Ly6g", "Camp", "Ltf", "Ngp", "Csf1r", "Adgre1", "Clec4f", "Cd68", "Trem2", "Gpnmb",
              "Cd3e", "Cd79a", "Ncr1", "Itgam", "Ccr2")
sig_genes = intersect(sig_genes, rownames(merged))
p_dot = DotPlot(merged, features = sig_genes) + RotatedAxis() + ggtitle("Signature marker check per cluster")
ggsave(file.path(fig_dir, "gse156057_signature_dotplot.png"), p_dot, width = 10, height = 6, dpi = 300)

pct_expr = sapply(sig_genes, function(g) {
  tapply(GetAssayData(merged, layer = "data")[g, ], merged$seurat_clusters, function(x) mean(x > 0))
})
write.csv(round(pct_expr, 3), file.path(results_dir, "gse156057_pct_expr_by_cluster.csv"))
message("=== pct expressing per cluster ==="); print(round(pct_expr, 2))

# Save annotated object BEFORE the slow FindAllMarkers step (40 clusters x 77k cells is
# very slow on this machine) so downstream proportion analysis isn't blocked on it.
saveRDS(merged, file.path(results_dir, "gse156057_annotated.rds"))
message("Saved gse156057_annotated.rds (before FindAllMarkers).")

cluster_markers = FindAllMarkers(merged, only.pos = TRUE, min.pct = 0.25, logfc.threshold = 0.5)
write.csv(cluster_markers, file.path(results_dir, "gse156057_cluster_markers.csv"), row.names = FALSE)
top5 = cluster_markers %>% group_by(cluster) %>% slice_max(avg_log2FC, n = 5)
write.csv(top5, file.path(results_dir, "gse156057_cluster_top5.csv"), row.names = FALSE)
message("Done: FindAllMarkers complete.")
