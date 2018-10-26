library(data.table)
library(magrittr)

# 1st arg: decimal that indicates the ratio of sample size to full size
# 2nd to last arg: csv file names containing data to be sampled
args <- commandArgs(trailingOnly = TRUE)

# set seed to be able to reproduce the same sample
set.seed(1)

ratio <- as.numeric(args[1])
i <- 2
while (i <= length(args)) {
  dt <- fread(args[i])
  dt_sample <- dt[sample(.N, floor(ratio*(.N)))]
  new_filename <- gsub("(.csv)", "", args[i]) %>% paste0("_sample.csv")
  fwrite(dt_sample, new_filename)
  
  i = i + 1
}