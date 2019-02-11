# Tip: use RStudio's document outline for navigating this file

# Import ----
# contains commonly used functions and libraries
source("utils_custom.R")

# Load Cleaned Data ----
# see the cleaning directory for details of how this data was cleaned
load("dt_sameStep.RData")
load("dt_sameWindow.RData")

window_change <- dt_sameStep[, mean(RHR_median, na.rm = TRUE), by = window_size]

png(filename = "window_change.png", width = 8, height = 4, units = "in", res = 500)
plot(window_change$window_size, window_change$V1, 
     xlab = "Time Window Size",
     ylab = "Estimated RHR (bpm)")
dev.off()

step_changes <- dt_sameWindow[, mean(RHR_median, na.rm = TRUE), by = steps_threshold]

png(filename = "step_change.png", width = 8, height = 4, units = "in", res = 500)
plot(step_changes$steps_threshold, step_changes$V1, 
     xlab = "Number of Steps",
     ylab = "Estimated RHR (bpm)")
dev.off()

