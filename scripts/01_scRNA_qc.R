# 01_scRNA_qc.R
# GSE285615 scRNA-seq (WT, TG 각 1개 샘플, 전체 간 조직 10x) QC
# Requires: 00_setup.R
# Provides: results/scrna_qc_list.rds (QC 통과한 WT/TG Seurat 객체 리스트, 병합 전)

source("scripts/00_setup.R")

mats = list(
  WT = Read10X_h5(file.path(data_dir, "GSM8705804_WT_filtered_feature_bc_matrix.h5")),
  TG = Read10X_h5(file.path(data_dir, "GSM8705805_TG_filtered_feature_bc_matrix.h5"))
)

seurat_list = lapply(names(mats), function(sample_name) {
  obj = CreateSeuratObject(
    counts = mats[[sample_name]],
    project = sample_name,
    min.cells = 3,
    min.features = 200
  )
  obj$genotype = sample_name
  obj[["percent.mt"]] = PercentageFeatureSet(obj, pattern = "^mt-")
  obj
})
names(seurat_list) = names(mats)

pre_qc_counts = sapply(seurat_list, ncol)
message("QC 전 세포 수: ", paste(names(pre_qc_counts), pre_qc_counts, sep = "=", collapse = ", "))

qc_vln = VlnPlot(
  merge(seurat_list[[1]], seurat_list[[2]]),
  features = c("nFeature_RNA", "nCount_RNA", "percent.mt"),
  group.by = "orig.ident", ncol = 3, pt.size = 0
)
ggsave(file.path(fig_dir, "01_qc_violin_prefilter.png"), qc_vln, width = 10, height = 4, dpi = 300)

# 간 조직 whole-tissue 10x 기준 QC 컷오프: 간세포는 미토콘드리아 비중이 높은 편이라 25%까지 허용,
# nFeature 상한은 doublet 배제용, 하한은 empty droplet/저품질 세포 배제용.
qc_filtered = lapply(seurat_list, function(obj) {
  subset(obj, subset = nFeature_RNA > 200 & nFeature_RNA < 6000 & nCount_RNA < 30000 & percent.mt < 25)
})

post_qc_counts = sapply(qc_filtered, ncol)
message("QC 후 세포 수: ", paste(names(post_qc_counts), post_qc_counts, sep = "=", collapse = ", "))

qc_summary = data.frame(
  sample = names(pre_qc_counts),
  n_cells_prefilter = pre_qc_counts,
  n_cells_postfilter = post_qc_counts
)
write.csv(qc_summary, file.path(results_dir, "01_qc_summary.csv"), row.names = FALSE)

saveRDS(qc_filtered, file.path(results_dir, "scrna_qc_list.rds"))
