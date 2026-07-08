# 06_deconvolution.R
# Requires: 03_scRNA_annotate_finalize.R (results/scrna_annotated.rds),
#           05_bulk_load_merge.R (results/bulk_counts.rds)
# Provides: results/06_deconvolution_props.csv (cell_type x sample 상대 abundance score, 34개 bulk 시료 전체)
#
# scRNA reference가 genotype당 1개 샘플뿐이라 subject-variance 기반 방법(MuSiC, Bisque의
# ReferenceBasedDecomposition)은 부적절 -> BisqueRNA::MarkerBasedDecomposition (마커 유전자
# 집합의 첫 PC를 상대 abundance score로 사용, cross-subject variance 불필요) 사용.
# 주의: 결과값은 세포타입 간 절대 비율(합이 1)이 아니라 세포타입별 상대적 scale의 PCA score다.
# 같은 세포타입을 시료 간(WT vs TG, WT vs MKO)으로 비교하는 데는 유효하지만, 세포타입 간
# 절대적 크기 비교에는 쓸 수 없다.

source("scripts/00_setup.R")

annotated = readRDS(file.path(results_dir, "scrna_annotated.rds"))
bulk = readRDS(file.path(results_dir, "bulk_counts.rds"))

Idents(annotated) = annotated$cell_type
ct_markers = FindAllMarkers(annotated, only.pos = TRUE, min.pct = 0.25, logfc.threshold = 0.5)
ct_markers = ct_markers %>%
  arrange(cluster, p_val_adj, desc(avg_log2FC)) %>%
  select(cluster, gene, avg_log2FC, p_val_adj)
write.csv(ct_markers, file.path(results_dir, "06_celltype_markers.csv"), row.names = FALSE)

message(sprintf("%d개 세포타입, 세포타입당 마커 유전자 수:", length(unique(ct_markers$cluster))))
print(table(ct_markers$cluster))

# bulk: raw count -> CPM -> log2(CPM+1). PCA 기반 방법이라 분산안정화를 위해 log 스케일 사용.
lib_size = colSums(bulk$counts)
cpm = sweep(bulk$counts, 2, lib_size, "/") * 1e6
logcpm = log2(cpm + 1)

overlap_genes = intersect(rownames(logcpm), unique(ct_markers$gene))
message(sprintf("bulk-scRNA 마커 유전자 교집합: %d / %d", length(overlap_genes), length(unique(ct_markers$gene))))

bulk_eset = Biobase::ExpressionSet(assayData = as.matrix(logcpm))

decon = MarkerBasedDecomposition(
  bulk.eset = bulk_eset,
  markers = ct_markers,
  ct_col = "cluster",
  gene_col = "gene",
  weighted = TRUE,
  w_col = "avg_log2FC",
  min_gene = 5,
  max_gene = 100,
  unique_markers = TRUE,
  verbose = TRUE
)

props = as.data.frame(t(decon$bulk.props))
props$sample = rownames(props)
props = props %>% left_join(bulk$meta, by = "sample")

write.csv(props, file.path(results_dir, "06_deconvolution_props.csv"), row.names = FALSE)
saveRDS(decon, file.path(results_dir, "06_decon_full.rds"))

message("완료. 세포타입별 사용된 마커 유전자 수:")
print(sapply(decon$genes.used, length))
