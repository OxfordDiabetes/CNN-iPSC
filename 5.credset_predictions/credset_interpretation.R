###   Quick Description   ###
# After compute_credible to preprocess the tables, this script can be used to
# Determine the distribution of results 

library(dplyr)
library(tidyr)
library(fitdistrplus)
library(logspline)
library(LambertW)
library(ggplot2)
library(reshape2)
library(qvalue)
library(ape)
library(cluster) 
library(ggdendro)
library(dendextend)
library(psych)
library(gplots)
library(RColorBrewer)
library(grid)
library(pheatmap)


setwd("~/Oxford 2.0/Scripts/CNN_project/Data/better_predictions/")

cred_set_results <- read.table("credible_set_pred.txt")
name_var_seq <- read.table("unique_all_name_seq.csv", header = TRUE, sep = ",")
name_to_loc <- read.table("HRC_credset.snp_ann.txt")
mature_table <- read.table("CNN_res.short.190919.txt")


# Calculate the differences for each variant and each stage by subtracting alternating rows
# The first row (ref) is subtracted froom the second row. This way the diff_value increases  
# if the variant increases chromatin openness.
diff <-
  cred_set_results[seq(2, nrow(cred_set_results), 2), ] - cred_set_results[seq(1, nrow(cred_set_results), 2), ]

# Get the .fasta-files in str-format
name_var_seq$sequences <- as.character(name_var_seq$sequences)

# Boxplot to compare stages
# First put the stages in chronological order
diff_order <- diff
colnames(diff_order) <-
  c("BLC", "DE", "EN", "EP", "GT", "PE", "PF", "iPSC")
diff_order <-
  diff_order[, c("iPSC", "DE", "GT", "PF", "PE", "EP", "EN", "BLC")]

#sapply(diff_order, sd, na.rm = TRUE)
meltDiff <- melt(diff_order)

p <- ggplot(meltDiff, aes(factor(variable), value, fill=variable)) +
  labs(title="Boxplot of Predicted Stage differences",x="Stage", y = "Predicted Difference")
p + geom_boxplot() + scale_fill_brewer(palette="RdBu") + theme_minimal()

dp <- ggplot(meltDiff, aes(variable, value, fill = variable)) + 
  geom_violin(trim=FALSE)+
  labs(title="Plot of Predicted differences per stage",x="Stage", y = "Predicted difference") +
  theme(text = element_text(size = 30),
        axis.title.x = element_text(size = 24),
        axis.title.y = element_text(size = 24)
        )
dp + scale_fill_brewer(palette="RdBu") + theme_minimal(base_size = 14)

#Now that you have the graph see if sign different
#non-parametric so kw test
kruskal.test(value ~ variable, data = meltDiff)
#Kruskal-Wallis rank sum test
#Kruskal-Wallis chi-squared = 189.36, df = 8, p-value < 2.2e-16
####Significantly different variance!###

### DO NOT NORMALIZE DATA ###


#New p-values. Don't normalize the data
z_score_final <- as.data.frame(scale(diff_order))
average_diff <- colMeans(diff_order)
p_val_final <- sapply(z_score_final, function(z){pvalue2sided=2*pnorm(-abs(z))})
qfinal <- qvalue(p = p_val_final)
hist(qfinal)


summary(qfinal)

# Summary results
#Call:
#  qvalue(p = p_val_final)
#
#pi0:	1	
#
#Cumulative number of significant calls:
#  
#  <1e-04 <0.001 <0.01 <0.025 <0.05  <0.1     <1
#p-value    11219  15451 24134  30414 37425 47887 878232
#q-value     6641   8517 11603  13394 15096 17378 878232
#local FDR   5265   6581  8565   9790 10886 12097  20619

qvalue_final <- qfinal$qvalues
lfdr <- qfinal$lfdr
hist(lfdr)
plot(qfinal)


### Merging ###

#To compare diffs to position PPA, merge dataframes
# Remove ">" sign between nucleotides in name_to_loc rsids
name_to_loc$V1 <- gsub(">", "", name_to_loc$V1)
# Same removal for mature_table
mature_table$variant <- gsub(">", "", mature_table$variant)
#Tailor name_to_loc
name_to_loc2 <- name_to_loc[, -3]
colnames(name_to_loc2) <- c("name_only", "gen_loc")

#Add names and locations to diff
diff_name <- diff_order
diff_name$name <- name_var_seq$name_only[seq(1,nrow(name_var_seq),2)]
diff_name <- diff_name[ , c(9,1,2,3,4,5,6,7,8)]
loc_diff <- merge(diff_name, name_to_loc2, by.x = "name", by.y = "name_only")
loc_diff <- loc_diff[, c(10,1:9)]

### Largest table ###
diff_name_qval <- data.frame(diff_name, qvalue_final)
diff_name_qval$al_ref <- substring(name_var_seq$sequences, 500, 500)[seq(1,nrow(name_var_seq),2)]
diff_name_qval$al_alt <- substring(name_var_seq$sequences, 500, 500)[seq(2,nrow(name_var_seq),2)]
largest_full <- merge(diff_name_qval, name_to_loc2, by.x = "name", by.y = "name_only")
largest_noPPA <- merge(largest_full, mature_table[,c("variant", "lowest_Q")], by.x = "name", by.y = "variant")
# Clean the table up
largest_noPPA <- largest_noPPA[ ,c(1,18:21,2:17)]
colnames(largest_noPPA)[1] <- "rsID"
colnames(largest_noPPA)[5] <- "mature_islet_Q"
colnames(largest_noPPA)[6:13] <- paste(colnames(largest_noPPA)[6:13], "_diff")
colnames(largest_noPPA)[14:21] <- gsub(".1", "_q", colnames(largest_noPPA)[14:21])
write.table(largest_noPPA, file = "final_CNN_pred.txt", sep = "\t")

### Warning! optional branch ahead ###
#To keep whole names, do this:
full_loc_diff <- merge(diff_name, name_to_loc, by.x = "name", by.y = "V1")
full_loc_diff <- full_loc_diff[, c(10,11,1:9)]

### End of optional branch

### End of first merge ###

###Key next step: importing PPAg ###
# This script makes a single df: "dataset"
# As well as an R object: "cred" (list of dfs)
# They contain the same credible set signals

setwd("per_locus_credsets/")

file_list <- list.files(pattern = ".txt$")
cred = list()

for (file in file_list){
  # Making the named list of df's, cred
  name = gsub("credible_set_Eur_","",gsub(".txt","",file))
  df = read.table(file,header=T,sep="\t")
  cred[[name]] = df
  print(file)
  
  # Making the single df: "dataset"
  # if the merged dataset does exist, append to it
  if (exists("dataset")){
    temp_dataset <-read.table(file, header=TRUE, sep="\t")
    dataset<-rbind(dataset, temp_dataset)
    rm(temp_dataset)
  }
  
  # if the merged dataset doesn't exist, create it
  if (!exists("dataset")){
    dataset <- read.table(file, header=TRUE, sep="\t")
  }
}

# Get unique locations to find q-values
largest_unique <- largest_noPPA[!duplicated(largest_noPPA$gen_loc),]

# Append q-values to an R object that contains credible sets for each signal
for (sign in 1:length(cred)) {
  for (var in 1:nrow(cred[[sign]])) {
    position=paste0(cred[[sign]][var,]$Chr,":", cred[[sign]][var,]$Pos)
    if (position %in% largest_unique$gen_loc) {
      cred[[sign]][var,5:12] <- subset(largest_unique, gen_loc == position, 14:21)
    }
  }
}

#Save cred, an R object: A list containing df's for each credible set
saveRDS(cred, file = "cred_sets.rds", version = 2)

# Mind you, there are more unique locations than rsID's/variants/q-values
# 126013 unique locations vs. 109779 unique rsID rows


setwd("~/Oxford 2.0/Scripts/CNN_project/Data/better_predictions/")
per_locus_credset <- dataset
per_locus_credset$full_loc <- paste(per_locus_credset$Chr, per_locus_credset$Pos, sep=":")

#Merge PPA with diff
loc_PPA_diff <- merge(per_locus_credset, loc_diff, by.x = "full_loc", by.y = "gen_loc")

#### Experiments ####
# How many unique locations are there out of 126,013 per locus PPA rows? Ans: 109400
length(unique(per_locus_credset$full_loc))
# Do all rsid's that have an associated location occur in the PPA loci dataset? Ans: Yes, 109,779.
dim(subset(name_to_loc, V2 %in% per_locus_credset$full_loc))
# Do all locations with an associated PPA occur in the rsid to location dataset? Ans: NO, 125,884 of 126,013.
dim(subset(per_locus_credset, full_loc %in% name_to_loc$V2))
#### End of Experiments ####



#Merge PPA with full_diff
colnames(full_loc_diff)[1:2] <- c("loc","nickname")
full_PPA_diff <- merge(per_locus_credset, full_loc_diff, by.x = "full_loc", by.y = "loc")

# Make a similar full_PPA_diff, but only with highest PPA
unique_rsid_PPA_diff <- full_PPA_diff %>% group_by(name) %>% top_n(1, PPAg )
#
#Get unique ones, remove extra cols and Select PPa threshold 
slim_PPA_diff <- subset(full_PPA_diff, select = -c(full_loc, Chr, Pos))
full_PPA_select <- full_PPA_diff[full_PPA_diff$PPAg > 0.1, ]
unique_rsid_PPA_select <- unique_rsid_PPA_diff[unique_rsid_PPA_diff$PPAg >= 0.1, ]

###End optional branch ###


#Select PPa >0.1
loc_PPA_select <- loc_PPA_diff[loc_PPA_diff$PPAg >= 0.1, ]

#Select rows with names and pred. diff. containing qvalue < 0.05
fdrselect_diffname <- diff_name[apply(qvalue_final[, ], MARGIN = 1, function(x) any(x <= 0.05)), ]
qvalue_final_df <- as.data.frame(qvalue_final)
qvalue_name <- qvalue_final_df
qvalue_name$rsid <- diff_name$name
qvalue_name <- qvalue_name[ , c(9,1,2,3,4,5,6,7,8)]

#### Select predicted differences, based on qvalue signigicance ####
fdrselect_iPSC <- diff_name[qvalue_final_df$iPSC <= 0.05, ]
fdrselect_iPSC_PPA <- merge(fdrselect_iPSC, full_PPA_diff, by.x = "name", by.y = "name", all.x = TRUE)
fdrselect_DE <- diff_name[qvalue_final_df$DE <= 0.05, ]
fdrselect_GT <- diff_name[qvalue_final_df$GT <= 0.05, ]
fdrselect_PF <- diff_name[qvalue_final_df$PF <= 0.05, ]
fdrselect_PE <- diff_name[qvalue_final_df$PE <= 0.05, ]
fdrselect_EP <- diff_name[qvalue_final_df$EP <= 0.05, ]
fdrselect_EN <- diff_name[qvalue_final_df$EN <= 0.05, ]
fdrselect_BLC <- diff_name[qvalue_final_df$BLC <= 0.05, ]

###################################################################

#### Count how many of the significant predicted differences are shared across stages ####

# Prepare empty df with cols for siginifcant difference occurrence
stacked_df <- data.frame(matrix(ncol=2, nrow =0))
colnames(stacked_df) <- c("Single stage", "Shared")

# Loop through the stages in the qvalue dataframe and count how many significant
# differences are unique to each stage
for (i in colnames(qvalue_final_df)) {
  qvalselect <- qvalue_final_df[qvalue_final_df[[i]] <= 0.05, ]
  num <- apply(qvalselect <= 0.05, 1,  sum, na.rm= TRUE)
  single_counts <- sum(num == 1)
  total <- length(num)
  multiple_counts <- total - single_counts
  # Append unique and shared to the df
  stacked_df[i,] <- cbind(single_counts, multiple_counts)
}

# Alter the df format to prepare for plotting
stacked_df$stage <- row.names(stacked_df)
stacked_test <- melt(stacked_df, key = "occurrence", value = "number")
stacked_test$stage <- factor(stacked_test$stage)
stacked_test$stage <- ordered(stacked_test$stage, levels = c("iPSC", "DE", "GT", "PF", "PE", "EP", "EN", "BLC"))

# Plot the results in a stacked barplot
ggplot(stacked_test, aes(fill=variable, y=value, x=stage)) + 
  geom_bar(position="stack", stat="identity") +
  ggtitle("Occurrence of significant predicted differences") +
  scale_color_brewer(palette="Dark2") +
  theme_minimal() +
  xlab("stage") +
  ylab("Number of significant predicted differences")

#############################################################################

#### How many loci have at least one significant predicted difference? ####

# How many loci are there? Ans: 380
length(unique(per_locus_credset$IndexSNP))
# How many rsid's have at least one significant predicted difference? Ans: 7468
nrow(fdrselect_diffname )
# How many rows of the full_PPA_diff remain if you select these rsid's? Ans: 8638
full_sign <- subset(full_PPA_diff, name %in% fdrselect_diffname$name)
# How many of the 380 Index SNPS harbour at least on significant predicted diff variant? Ans: 301
length(unique(full_sign$IndexSNP))


#Now, from the selected fdr, subset the PPa > 0.1 from loc_PPA_select. fdrselect_nn contains nicknames and variant names
fdrselect_PPA_diffname <- subset(fdrselect_diffname, name %in% loc_PPA_select$name)
fdrselect_nn <- subset(full_loc_diff, name %in% fdrselect_PPA_diffname$name)
# To get pheatmap stars, look up in qvalue
qvalselect_nn <- subset(qvalue_name, rsid  %in% fdrselect_nn$name)
rownames(qvalselect_nn) <- qvalselect_nn$rsid
qvalselect_nn <- within(qvalselect_nn, rm(rsid))

fdrselect_nn$total_name <- paste(fdrselect_nn$name, fdrselect_nn$nickname, sep = "  ")
fdrselect_nn <- fdrselect_nn[, -c(1:3)]
rownames(fdrselect_nn) <- fdrselect_nn$total_name
fdrselect_nn <- within(fdrselect_nn, rm(total_name))

# To get pheatmap stars, look up in qvalue


# Significant variants for each stage #
iPSC_final_select <-
  subset(fdrselect_iPSC, name %in% loc_PPA_select$name)
DE_final_select <-
  subset(fdrselect_DE, name %in% loc_PPA_select$name)
GT_final_select <-
  subset(fdrselect_GT, name %in% loc_PPA_select$name)
PF_final_select <-
  subset(fdrselect_PF, name %in% loc_PPA_select$name)
PE_final_select <-
  subset(fdrselect_PE, name %in% loc_PPA_select$name)
EP_final_select <-
  subset(fdrselect_EP, name %in% loc_PPA_select$name)
EN_final_select <-
  subset(fdrselect_EN, name %in% loc_PPA_select$name)
BLC_final_select <-
  subset(fdrselect_BLC, name %in% loc_PPA_select$name)
# End of significant variants for each stage #

#Redo heatmap with dendrogram with the following traits:
#Use fdrselect_diffname, because PPA > 0.1 and q-value < 0.05 gives 44 variants
#Add q-value asterisks
#SNP_ID + variant ID as label

fdr_nn_matrix <- data.matrix(fdrselect_nn)

fdr_nn_matrix <- 
heatmap.2(
  fdr_nn_matrix,
  col = bluered,
  dendrogram = "row",
  Colv = NA,
  key = T,
  cexRow = 0.6,
  margins = c(4, 13)
)
pheatmap::pheatmap(fdrselect_nn, color = colorRampPalette(rev(brewer.pal(
  n = 8, name =
    "RdBu"
)))(20), cluster_cols = FALSE)


# Thresholds for predictions
min = -0.2
max = 0.2
thresh_nn <- fdrselect_nn
thresh_nn[,][thresh_nn[,] < min] <- min
thresh_nn[,][thresh_nn[,] > max] <- max

my_pheatmap <- pheatmap::pheatmap(thresh_nn, color = colorRampPalette(rev(brewer.pal(
  n = 10, name =
    "RdBu"
)))(16), cluster_cols = FALSE)

#get the order of this new pheatmap to get the qvalue order right
pheatname_order <- my_pheatmap$tree_row$labels[my_pheatmap$tree_row$order]
pheatrsid_order <- sapply(strsplit(pheatname_order, "  "), `[[`, 1)
thresh_nn_order <- row.names(thresh_nn)
thresh_nn_order <- sapply(strsplit(thresh_nn_order, "  "), `[[`, 1)

qvalselect_nn <- qvalselect_nn[c(thresh_nn_order),]

#After creating an empty matrix for the stars, fill in with stars based on qvalue
qval_sign_matrix <- matrix(data = " ", nrow = dim(qvalselect_nn)[1], ncol = dim(qvalselect_nn)[2])
for (i in 1:nrow(qvalselect_nn)){
  for (j in 1:ncol(qvalselect_nn)){
    qval_sign_matrix[i,j][(qvalselect_nn[i,j] <= 0.05 )] <- "*"
    
  }
}
qval_sign_matrix

# Store the "pretty heatmap" that we'll use from now on (this one has stars for significance)
p <- pheatmap::pheatmap(thresh_nn, color = colorRampPalette(rev(brewer.pal(
  n = 10, name =
    "RdBu"
)))(16), cluster_cols = FALSE, display_numbers = qval_sign_matrix)

# The "pheatmap" object is stored as a list of lists, containing information about the heatmap
# (obviously), and it's properties. To get the rownames as ordered in the heatmap after clustering:
final_pheatmap_order <- p$tree_row$labels[p$tree_row$order]
write.table(final_pheatmap_order, file = "final_pheatmap_row_order.txt")

# Write some tables:
write.table(loc_PPA_diff, file = "loc_PPA_diff.txt", quote = FALSE, sep = "\t")
write.table(full_PPA_diff, file = "full_PPA_diff.txt", quote = FALSE, sep = "\t")
write.table(qvalue_name, file = "qvalue_name.txt", quote = FALSE, sep = "\t")

#Select PROX1 variants of interest and other one and plot:
prox_selected <- full_PPA_diff[full_PPA_diff$nickname == "PROX1_rs79687284_Known_2", ]
prox_selected <- prox_selected[,-c(1:3)]
prox_selected.m <- melt(prox_selected)

p<-ggplot(prox_selected.m, aes(x=variable, y=value, group=name, linetype=name)) +
  geom_line(aes(color=name), size =1.2)+
  geom_point(aes(color=name), size =3) +
  ylim(-0.6,0.4)
p <- p + scale_color_brewer(palette="Paired")+
  labs(title="PROX1 variants throughout development",x="Stage", y = "Predicted Difference") +
  theme_minimal(base_size = 22)
p + theme(legend.position="top")

#Select ADCY5 variants of interest and other one and plot:
adcy5_selected <- full_PPA_diff[full_PPA_diff$nickname == "ADCY5_rs11708067_Known_1", ]
adcy5_selected <- adcy5_selected[adcy5_selected$PPAg > 0.1 ,]
adcy5_selected <- adcy5_selected[,-c(1:3)]
adcy5_selected.m <- melt(adcy5_selected)

p<-ggplot(adcy5_selected.m, aes(x=variable, y=value, group=name, linetype=name)) +
  geom_line(aes(color=name), size =1.2)+
  geom_point(aes(color=name), size =3) +
  ylim(-0.4,0.4)
p <- p + scale_color_brewer(palette="Paired")+
  labs(title="ADCY5 variants throughout development",x="Stage", y = "Predicted Difference") +
  theme_minimal(base_size = 22)
p + theme(legend.position="top")


#Select HNF1A variants of interest and other one and plot:
hnf1a_selected <- full_PPA_diff[full_PPA_diff$nickname == "HNF1A_rs56348580_Known_1", ]
hnf1a_selected <- hnf1a_selected[hnf1a_selected$PPAg > 0.1 ,]
hnf1a_selected <- hnf1a_selected[,-c(1:3)]
hnf1a_selected.m <- melt(hnf1a_selected)

p<-ggplot(hnf1a_selected.m, aes(x=variable, y=value, group=name, linetype=name)) +
  geom_line(aes(color=name), size =1.2)+
  geom_point(aes(color=name), size =3) +
  ylim(-0.4,0.4)
p <- p + scale_color_brewer(palette="Paired")+
  labs(title="HNF1A variants throughout development",x="Stage", y = "Predicted Difference") +
  theme_minimal(base_size = 22)
p + theme(legend.position="top")

#Select PPARG variants of interest and other one and plot:
pparg_selected <- full_PPA_diff[full_PPA_diff$nickname == "PPARG_rs17819328_Known_2", ]
pparg_selected <- pparg_selected[pparg_selected$PPAg > 0.1 ,]
pparg_selected <- pparg_selected[,-c(1:3)]
pparg_selected.m <- melt(pparg_selected)

p<-ggplot(pparg_selected.m, aes(x=variable, y=value, group=name, linetype=name)) +
  geom_line(aes(color=name), size =1.2)+
  geom_point(aes(color=name), size =3) +
  ylim(-0.4,0.4)
p <- p + scale_color_brewer(palette="Paired")+
  labs(title="PPARG variants throughout development",x="Stage", y = "Predicted Difference") +
  theme_minimal(base_size = 22)
p + theme(legend.position="top")


#####################   Not necessary   ###########################
#Hclust locus-name and variant name 
fdrselect_nn <- fdrselect_nn[,-c(1,3)]
fdrselect_nn$nickname <-  sapply(strsplit(as.character(fdrselect_nn$nickname), "\\_"), `[`, 1)
fdrselect_nn$nickname <- sub('[.]', '_', make.names(fdrselect_nn$nickname, unique=TRUE))
rownames(fdrselect_nn) <- fdrselect_nn$nickname
fdrselect_nn <- fdrselect_nn[,-1]


#Do hclust based on loci, nicknames can clarify
dist_diff <- dist(fdrselect_nn, method = "euclidean")
hc.cols <- hclust(dist((fdrselect_nn)))
plot(hc.cols, col = "#487AA1", col.main = "Black", main = "Predicted Difference Dendogram", col.lab = "#7C8071", 
     col.axis = "#F38630", lwd = 1, lty = 3, sub = "", axes = FALSE, xlab = "Locus", ylab = "Euclidian Distance", horiz = TRUE)

#Do hclust based on stages, no nicknames needed
dist_diff <- dist(fdrselect_diffname, method = "euclidean")
hc.cols <- hclust(dist(t(fdrselect_diffname)))
plot(hc.cols, col = "#487AA1", col.main = "Black", , main = "Predicted Difference Dendogram", col.lab = "#7C8071", 
     col.axis = "#F38630", lwd = 1, lty = 3, sub = "", axes = FALSE, xlab = "Stage", ylab = "Euclidian Distance")


###############################################################
###                                                         ###
###             End not necessary                           ###
###                                                         ###
###############################################################



setwd("~/Oxford/RealScripts/credible_sets/data")
save.image("~/Oxford/RealScripts/credible_sets/data/ideas_interpretation")

### Make all vs all scatterplots ###
rownames(diff_name) <- diff_name$name
diff_name <- diff_name[,-1]
plot(diff_name)

savehistory()

pairs.panels(diff_name, 
             method = "pearson", # correlation method
             hist.col = "#00AFBB",
             density = TRUE  # show density plots
)

########################################################################
###                                                                  ###
###   Select Monogenic DM Genes:                                     ###
###   GCK, HNF1A, HNF1B, HNF4A, KCNJ11, PPARG, WFS1                  ###
###                                                                  ###
########################################################################

GCK_df <- full_PPA_diff[grep("GCK", full_PPA_diff$nickname),]
HNF1A_df <- full_PPA_diff[grep("HNF1A", full_PPA_diff$nickname),]
HNF1B_df <- full_PPA_diff[grep("HNF1B", full_PPA_diff$nickname),]
HNF4A_df <- full_PPA_diff[grep("HNF4A", full_PPA_diff$nickname),]
KCNJ11_df <- full_PPA_diff[grep("KCNJ11", full_PPA_diff$nickname),]
PPARG_df <- full_PPA_diff[grep("PPARG", full_PPA_diff$nickname),]
WFS1_df <- full_PPA_diff[grep("WFS1", full_PPA_diff$nickname),]

mono_genes <- bind_rows(GCK_df, HNF1A_df,HNF1B_df, HNF4A_df, KCNJ11_df, PPARG_df, WFS1_df)

mono_genes_select <- mono_genes[mono_genes$PPAg > 0.1,]
mono_genes_select2 <- mono_genes[mono_genes$PPAg > 0.01,]


###Important additional stuff###


### Get q-values for predicted differences ###
qvalue_named <- cbind(as.data.frame(diff_name$name), qvalue_final)


###Make histogram of cred_set_results
colnames(cred_set_results) <- c("BLC", "DE","EN","EP","PE","PFG","PGT","iPSC")
cred_set_results <- cred_set_results[,c(8,2,7,6,5,4,3,1)]
cred_set_results2 <- melt(cred_set_results)
g <- ggplot(cred_set_results2,aes(x=value), fill = blue)
g <- g + geom_histogram()
g <- g + facet_wrap(~variable)
g +theme_minimal() 
