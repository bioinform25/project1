# 02_gse166504_cluster_annotate.R
# Requires: 01_gse166504_extract_myeloid.R
# Provides: results/gse166504_annotated.rds, results/gse166504_signature_check.csv,
#           figures/gse166504_*.png
#
# Question: does an S100a8/S100a9-hi, Ly6g-negative, Csf1r/Cd68/Adgre1-moderate
# macrophage/monocyte population (as defined in project1) reproducibly appear across
# multiple mice (real biological replicates: Chow n=3, 15wk-NAFL n=3, 30wk-NASH n=4,
# 34wk n=1) in this independent dataset, distinct from the author-labeled Neutrophil
# population and from resident Kupffer cells?

source("scripts/00_setup.R")  # reuses project1's library loads / options
library(data.table)

results_dir = "external_validation/results"
fig_dir = "external_validation/figures"
dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)

mat = readRDS(file.path(results_dir, "gse166504_myeloid_counts.rds"))
meta = readRDS(file.path(results_dir, "gse166504_myeloid_meta.rds"))

# Parse FileName -> diet condition + animal
meta[, c("npc_tag", "condition", "animal", "capture") := tstrsplit(FileName, "_", fixed = FALSE)]
meta[, condition := factor(condition, levels = c("Chow", "15weeks", "30weeks", "34weeks"))]
meta_df = as.data.frame(meta)
rownames(meta_df) = meta_df$full_name

obj = CreateSeuratObject(counts = mat, meta.data = meta_df[colnames(mat), ], min.cells = 3, min.features = 100)
obj[["percent.mt"]] = PercentageFeatureSet(obj, pattern = "^mt-")

message(sprintf("Cells before QC: %d", ncol(obj)))
obj = subset(obj, subset = nFeature_RNA > 100 & percent.mt < 30)
message(sprintf("Cells after QC: %d", ncol(obj)))
print(table(obj$condition, obj$CellType))

obj = NormalizeData(obj)
obj = FindVariableFeatures(obj, nfeatures = 2000)
obj = ScaleData(obj)
obj = RunPCA(obj, npcs = 30)
obj = FindNeighbors(obj, dims = 1:30)
obj = FindClusters(obj, resolution = 0.6)
obj = RunUMAP(obj, dims = 1:30)

p_umap_cluster = DimPlot(obj, label = TRUE) + ggtitle("GSE166504 myeloid subclusters")
p_umap_authorlabel = DimPlot(obj, group.by = "CellType") + ggtitle("Author-provided CellType label")
p_umap_animal = DimPlot(obj, group.by = "animal") + facet_wrap(~obj$condition) + ggtitle("By animal / condition")
ggsave(file.path(fig_dir, "gse166504_umap_clusters.png"), p_umap_cluster, width = 6, height = 5, dpi = 300)
ggsave(file.path(fig_dir, "gse166504_umap_authorlabel.png"), p_umap_authorlabel, width = 6, height = 5, dpi = 300)
ggsave(file.path(fig_dir, "gse166504_umap_animal.png"), p_umap_animal, width = 10, height = 8, dpi = 300)

# Cross-tab: our subclusters vs author's own coarse labels
print(table(obj$seurat_clusters, obj$CellType))
write.csv(as.data.frame.matrix(table(obj$seurat_clusters, obj$CellType)),
          file.path(results_dir, "gse166504_cluster_vs_authorlabel.csv"))

# Signature check genes (same panel used to define S100A8hi_macrophage vs Neutrophil in project1)
sig_genes = c("S100a8", "S100a9", "Ly6g", "Camp", "Ltf", "Ngp", "Csf1r", "Adgre1", "Clec4f", "Cd68", "Trem2", "Gpnmb")
sig_genes = intersect(sig_genes, rownames(obj))
p_dot = DotPlot(obj, features = sig_genes) + RotatedAxis() + ggtitle("Signature marker check per subcluster")
ggsave(file.path(fig_dir, "gse166504_signature_dotplot.png"), p_dot, width = 9, height = 6, dpi = 300)

pct_expr = sapply(sig_genes, function(g) {
  tapply(GetAssayData(obj, layer = "data")[g, ], obj$seurat_clusters, function(x) mean(x > 0))
})
avg_expr = AverageExpression(obj, features = sig_genes, group.by = "seurat_clusters", layer = "data")$RNA
write.csv(round(pct_expr, 3), file.path(results_dir, "gse166504_pct_expr_by_cluster.csv"))
write.csv(round(avg_expr, 3), file.path(results_dir, "gse166504_avg_expr_by_cluster.csv"))
message("=== pct expressing per cluster ==="); print(round(pct_expr, 2))

saveRDS(obj, file.path(results_dir, "gse166504_annotated.rds"))
message("Done: gse166504_annotated.rds saved.")
