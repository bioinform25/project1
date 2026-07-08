# 03_scRNA_annotate_finalize.R
# Requires: 02_scRNA_cluster_annotate.R (results/scrna_clustered_unannotated.rds,
#           results/02_cluster_top5_markers.csv)
# Provides: results/scrna_annotated.rds (cell_type 라벨 부여, 저품질/모호 클러스터 제외)
#
# 클러스터 0.8 해상도 결과, 골수계(myeloid) 세부 클러스터가 이미 잘 분리되어 있어
# 별도의 myeloid subclustering 없이 바로 라벨링 가능함을 확인했다 (S100a8/S100a9/Ly6g/
# Csf1r/Adgre1/Clec4f/Trem2/Gpnmb 발현을 클러스터별로 직접 조회, check 스크립트는 1회성이라 삭제).
#
# 핵심 발견: 클러스터 12(S100a8/9 ~94% 양성, Ly6g ~5%, Csf1r 23%, Cd68 18%)가 논문이
# 말하는 "S100A8+ macrophage"에 해당하는 단핵구-유래 염증성 골수계 세포이고, 클러스터 23
# (S100a8/9 100%, Ly6g 88%, Camp/Ltf/Ngp/Mpo 모두 양성)은 완전히 별개인 성숙 호중구다.
# 이 둘을 구분하지 않으면 핵심 population이 호중구에 오염된다.

source("scripts/00_setup.R")

merged = readRDS(file.path(results_dir, "scrna_clustered_unannotated.rds"))

# cluster -> cell_type 매핑. 근거: 02 단계 FindAllMarkers top5 (results/02_cluster_top5_markers.csv)
# + S100a8/S100a9/Adgre1/Csf1r/Clec4f/Ly6g/Trem2/Gpnmb/Cd68/Lyz2/Mpo/Camp/Ltf/Ngp 클러스터별 발현.
cluster_to_celltype = c(
  "0"  = "Hepatocyte",              # Sds, Etnppl, Serpina1e, Hal (periportal)
  "1"  = "Endothelial",             # Lyve1, Mmrn2, Cldn5 (LSEC)
  "2"  = "Hepatocyte",              # Acaa1b, Rgn, Fitm1 (pericentral)
  "3"  = "B_cell",                  # Pax5, Ebf1, Cd79a, Ms4a1
  "4"  = "Endothelial",             # Fabp4, Cyyr1 (capillarized LSEC)
  "5"  = "Macrophage_Kupffer",      # Gpnmb, Trem2, Cx3cr1 (lipid-associated macrophage, S100a8/9 낮음)
  "6"  = "Hepatocyte",              # Mup17, Cyp2c37/29, Lect2
  "7"  = "T_cell",                  # Lef1, Tcf7, Il7r (naive)
  "8"  = "Exclude_lowQC",           # Gm42418/mt-Nd2/mt-Atp6 (ambient/저품질)
  "9"  = "T_cell",                  # Tcrg-C2, Trgv2 (gamma-delta)
  "10" = "Macrophage_Kupffer",      # Vsig4, Clec4f, Folr2 (resident Kupffer, S100a8/9 낮음)
  "11" = "Macrophage_Kupffer",      # Ace, Krt80, Csf1r 97%/Cd68 83% (S100a8/9 낮음)
  "12" = "S100A8hi_macrophage",     # Il1f9/Acod1/Il1r2 + S100a8 94%/S100a9 94%, Ly6g 5% -> 핵심 population
  "13" = "Dendritic_cell",          # Xcr1 (cDC1)
  "14" = "Dendritic_cell",          # Cd209a, Flt3 (cDC2)
  "15" = "Dendritic_cell",          # Siglech (pDC)
  "16" = "Cholangiocyte",           # Nipal2, Dab1, epithelial
  "17" = "NK_cell",                 # Ncr1, Klra4/9
  "18" = "Macrophage_Kupffer",      # Clec4f 100%, Adgre1 95% (core resident Kupffer, S100a8/9 낮음)
  "19" = "T_cell",                  # Gzmk, Pdcd1, Cd8a (CD8 activated)
  "20" = "Hepatocyte",              # Apob, F2, Mug1 (acute phase)
  "21" = "Stellate_Fibroblast",     # Rspo3, Wnt9b, Bmp4
  "22" = "Exclude_ambiguous",       # Pbk/Cdkn3/Cdc20/Ccnb1 (cell-cycle only, lineage 불명확)
  "23" = "Neutrophil",              # Ly6g 88%, Camp/Ltf/Ngp/Mpo -- S100A8hi_macrophage와 별개
  "24" = "Endothelial",             # Vwf, Gja5 (large vessel)
  "25" = "B_cell",                  # Vpreb3, Fcrl1, Siglecg
  "26" = "Stellate_Fibroblast",     # Col6a1
  "27" = "Mast_cell"                # Fcer1a, Ms4a2, Cpa3
)

merged$cell_type = unname(cluster_to_celltype[as.character(merged$seurat_clusters)])

n_excluded = sum(startsWith(merged$cell_type, "Exclude"))
message(sprintf("전체 %d개 세포 중 %d개(%.1f%%) 저품질/모호 클러스터로 제외",
                 ncol(merged), n_excluded, 100 * n_excluded / ncol(merged)))

annotated = subset(merged, subset = !cell_type %in% c("Exclude_lowQC", "Exclude_ambiguous"))
annotated$cell_type = factor(annotated$cell_type)

p_umap_celltype = DimPlot(annotated, group.by = "cell_type", label = TRUE, repel = TRUE) +
  ggtitle("Annotated cell types")
ggsave(file.path(fig_dir, "03_umap_celltype.png"), p_umap_celltype, width = 8, height = 6, dpi = 300)

# S100A8hi_macrophage가 호중구/다른 대식세포와 실제로 분리되는지 확인하는 검증용 dotplot
confirm_genes = c("S100a8", "S100a9", "Ly6g", "Camp", "Ltf", "Ngp", "Csf1r", "Adgre1", "Clec4f", "Cd68", "Trem2", "Gpnmb")
confirm_clusters = c("Neutrophil", "S100A8hi_macrophage", "Macrophage_Kupffer")
p_confirm = DotPlot(
  subset(annotated, subset = cell_type %in% confirm_clusters),
  features = intersect(confirm_genes, rownames(annotated)),
  group.by = "cell_type"
) + RotatedAxis() + ggtitle("Neutrophil vs S100A8hi_macrophage vs other Macrophage_Kupffer")
ggsave(file.path(fig_dir, "03_confirm_s100a8_identity.png"), p_confirm, width = 9, height = 4, dpi = 300)

cell_type_counts = table(annotated$cell_type, annotated$genotype)
write.csv(as.data.frame.matrix(cell_type_counts), file.path(results_dir, "03_celltype_counts_by_genotype.csv"))
print(cell_type_counts)

saveRDS(annotated, file.path(results_dir, "scrna_annotated.rds"))
