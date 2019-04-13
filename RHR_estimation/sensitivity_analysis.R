# Tip: use RStudio's document outline for navigating this file

# Import ----
# contains commonly used functions and libraries
source("utils_custom.R")

# Load Cleaned Data ----
# see the cleaning directory for details of how this data was cleaned
load("dt_sameStep.RData")
load("dt_sameWindow.RData")

window_change <- dt_sameStep[, .(RHR_median_mean = mean(RHR_median, na.rm = TRUE), 
                             RHR_median_sd = sd(RHR_median, na.rm = TRUE)),
                             by = window_size]

png(filename = "window_change_withSD.png", width = 8, height = 4, units = "in", res = 500)
plot(window_change$window_size, window_change$RHR_median_mean, 
     xlab = "Time Window Size",
     ylab = "Estimated RHR (bpm)",
     ylim=c(min(window_change$RHR_median_mean - window_change$RHR_median_sd), max(window_change$RHR_median_mean + window_change$RHR_median_sd)))
arrows(window_change$window_size, 
       window_change$RHR_median_mean - window_change$RHR_median_sd, 
       window_change$window_size, 
       window_change$RHR_median_mean + window_change$RHR_median_sd, 
       length=0.05, angle=90, code=3)
dev.off()

step_change <- dt_sameWindow[, .(RHR_median_mean = mean(RHR_median, na.rm = TRUE), 
                                  RHR_median_sd = sd(RHR_median, na.rm = TRUE)),
                              by = steps_threshold]
png(filename = "step_change_withSD.png", width = 8, height = 4, units = "in", res = 500)
plot(step_change$steps_threshold, step_change$RHR_median_mean, 
     xlab = "Number of Steps",
     ylab = "Estimated RHR (bpm)",
     ylim=c(min(step_change$RHR_median_mean - step_change$RHR_median_sd), max(step_change$RHR_median_mean + step_change$RHR_median_sd)))
arrows(step_change$steps_threshold, 
       step_change$RHR_median_mean - step_change$RHR_median_sd, 
       step_change$steps_threshold, 
       step_change$RHR_median_mean + step_change$RHR_median_sd, 
       length=0.05, angle=90, code=3)
dev.off()

# plot of derivatives

