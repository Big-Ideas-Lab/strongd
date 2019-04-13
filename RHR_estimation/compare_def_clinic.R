# Tip: use RStudio's document outline for navigating this file

# Import ----
# contains commonly used functions and libraries
source("utils_custom.R")

# Load Cleaned Data ----
# see the cleaning directory for details of how this data was cleaned
load("cleaning/RData_clean/dt_hr_clinical.RData")
load("plots_metrics_list_dev.RData")
load("cleaning/RData_clean/dt_hr_filtered.RData")

# Get clinical mean RHR ----
common_ids <- unique(dt_hr_clinical$Id) %>% intersect(unique(dt_hr$Id))
dt_hr_clinical <- dt_hr_clinical[Id %in% common_ids]
dt_hr <- dt_hr[Id %in% common_ids]

# select rows with lying/sitting/standing HR measurements
dt_hr_clinical <- dt_hr_clinical[!is.na(HR_perMin_lying) | !is.na(HR_perMin_sitting) | !is.na(HR_perMin_standing)]
dt_hr_clinical[, mean_RHR := rowMeans(dt_hr_clinical[, 3:5], na.rm = TRUE)]

# select clinical mean that has date closest to the start date of the sampled fitbit HR measurements
# exclude clinic participants that don't have corresponding HR measurements
dt_list <- list()
for (id in common_ids) {
  start_date <- dt_hr[Id == id]$Time %>% as.Date() %>% min()
  min_diff <- Inf
  best_row <- NA
  for (i in 1:nrow(dt_hr_clinical[Id == id])) {
    if(((start_date - dt_hr_clinical[Id == id][i]$Date) %>% as.numeric() %>% abs()) < min_diff) {
      best_row <- dt_hr_clinical[Id == id][i]
    }
  }
  dt_list <- c(dt_list, list(best_row))
}
# concatenate
dt_hr_clinical_closest <- rbindlist(dt_list)
# save(dt_hr_clinical_closest, file = "dt_hr_clinical_closest.RData")

# Compare clinical mean RHR with model output RHR ----
dt_metrics <- plots_metrics_list$dt_metrics
dt_metrics <- dt_metrics[Id %in% common_ids]

setkey(dt_metrics, Id)
setkey(dt_hr_clinical_closest, Id)
setkey(dt_hr, Id)

fit <- lm(formula = dt_hr_clinical_closest$mean_RHR ~ dt_metrics$RHR_median)
summary(fit)

png(filename = "est_vs_clinical_rhr.png", width = 8, height = 4, units = "in", res = 500)
plot(dt_metrics$RHR_median, 
     dt_hr_clinical_closest$mean_RHR,
     xlab = "Estimated RHR (bpm)",
     ylab = "Clinical RHR (bpm)")
abline(fit)
abline(a = 0, b = 1, lty = "dashed")
legend("topleft", legend=c("Fitted Line", "Target Line"), lty=c("solid", "dashed"))
dev.off()

plot(fit)

# medians_step_window ----
png(filename = "medians_step_window.png", width = 12, height = 4, units = "in", res = 500)
layout(matrix(1:2, ncol = 1))
par(mar = c(0,5,2,5), cex.axis = 0.7, cex.lab = 0.7)
plot(1:nrow(dt_metrics), dt_metrics$RHR_median, 
     col = "blue", pch = 15, 
     ylim = c(min(c(dt_metrics$RHR_median, dt_metrics$notRHR_median)), max(c(dt_metrics$RHR_median, dt_metrics$notRHR_median)) + 10),
     xaxt='n',
     xlab = "Participant",
     ylab = "Heart Rate (bpm)")
points(1:nrow(dt_metrics), dt_hr[, median(Value), by = Id]$V1, pch = 1)
points(1:nrow(dt_metrics), dt_metrics$notRHR_median, col = "red", pch = 2)
#legend("bottomleft", legend=c("Est. RHR", "Est. non-RHR", "All HR median"), pch=c(0, 1, 2), pt.cex = 1, cex = 0.6)

par(mar = c(5, 5, 0, 5), cex.axis = 0.7, cex.lab = 0.7)
plot(1:nrow(dt_metrics), dt_metrics$steps_threshold, pch=20,
     xaxt='n',
     xlab = "Participant",
     ylab = "Num. Steps (dots)")
par(new = T)
plot(1:nrow(dt_metrics), dt_metrics$window_size, pch=4, axes=F, xlab=NA, ylab=NA, cex=1)
axis(side = 4)
mtext(side = 4, line = 3, "Time Window (crosses)", cex = 0.7, adj = 1)
dev.off()

# archived: medians_step_window ----
png(filename = "medians.png", width = 12, height = 4, units = "in", res = 500)
plot(1:nrow(dt_metrics), dt_metrics$RHR_median, 
     col = "blue", pch = 15, 
     ylim = c(min(c(dt_metrics$RHR_median, dt_metrics$notRHR_median)), max(c(dt_metrics$RHR_median, dt_metrics$notRHR_median)) + 10),
     xaxt='n',
     xlab = "Participant",
     ylab = "Heart Rate (bpm)")
points(1:nrow(dt_metrics), dt_hr[, median(Value), by = Id]$V1, pch = 1)
points(1:nrow(dt_metrics), dt_metrics$notRHR_median, col = "red", pch = 2)
dev.off()
# legend("bottomleft", legend=c("Est. RHR", "Est. non-RHR", "All HR median"), pch=c(0, 1, 2), pt.cex = 1, cex = 0.6)
# participants with only 1 resting or non-resting median have both medians overlayed

#png(filename = "step_window.png", width = 12, height = 4, units = "in", res = 500)
par(mar = c(5,5,2,5))
plot(1:nrow(dt_metrics), dt_metrics$steps_threshold, pch=1,
     xlab = "Participant",
     ylab = "Number of Steps")
par(new = T)
plot(1:nrow(dt_metrics), dt_metrics$window_size, pch=4, axes=F, xlab=NA, ylab=NA, cex=1)
axis(side = 4)
mtext(side = 4, line = 3, "Time Window Size (min)")
#dev.off()

# archived: range plots ----
RHR_min <- min(c(dt_metrics$RHR_min, dt_metrics$notRHR_min))
RHR_max <- max(c(dt_metrics$RHR_max, dt_metrics$notRHR_max))

png(filename = "RHR_range.png", width = 8, height = 4, units = "in", res = 500)
plot(1:nrow(dt_metrics), dt_metrics$RHR_median,
     ylim = c(RHR_min, RHR_max),
     pch = 19, 
     xaxt='n',
     xlab = "Participant",
     ylab = "Heart Rate (bpm)")
segments(x0 = 1:nrow(dt_metrics),
         y0 = dt_metrics$RHR_min,
         x1 = 1:nrow(dt_metrics),
         y1 = dt_metrics$RHR_max)
# text(x = 1:nrow(dt_metrics), y = dt_metrics$RHR_median, label = dt_metrics$RHR_size, pos = 3)
dev.off()

png(filename = "notRHR_range.png", width = 8, height = 4, units = "in", res = 500)
plot(1:nrow(dt_metrics), dt_metrics$notRHR_median,
     ylim = c(RHR_min, RHR_max),
     pch = 19, 
     xaxt='n',
     xlab = "Participant",
     ylab = "Heart Rate (bpm)")
segments(x0 = 1:nrow(dt_metrics),
         y0 = dt_metrics$notRHR_min,
         x1 = 1:nrow(dt_metrics),
         y1 = dt_metrics$notRHR_max)
dev.off()
