# Tip: use RStudio's document outline for navigating this file

# Import ----
# contains commonly used functions and libraries
source("utils_custom.R")

# Load Cleaned Data ----
# see the cleaning directory for details of how this data was cleaned

load("cleaning/RData_clean/dt_steps.RData")
load("cleaning/RData_clean/dt_hr_filtered.RData")
load("cleaning/RData_clean/dt_arm_simple.RData")

# Interpolate per second HR measurement for each per minute step measurement ----

# note that interpolating in the other direction (find per minute step measurement for each per second HR measurement)
# would create duplicate step measurements, making it seem like the participant took more steps

# setup for join on id and then within each unique id value, join on time
dt_hr[, join_time := Time]
dt_steps_perMin[, join_time := ActivityMin]
setkey(dt_hr, Id, join_time)
setkey(dt_steps_perMin, Id, join_time)

# right outer join (include all measurements from dt_steps_perMin), interpolating the temporally closest HR measurement for each steps measurement
# we're interested in HR changes that RESULT FROM previously taken steps
# thus, we roll backward to interpolate the closest HR measurement that occurs AFTER each steps measurement

# limit interpolation to HR measurement that occur at most 1min (60s) after step measurement
join_steps_hr <- dt_hr[dt_steps_perMin, roll = -60] 
dt_steps_hr <- join_steps_hr[, .(Id, ActivityMin, Value, Steps)]
# remove step measurements that do not have an interpolated HR value
dt_steps_hr <- dt_steps_hr[!is.na(Value)]
id_list <- dt_steps_hr$Id %>% unique()

setkey(dt_steps_hr, Id, ActivityMin)

# Outlier Removal ----
# construct a HR boxplot for each participant
# boxplot <- boxplot(Value ~ Id, dt_steps_hr)
# 
# # progress bar
# pb <- txtProgressBar(min = 0, max = length(boxplot$names), style = 3)
# i = 1
# for (group_num in 1:length(boxplot$names)) {
#   id <- boxplot$names[group_num]
#   out <- boxplot$out[boxplot$group == group_num]
#   
#   # want to remove outliers for this participant, i.e. rows where Id == id and Value %in% out
#   # thus, we will keep the complement:
#   dt_steps_hr <- dt_steps_hr[!((Id == id) & (Value %in% out))]
#   
#   setTxtProgressBar(pb, i)
#   i = i + 1
# }
# close(pb)
# 
# save(dt_steps_hr, file = "dt_steps_hr_noBoxplotOutliers.RData")

# Define RHR in terms of num. steps taken within some time window ----

# I will attempt to define RHR in terms of **total number of steps** taken within a **time window** of some length.
# The idea is to find a num. steps and time window combination that is good at separating high HR from low HR (or RHR).
# Specifically, we want to threshold the num. steps taken within a time window such that there is a great "difference" between 
# HR values for num. steps taken **below** this threshold and HR values taken **above** this threshold.

# To measure this "difference" concept (which I will call **sensitivity**), I will use the following method:
# 1. For a time window of size n, find the rolling sum of steps taken within time window.
# 2. For a num. steps threshold m, find a **per participant** summary statistic, e.g. median, for HR values corresponding to entries
# with steps rolling sum <= m; let's call this low_summaryHR. Repeat for entries with steps rolling sum > m; 
# let's call this high_summaryHR.
# 3. For each participant, calculate diff_summaryHR = abs(high_summaryHR - low_summaryHR).
# 4. For each participant, to see how significant diff_summaryHR is **relative to the range of that participant's HR values (rangeHR)**,
# calculate ratio_diff_range = diff_summaryHR/rangeHR.
# 5. Finally, we have a ratio_diff_range measure for each participant. Aggregate these values with a mean function to get an overall 
# measurement of the "difference" concept. Let's call this **sensitivity**.

# Goal: find a time window of size n* and num. steps threshold m* combination that **maximizes sensitivity**. This combination of 
# parameters maximizes the "difference" of HR when comparing HR for entries below the threshold vs entries above the threshold, i.e.
# this combination of parameters is good that separating low from high HR values.

# These lower HR values will be used to **define RHR**:
# I will define RHR as HR values that occur when the total number of steps <= m*
# within a time window of size n*.

gridSearch_diff_window_steps <- function(dt_steps_hr, window_size_list, steps_threshold_list) {
  # this function searches for the largest sensitivity value produced from all combinations of parameters
  # specified by window_size_list and steps_threshold_list.
  
  # initialize table with all possible combinations of the step thresholds and window sizes specified above
  dt_results <- data.table(steps_threshold = rep(steps_threshold_list, each = length(window_size_list)),
                           window_size = window_size_list,  # will be recycled
                           sensitivity = as.numeric(rep(NA, length(steps_threshold_list)*length(window_size_list))))
  
  # range of HR values for each participant
  dt_rangeHR_byId <- dt_steps_hr[, 
                                 .(rangeHR = range(Value, na.rm = TRUE)[2] - range(Value, na.rm = TRUE)[1]), 
                                 by = Id]
  
  num_participants <- length(dt_rangeHR_byId$Id)
  
  # progress bar
  pb <- txtProgressBar(min = 0, max = nrow(dt_results), style = 3)
  i = 1
  for (n in window_size_list) {
    # for each row, keep track of the rolling sum of num. steps within a time window that occurs BEFORE the current row
    # (the table is already sorted by Id and then sorted by ActivityMin within each unique Id value)
    # (the Steps column has no missing values: `dt_steps_hr$Steps %>% is.na() %>% any()`` returns FALSE)
    
    # cleanup
    dt_steps_hr[, rolling_sum_steps := NULL]
    
    dt_steps_hr[, 
                rolling_sum_steps := roll_sum(Steps, n, align = "right", fill = NA),
                by = Id]
    
    for (m in steps_threshold_list) {
      # summary HR where rolling_sum_steps <= steps_threshold for each participant
      dt_low_summaryHR_byId <- dt_steps_hr[rolling_sum_steps <= m,
                                           .(low_summaryHR = median(Value, na.rm = TRUE)),
                                           by = Id]
      
      # summary HR where rolling_sum_steps > steps_threshold for each participant
      dt_high_summaryHR_byId <- dt_steps_hr[rolling_sum_steps > m,
                                            .(high_summaryHR = median(Value, na.rm = TRUE)),
                                            by = Id]
      
      # only consider participants with who have associated values in BOTH the "low" and "high" tables above
      id_list <- intersect(dt_low_summaryHR_byId$Id, dt_high_summaryHR_byId$Id)
      dt_id <- data.table(Id = id_list)
      
      if (nrow(dt_id) >= ceiling(num_participants/2)) {
        # continue only if we can calculate sensitivity for at least half of the participants
        
        dt_low_summaryHR_byId <- dt_low_summaryHR_byId[dt_id, on = "Id"]
        dt_high_summaryHR_byId <- dt_high_summaryHR_byId[dt_id, on = "Id"]
        
        dt_combined <- copy(dt_rangeHR_byId)
        dt_combined <- dt_combined[dt_id, on = "Id"]

        stopifnot(all(dt_low_summaryHR_byId$Id == dt_high_summaryHR_byId$Id) && all(dt_low_summaryHR_byId$Id == dt_combined$Id))
        
        dt_combined[, low_summaryHR := dt_low_summaryHR_byId$low_summaryHR]
        dt_combined[, high_summaryHR := dt_high_summaryHR_byId$high_summaryHR]

        # difference between high_summaryHR (above threshold) and low_summaryHR (below threshold) for each participant
        dt_combined[, diff_summaryHR := high_summaryHR - low_summaryHR]

        # how significant is this difference compared to the range of HR values for each participant?
        # --> find ratio of diff_summaryHR/rangeHR for each participant
        dt_combined[, ratio_diff_range := diff_summaryHR/rangeHR]

        # average over this ratio to find an overall measure for how much this window-threshold combination
        # causes change in HR values between HR values for steps below the threshold and HR values for steps above the threshold
        # let's call this measure "sensitivity"
        sensitivity <- dt_combined[, mean(ratio_diff_range)]
        
        # append to results table
        dt_results[window_size == n & steps_threshold == m]$sensitivity <- sensitivity
      } else {
        dt_results[window_size == n & steps_threshold == m]$sensitivity <- NA
      }
      
      setTxtProgressBar(pb, i)
      i = i + 1
    }
  }
  
  close(pb)
  
  return(dt_results)
}

gridSearch_deviation_window_steps <- function(dt_steps_hr, window_size_list, steps_threshold_list) {
  # initialize table with all possible combinations of the step thresholds and window sizes specified above
  dt_results <- data.table(steps_threshold = rep(steps_threshold_list, each = length(window_size_list)),
                           window_size = window_size_list,  # will be recycled
                           RHR_dev = as.numeric(rep(NA, length(steps_threshold_list)*length(window_size_list))),
                           notRHR_dev = as.numeric(rep(NA, length(steps_threshold_list)*length(window_size_list))),
                           RHR_median = as.numeric(rep(NA, length(steps_threshold_list)*length(window_size_list))),
                           notRHR_median = as.numeric(rep(NA, length(steps_threshold_list)*length(window_size_list)))
                           )
  
  num_participants <- dt_steps_hr$Id %>% unique() %>% length()
  
  # progress bar
  pb <- txtProgressBar(min = 0, max = nrow(dt_results), style = 3)
  i = 1
  for (n in window_size_list) {
    # cleanup
    dt_steps_hr[, rolling_sum_steps := NULL]
    
    dt_steps_hr[, 
                rolling_sum_steps := roll_sum(Steps, n, align = "right", fill = NA),
                by = Id]
    
    # TODO: get rid of multi-id logic
    for (m in steps_threshold_list) {
      # summary HR where rolling_sum_steps <= steps_threshold for each participant
      dt_low_deviationHR_byId <- dt_steps_hr[rolling_sum_steps <= m,
                                           .(low_deviationHR = sd(Value, na.rm = TRUE)),
                                           by = Id]
      
      # summary HR where rolling_sum_steps > steps_threshold for each participant
      dt_high_deviationHR_byId <- dt_steps_hr[rolling_sum_steps > m,
                                            .(high_deviationHR = sd(Value, na.rm = TRUE)),
                                            by = Id]
      
      # only consider participants with who have associated values in BOTH the "low" and "high" tables above
      # id_list <- intersect(dt_low_deviationHR_byId$Id, dt_high_deviationHR_byId$Id)
      # dt_id <- data.table(Id = id_list)
      
      # if (nrow(dt_id) >= ceiling(num_participants/2)) {
      dt_low_deviationHR_byId <- dt_low_deviationHR_byId  #[dt_id, on = "Id"]
      dt_high_deviationHR_byId <- dt_high_deviationHR_byId  #[dt_id, on = "Id"]
      
      if (nrow(dt_low_deviationHR_byId) == 1) {
        dt_results[window_size == n & steps_threshold == m]$RHR_dev <- dt_low_deviationHR_byId$low_deviationHR 
      }
      
      if (nrow(dt_high_deviationHR_byId) == 1) {
        dt_results[window_size == n & steps_threshold == m]$notRHR_dev <- dt_high_deviationHR_byId$high_deviationHR 
      }
      
      dt_low_medianHR <- dt_steps_hr[rolling_sum_steps <= m,
                                     .(low_medianHR = median(Value, na.rm = TRUE)),
                                     by = Id]
      dt_high_medianHR <-  dt_steps_hr[rolling_sum_steps > m,.
                                       (high_medianHR = median(Value, na.rm = TRUE)),
                                       by = Id]
      
      if (nrow(dt_low_medianHR) == 1) {
        dt_results[window_size == n & steps_threshold == m]$RHR_median <- dt_low_medianHR$low_medianHR
      }
      
      if (nrow(dt_high_medianHR) == 1) {
        dt_results[window_size == n & steps_threshold == m]$notRHR_median <- dt_high_medianHR$high_medianHR 
      }
      
      setTxtProgressBar(pb, i)
      i = i + 1
    }
  }
  
  close(pb)
  return(dt_results)
}

# Best window + step threshold combination for each participant ----
# TODO: comparison across arms
gridSearch_savePlot_perId <- function(id_list, gridSearch_func, window_size_list, steps_threshold_list, soft = FALSE, save = FALSE) {
  gridSearch_func_name <- substitute(gridSearch_func) %>% as.character()
  
  plots <- list()
  dt_metrics <- data.table(Id = id_list,
                           penalty = as.numeric(rep(NA, length(id_list))),
                           steps_threshold = as.numeric(rep(NA, length(id_list))),
                           window_size = as.numeric(rep(NA, length(id_list))),
                           RHR_median = as.numeric(rep(NA, length(id_list))),
                           notRHR_median = as.numeric(rep(NA, length(id_list))),
                           RHR_mean = as.numeric(rep(NA, length(id_list))),
                           notRHR_mean = as.numeric(rep(NA, length(id_list))),
                           RHR_size = as.numeric(rep(NA, length(id_list))),
                           notRHR_size = as.numeric(rep(NA, length(id_list))),
                           RHR_max = as.numeric(rep(NA, length(id_list))),
                           notRHR_max = as.numeric(rep(NA, length(id_list))),
                           RHR_min = as.numeric(rep(NA, length(id_list))),
                           notRHR_min = as.numeric(rep(NA, length(id_list)))
  )
  for(i in 1:length(id_list)) {
    id <- id_list[i]
    print(sprintf("Searching for participant with id %s", id))
    
    if (soft == TRUE) {
      softmin <- dt_steps_hr[Id == id]$Value %>% quantile(0.05, na.rm = TRUE)
      softmax <- dt_steps_hr[Id == id]$Value %>% quantile(0.95, na.rm = TRUE)
      
      dt_results <- gridSearch_func(dt_steps_hr[Id == id & Value < softmax & Value > softmin], window_size_list, steps_threshold_list)  
    } else {
      dt_results <- gridSearch_func(dt_steps_hr[Id == id], window_size_list, steps_threshold_list)  
    }
    
    best_index <- dt_results[, 3] %>% unlist() %>% as.numeric() %>% which.min()
    dt_best <- dt_results[best_index]
    print(dt_best)
   
    window_size <- dt_best$window_size
    steps_threshold <- dt_best$steps_threshold
    
    dt_metrics[Id == id]$penalty <- dt_best[, 3]
    dt_metrics[Id == id]$steps_threshold <- steps_threshold
    dt_metrics[Id == id]$window_size <- window_size
    
    dt_steps_hr[, rolling_sum_steps := NULL]
    dt_steps_hr[Id == id, rolling_sum_steps := roll_sum(Steps, window_size, align = "right", fill = NA)]
    
    dt_steps_hr[, isRHR := NULL]
    dt_steps_hr[(Id == id) & (rolling_sum_steps <= steps_threshold),
                isRHR := TRUE]
    dt_steps_hr[(Id == id) & (rolling_sum_steps > steps_threshold),
                isRHR := FALSE]
    
    # median
    dt_metrics[Id == id]$RHR_median <- dt_steps_hr[(Id == id) & isRHR == TRUE & !is.na(Value)]$Value %>% median()
    dt_metrics[Id == id]$notRHR_median <- dt_steps_hr[(Id == id) & isRHR == FALSE & !is.na(Value)]$Value %>% median()
    
    # mean
    dt_metrics[Id == id]$RHR_mean <- dt_steps_hr[(Id == id) & isRHR == TRUE & !is.na(Value)]$Value %>% mean()
    dt_metrics[Id == id]$notRHR_mean <- dt_steps_hr[(Id == id) & isRHR == FALSE & !is.na(Value)]$Value %>% mean()
    
    # size
    dt_metrics[Id == id]$RHR_size <- dt_steps_hr[(Id == id) & isRHR == TRUE & !is.na(Value)]$Value %>% length()
    dt_metrics[Id == id]$notRHR_size <- dt_steps_hr[(Id == id) & isRHR == FALSE & !is.na(Value)]$Value %>% length()
    
    # min
    dt_metrics[Id == id]$RHR_min <- dt_steps_hr[(Id == id) & isRHR == TRUE & !is.na(Value)]$Value %>% min()
    dt_metrics[Id == id]$notRHR_min <- dt_steps_hr[(Id == id) & isRHR == FALSE & !is.na(Value)]$Value %>% min()
    
    # max
    dt_metrics[Id == id]$RHR_max <- dt_steps_hr[(Id == id) & isRHR == TRUE & !is.na(Value)]$Value %>% max()
    dt_metrics[Id == id]$notRHR_max <- dt_steps_hr[(Id == id) & isRHR == FALSE & !is.na(Value)]$Value %>% max()
    
    # plots
    plots[[(i-1)*2 + 1]] <- show_linePerGroup(dt_steps_hr[isRHR == TRUE & Id == id], "ActivityMin", "Value", "Id") +
      scale_color_manual(values = "#66C2A5") +
      ylim(c(20, 220)) +
      theme(plot.title = element_text(hjust = 0.5, size = 9), axis.title = element_text(size = 7)) +
      labs(title = sprintf("%s: estimated RHR, window=%d, steps=%d", id, window_size, steps_threshold),
           x = "Minutes",
           y = "Heart Rate")
    
    if (save == TRUE) {
      sprintf("%s_window=%d_steps=%d_isRHR=TRUE_%s_soft=%s.png", id, window_size, steps_threshold, gridSearch_func_name, as.character(soft)) %>%
        ggsave(path = "./temp_plots/", width = 8, height = 6, units = "in")
    }
    
    plots[[(i-1)*2 + 2]] <- show_linePerGroup(dt_steps_hr[isRHR == FALSE & Id == id], "ActivityMin", "Value", "Id") +
      scale_color_manual(values = "#FC8D62") +
      ylim(c(20, 220)) +
      theme(plot.title = element_text(hjust = 0.5, size = 9), axis.title = element_text(size = 7)) +
      labs(title = sprintf("%s: estimated regular HR: window=%d, steps=%d", id, window_size, steps_threshold),
           x = "Minutes",
           y = "Heart Rate")
    
    if (save == TRUE) {
      sprintf("%s_window=%d_steps=%d_isRHR=FALSE_%s_soft=%s.png", id, window_size, steps_threshold, gridSearch_func_name, as.character(soft)) %>%
        ggsave(path = "./temp_plots/", width = 8, height = 6, units = "in")
    }
  }
  
  return(list("plots" = plots, "dt_metrics" = dt_metrics))
}

# search ----
# sample 3 participants
set.seed(0)
id_sample <- sample(id_list, 3)
# id_sample <- c("0036")

# step threshold search over hundreds
window_size_list <- c(1, 5, 10, 30, 60)  # minutes
steps_threshold_list <- c(0, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000)  # num. steps

plots_metrics_list <- gridSearch_savePlot_perId(id_sample, gridSearch_deviation_window_steps, window_size_list, steps_threshold_list, save = TRUE)

plots <- plots_metrics_list$plots

png(filename = sprintf("%s_dev.png", paste(id_sample, collapse="_")), width = 8, height = 6, units = "in", res = 500)
multiplot(plotlist = plots, layout = matrix(1:(length(id_sample)*2), ncol = 2, byrow=TRUE))
dev.off()

# fine grain search
window_size_list <- seq(1, 120, 1)  # minutes
steps_threshold_list <- seq(0, 1000, 10) # num. steps

plots_metrics_list <- gridSearch_savePlot_perId(id_list, gridSearch_deviation_window_steps, window_size_list, steps_threshold_list, save = TRUE)
save(plots_metrics_list, file = "plots_metrics_list_dev.RData")

plots_metrics_list <- gridSearch_savePlot_perId(id_list, gridSearch_diff_window_steps, window_size_list, steps_threshold_list, save = TRUE)
save(plots_metrics_list, file = "plots_metrics_list_diff.RData")

png(filename = sprintf("%s_diff.png", paste(id_sample, collapse="_")), width = 8, height = 6, units = "in", res = 500)
multiplot(plotlist = plots, layout = matrix(1:(length(id_sample)*2), ncol = 2, byrow=TRUE))
dev.off()

id <- "0119"
steps_threshold <- 0
window_size <- 60

dt_steps_hr[, rolling_sum_steps := NULL]
dt_steps_hr[Id == id, rolling_sum_steps := roll_sum(Steps, window_size, align = "right", fill = NA)]

dt_steps_hr[, isRHR := NULL]
dt_steps_hr[(Id == id) & (rolling_sum_steps <= steps_threshold),
            isRHR := TRUE]
dt_steps_hr[(Id == id) & (rolling_sum_steps > steps_threshold),
            isRHR := FALSE]

dt_steps_hr[(Id == id) & isRHR == TRUE & !is.na(Value)]$Value %>% length()
dt_steps_hr[(Id == id) & isRHR == FALSE & !is.na(Value)]$Value %>% length()

dt_steps_hr[(Id == id) & isRHR == TRUE & !is.na(Value)]$Value %>% median()
dt_steps_hr[(Id == id) & isRHR == FALSE & !is.na(Value)]$Value %>% median()

dt_steps_hr[(Id == id) & isRHR == TRUE & !is.na(Value)]$Value %>% min()
dt_steps_hr[(Id == id) & isRHR == FALSE & !is.na(Value)]$Value %>% min()

dt_steps_hr[(Id == id) & isRHR == TRUE & !is.na(Value)]$Value %>% max()
dt_steps_hr[(Id == id) & isRHR == FALSE & !is.na(Value)]$Value %>% max()

# add sd to dt_metrics ----
load("plots_metrics_list_dev.RData")
dt_metrics <- plots_metrics_list$dt_metrics

dt_metrics[, RHR_sd := as.numeric(NA)]
dt_metrics[, notRHR_sd := as.numeric(NA)]
for (id in dt_metrics$Id %>% unique()) {
  window_size <- dt_metrics[Id == id]$window_size
  steps_threshold <- dt_metrics[Id == id]$steps_threshold
  
  dt_steps_hr[, rolling_sum_steps := NULL]
  dt_steps_hr[Id == id, rolling_sum_steps := roll_sum(Steps, window_size, align = "right", fill = NA)]
  
  dt_steps_hr[, isRHR := NULL]
  dt_steps_hr[(Id == id) & (rolling_sum_steps <= steps_threshold),
              isRHR := TRUE]
  dt_steps_hr[(Id == id) & (rolling_sum_steps > steps_threshold),
              isRHR := FALSE]
  
  # median
  dt_metrics[Id == id]$RHR_sd <- dt_steps_hr[(Id == id) & isRHR == TRUE & !is.na(Value)]$Value %>% sd()
  dt_metrics[Id == id]$notRHR_sd <- dt_steps_hr[(Id == id) & isRHR == FALSE & !is.na(Value)]$Value %>% sd()
}
save(dt_metrics, file = "dt_metrics.RData")

# sensitivity analysis ----
load("plots_metrics_list_dev.RData")
dt_metrics <- plots_metrics_list$dt_metrics

dt_sameWindow_list <- list()
dt_sameStep_list <- list()
# progress bar
pb <- txtProgressBar(min = 0, max = length(dt_metrics$Id %>% unique()), style = 3)
i = 1
for(id in dt_metrics$Id %>% unique()) {
  print(id)
  # constant window size, different num steps
  window_size_list <- dt_metrics[Id == id]$window_size  # minutes
  steps_threshold_list <- seq(0, 1000, 10)  # num. steps
  
  dt_results_sameWindow <- gridSearch_deviation_window_steps(dt_steps_hr[Id == id], window_size_list, steps_threshold_list)
  dt_results_sameWindow[, Id := id]
  dt_sameWindow_list <- c(dt_sameWindow_list, list(dt_results_sameWindow))
  
  # constant num steps, different window size
  window_size_list <- seq(1, 120, 1) # minutes
  steps_threshold_list <- dt_metrics[Id == id]$steps_threshold  # num. steps
  dt_results_sameStep <- gridSearch_deviation_window_steps(dt_steps_hr[Id == id], window_size_list, steps_threshold_list)
  dt_results_sameStep[, Id := id]
  dt_sameStep_list <- c(dt_sameStep_list, list(dt_results_sameStep))
  
  i = i + 1
}
close(pb)

dt_sameWindow <- rbindlist(dt_sameWindow_list)
dt_sameStep <- rbindlist(dt_sameStep_list)
save(dt_sameWindow, file = "dt_sameWindow.RData")
save(dt_sameStep, file = "dt_sameStep.RData")
