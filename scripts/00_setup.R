# 00_setup.R
# 모든 하위 스크립트가 사용하는 패키지 로드 + 경로 상수 정의.
# 작업 디렉토리는 project1.Rproj를 연 상태(레포 루트)를 가정.

set.seed(42)
options(repos = c(CRAN = "https://cloud.r-project.org"))

required_pkgs = c(
  "Seurat", "hdf5r", "Biobase", "BisqueRNA", "DESeq2", "limma",
  "tidyverse", "readxl", "pheatmap", "ggplot2", "ggpubr", "rstatix",
  "patchwork"
)

missing_pkgs = setdiff(required_pkgs, rownames(installed.packages()))
if (length(missing_pkgs) > 0) {
  # BisqueRNA is archived on CRAN (not built for current R) -> install from GitHub source.
  if ("BisqueRNA" %in% missing_pkgs) {
    if (!requireNamespace("remotes", quietly = TRUE)) install.packages("remotes")
    remotes::install_github("cozygene/bisque", upgrade = "never")
    missing_pkgs = setdiff(missing_pkgs, "BisqueRNA")
  }

  cran_pkgs = intersect(missing_pkgs, c("ggpubr", "rstatix", "patchwork"))
  if (length(cran_pkgs) > 0) install.packages(cran_pkgs)

  bioc_pkgs = setdiff(missing_pkgs, cran_pkgs)
  if (length(bioc_pkgs) > 0) {
    if (!requireNamespace("BiocManager", quietly = TRUE)) install.packages("BiocManager")
    BiocManager::install(bioc_pkgs, update = FALSE, ask = FALSE)
  }
}

invisible(lapply(required_pkgs, library, character.only = TRUE))

data_dir    = "data/raw"
results_dir = "results"
fig_dir     = "figures"
dir.create(results_dir, showWarnings = FALSE)
dir.create(fig_dir, showWarnings = FALSE)
