# 01_gse166504_extract_myeloid.R
# GSE166504 (mouse liver NPC scRNA-seq, chow/15wk-NAFL/30wk-NASH/34wk, iScience 2021).
# Raw count matrix is genes(rows) x cells(cols), header row has 1 fewer field than
# data rows (implicit gene-name index column) -> data column i+1 = header cell i.
# Extracts only myeloid cells (Kupffer cells, Monocyte/MoMF, Neutrophils; author-provided
# CellType labels) to keep the matrix small enough to work with directly.

library(data.table)

data_dir = "external_validation/data/GSE166504"
results_dir = "external_validation/results"
dir.create(results_dir, recursive = TRUE, showWarnings = FALSE)

meta = fread(file.path(data_dir, "GSE166504_cell_metadata.tsv.gz"))
meta[, full_name := paste0(FileName, "_", CellID)]

myeloid_types = c("Kupffer cells", "Monocyte/Monocyte derived macrophage", "Neutrophils")
meta_myeloid = meta[CellType %in% myeloid_types]
message(sprintf("Myeloid cells to extract: %d", nrow(meta_myeloid)))
print(table(meta_myeloid$CellType))

header_line = readLines(file.path(data_dir, "GSE166504_cell_raw_counts.txt.gz"), n = 1)
cell_names = strsplit(header_line, "\t")[[1]]
message(sprintf("Total cells in header: %d", length(cell_names)))

pos = match(meta_myeloid$full_name, cell_names)
stopifnot(all(!is.na(pos)))
data_cols = pos + 1L  # +1 because data rows have leading gene-name field

counts = fread(
  file.path(data_dir, "GSE166504_cell_raw_counts.txt.gz"),
  sep = "\t", skip = 1, select = c(1L, data_cols), header = FALSE
)
setnames(counts, c("gene", meta_myeloid$full_name))
message(sprintf("Extracted matrix: %d genes x %d cells", nrow(counts), ncol(counts) - 1))

gene_names = counts$gene
mat = as.matrix(counts[, -1, with = FALSE])
rownames(mat) = gene_names
stopifnot(!any(duplicated(gene_names)))

saveRDS(mat, file.path(results_dir, "gse166504_myeloid_counts.rds"))
saveRDS(meta_myeloid, file.path(results_dir, "gse166504_myeloid_meta.rds"))
message("Saved gse166504_myeloid_counts.rds and gse166504_myeloid_meta.rds")
