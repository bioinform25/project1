# 09_correlate_lipid_genes.R
# Requires: 05_bulk_load_merge.R, 06_deconvolution.R
# Provides: results/09_lipid_gene_correlation.csv, figures/09_correlation_*.png
#
# 논문의 핵심 기전(S100A8+ macrophage -> CCN3 억제 -> CD36 상승 -> 간세포 지질축적)이
# 우리 deconvolution 결과와도 이어지는지 확인: S100A8hi_macrophage/Macrophage_Kupffer
# 상대 abundance score가 같은 시료의 Cd36/Ccn3(Nov) 발현과 상관관계가 있는지 34개 bulk
# 시료 전체에서 검정.

source("scripts/00_setup.R")

bulk = readRDS(file.path(results_dir, "bulk_counts.rds"))
props = read.csv(file.path(results_dir, "06_deconvolution_props.csv"))

lib_size = colSums(bulk$counts)
logcpm = log2(sweep(bulk$counts, 2, lib_size, "/") * 1e6 + 1)

lipid_genes = intersect(c("Cd36", "Ccn3", "Nov", "Plin2", "Fasn", "Scd1", "Pparg"), rownames(logcpm))
message("사용 가능한 지질 관련 유전자: ", paste(lipid_genes, collapse = ", "))

gene_expr = as.data.frame(t(logcpm[lipid_genes, , drop = FALSE]))
gene_expr$sample = rownames(gene_expr)

merged = props %>% left_join(gene_expr, by = "sample")

cor_results = expand.grid(
  cell_type = c("S100A8hi_macrophage", "Macrophage_Kupffer"),
  gene = lipid_genes,
  subset = c("all_HFD", "axis1_HFD", "axis2_HFD"),
  stringsAsFactors = FALSE
) %>%
  rowwise() %>%
  mutate(
    dat = list(
      switch(subset,
        all_HFD  = merged %>% filter(diet == "HFD"),
        axis1_HFD = merged %>% filter(diet == "HFD", axis == "adipocyte_death"),
        axis2_HFD = merged %>% filter(diet == "HFD", axis == "macrophage_KO")
      )
    ),
    r = cor(dat[[cell_type]], dat[[gene]], method = "spearman"),
    p_value = cor.test(dat[[cell_type]], dat[[gene]], method = "spearman")$p.value,
    n = nrow(dat)
  ) %>%
  ungroup() %>%
  select(-dat) %>%
  arrange(cell_type, gene, subset)

write.csv(cor_results, file.path(results_dir, "09_lipid_gene_correlation.csv"), row.names = FALSE)
print(cor_results, n = 50)

p_cd36 = merged %>% filter(diet == "HFD") %>%
  ggplot(aes(x = S100A8hi_macrophage, y = Cd36, color = axis, shape = genotype)) +
  geom_point(size = 3) +
  geom_smooth(aes(group = 1), method = "lm", se = TRUE, color = "black", linewidth = 0.5) +
  theme_bw() +
  labs(title = "S100A8hi_macrophage score vs Cd36 expression (all HFD bulk samples, n=19)",
       x = "S100A8hi_macrophage relative abundance score", y = "Cd36 log2(CPM+1)")
ggsave(file.path(fig_dir, "09_correlation_S100A8_vs_Cd36.png"), p_cd36, width = 7, height = 5, dpi = 300)

if ("Ccn3" %in% lipid_genes || "Nov" %in% lipid_genes) {
  ccn3_gene = intersect(c("Ccn3", "Nov"), lipid_genes)[1]
  p_ccn3 = merged %>% filter(diet == "HFD") %>%
    ggplot(aes(x = S100A8hi_macrophage, y = .data[[ccn3_gene]], color = axis, shape = genotype)) +
    geom_point(size = 3) +
    geom_smooth(aes(group = 1), method = "lm", se = TRUE, color = "black", linewidth = 0.5) +
    theme_bw() +
    labs(title = sprintf("S100A8hi_macrophage score vs %s expression (all HFD bulk samples)", ccn3_gene),
         x = "S100A8hi_macrophage relative abundance score", y = sprintf("%s log2(CPM+1)", ccn3_gene))
  ggsave(file.path(fig_dir, "09_correlation_S100A8_vs_Ccn3.png"), p_ccn3, width = 7, height = 5, dpi = 300)
}
