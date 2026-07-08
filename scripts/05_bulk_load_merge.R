# 05_bulk_load_merge.R
# Requires: 00_setup.R
# Provides: results/bulk_counts.rds (list(counts=gene x 34 sample raw count matrix, meta=sample metadata))
#
# GSE285614는 두 개의 별도 DESeq2 비교 xlsx로 나뉘어 있고, 각 xlsx의 시료별 raw count가
# 통계 요약 컬럼(log2FoldChange 등) 옆에 같이 들어있다 (GEO 제출자가 원본 count를 같이 올림).
# axis 1(HFD_TG_vs_WT.xlsx)과 axis 2(MKO_HFD_vs_WT_HFD.xlsx)는 서로 다른 시퀀싱 배치이며,
# 두 파일 모두에 "WT" 시료가 있지만 실험적으로 다른 리터메이트 대조군이므로 genotype과
# axis를 분리해서 기록한다 (같은 배치로 착각해 풀링하지 않기 위함).

source("scripts/00_setup.R")

parse_bulk_xlsx = function(path, axis_label) {
  d = read_excel(path)
  meta_cols = c("ENSEMBL", "SYMBOL", "ENTREZID", "baseMean", "log2FoldChange",
                "lfcSE", "stat", "pvalue", "padj", "GSEArank")
  sample_cols = setdiff(colnames(d), c(colnames(d)[1], meta_cols))

  counts = as.data.frame(d[, sample_cols])
  rownames(counts) = NULL
  counts$SYMBOL = d$SYMBOL
  counts = counts %>%
    filter(!is.na(SYMBOL), SYMBOL != "") %>%
    group_by(SYMBOL) %>%
    summarise(across(all_of(sample_cols), \(x) sum(x, na.rm = TRUE)), .groups = "drop")

  count_mat = as.matrix(counts[, sample_cols])
  rownames(count_mat) = counts$SYMBOL

  list(counts = count_mat, samples = sample_cols, axis = axis_label)
}

axis1 = parse_bulk_xlsx(file.path(data_dir, "GSE285614_HFD_TG_vs_WT.xlsx"), "adipocyte_death")
axis2 = parse_bulk_xlsx(file.path(data_dir, "GSE285614_MKO_HFD_vs_WT_HFD.xlsx"), "macrophage_KO")

message(sprintf("axis1: %d genes x %d samples / axis2: %d genes x %d samples",
                 nrow(axis1$counts), ncol(axis1$counts), nrow(axis2$counts), ncol(axis2$counts)))

common_genes = intersect(rownames(axis1$counts), rownames(axis2$counts))
message(sprintf("두 axis 공통 유전자: %d개", length(common_genes)))

counts_all = cbind(axis1$counts[common_genes, ], axis2$counts[common_genes, ])
stopifnot(ncol(counts_all) == 34)

# 샘플명 -> genotype/diet/axis 메타데이터 파싱
parse_sample_name = function(s, axis) {
  if (axis == "adipocyte_death") {
    diet = ifelse(grepl("^HFD", s), "HFD", "Chow")
    genotype = ifelse(grepl("WT", s), "WT", "Bcl2TG")
  } else {
    diet = ifelse(grepl("HFD", s), "HFD", "Chow")
    genotype = ifelse(grepl("^MKO", s), "MKO", "WT")
  }
  data.frame(sample = s, axis = axis, genotype = genotype, diet = diet)
}

meta = bind_rows(
  lapply(axis1$samples, parse_sample_name, axis = "adipocyte_death"),
  lapply(axis2$samples, parse_sample_name, axis = "macrophage_KO")
)
meta$group = paste(meta$axis, meta$genotype, meta$diet, sep = "_")
rownames(meta) = meta$sample
meta = meta[colnames(counts_all), ]

stopifnot(identical(rownames(meta), colnames(counts_all)))
print(table(meta$axis, meta$genotype, meta$diet))

saveRDS(list(counts = counts_all, meta = meta), file.path(results_dir, "bulk_counts.rds"))
write.csv(meta, file.path(results_dir, "05_bulk_sample_metadata.csv"), row.names = FALSE)
