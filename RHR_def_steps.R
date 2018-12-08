# Tip: use RStudio's document outline for navigating this file

# Import ----
# contains commonly used functions and libraries
source("utils_custom.R")

# Load Cleaned Data ----
# see the cleaning directory for details of how this data was cleaned

load("cleaning/RData_clean/dt_steps.RData")
load("cleaning/RData_clean/dt_hr.RData")
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
id_list <- dt_steps_hr$Id %>% unique()  # 78 participants

# dt_steps_hr contains duplicate rows: `dt_steps_hr %>% duplicated() %>% any()` returns TRUE
# the HR data has duplicate rows --> thus, the join can create duplicates
# --> remove these duplicates so that we get correct values when we count steps below
setkey(dt_steps_hr, Id, ActivityMin)
dt_steps_hr <- unique(dt_steps_hr)

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

        # absolute difference between high_summaryHR (above threshold) and low_summaryHR (below threshold) for each participant
        dt_combined[, diff_summaryHR := abs(high_summaryHR - low_summaryHR)]

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
    
    # cleanup
    dt_steps_hr[, rolling_sum_steps := NULL]
  }
  
  close(pb)
  
  print("Window size and num. steps combination that produces the highest sensitivity:")
  print(dt_results[which.max(dt_results$sensitivity)])
  
  return(dt_results[which.max(dt_results$sensitivity)])
}

gridSearch_deviation_window_steps <- function(dt_steps_hr, window_size_list, steps_threshold_list) {
  # initialize table with all possible combinations of the step thresholds and window sizes specified above
  dt_results <- data.table(steps_threshold = rep(steps_threshold_list, each = length(window_size_list)),
                           window_size = window_size_list,  # will be recycled
                           deviation = as.numeric(rep(NA, length(steps_threshold_list)*length(window_size_list))))
  
  num_participants <- dt_steps_hr$Id %>% unique() %>% length()
  
  # progress bar
  pb <- txtProgressBar(min = 0, max = nrow(dt_results), style = 3)
  i = 1
  for (n in window_size_list) {
    dt_steps_hr[, 
                rolling_sum_steps := roll_sum(Steps, n, align = "right", fill = NA),
                by = Id]
    
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
      id_list <- intersect(dt_low_deviationHR_byId$Id, dt_high_deviationHR_byId$Id)
      dt_id <- data.table(Id = id_list)
      
      if (nrow(dt_id) >= ceiling(num_participants/2)) {
        dt_low_deviationHR_byId <- dt_low_deviationHR_byId[dt_id, on = "Id"]
        dt_high_deviationHR_byId <- dt_high_deviationHR_byId[dt_id, on = "Id"]
        
        dt_results[window_size == n & steps_threshold == m]$deviation <- mean(dt_low_deviationHR_byId$low_deviationHR)
      } else {
        dt_results[window_size == n & steps_threshold == m]$deviation <- NA
      }
      
      setTxtProgressBar(pb, i)
      i = i + 1
    }
    
    # cleanup
    dt_steps_hr[, rolling_sum_steps := NULL]
  }
  
  close(pb)
  print(dt_results[which.min(dt_results$deviation)])
  return(dt_results[which.min(dt_results$deviation)])
}


# Search 1: All participants ----

# step threshold search over different orders of magnitude
window_size_list <- c(1, 5, 10, 30, 60)  # minutes
steps_threshold_list <- c(10, 50, 100, 500, 1000, 5000, 10000)  # num. steps

dt_results <- gridSearch_window_steps(dt_steps_hr, function(...) {median(...)}, window_size_list, steps_threshold_list)
# here, I use median as the summary function, but other summary functions (with the na.rm option) can be used as well
# see dt_results for the sensitive value corresponding to each possible combination

# step threshold search over thousands
window_size_list <- c(1, 5, 10, 30, 60)  # minutes
steps_threshold_list <- c(2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000)  # num. steps
dt_results <- gridSearch_window_steps(dt_steps_hr, function(...) {median(...)}, window_size_list, steps_threshold_list)

# step threshold search over hundreds
window_size_list <- c(1, 5, 10, 30, 60)  # minutes
steps_threshold_list <- c(200, 300, 400, 500, 600, 700, 800, 900)  # num. steps
dt_results <- gridSearch_window_steps(dt_steps_hr, function(...) {median(...)}, window_size_list, steps_threshold_list)

# since we're interested in **resting** heart rate, let's try this same search over HR values below some threshold
# e.g. the mean: we want to observe a large sensitivity within the lower HR values rather than all HR values
meanHR <- mean(dt_steps_hr$Value, na.rm = TRUE)

# step threshold search over hundreds
window_size_list <- c(1, 5, 10, 30, 60)  # minutes
steps_threshold_list <- c(200, 300, 400, 500, 600, 700, 800, 900)  # num. steps
dt_results <- gridSearch_window_steps(dt_steps_hr[Value < meanHR], function(...) {median(...)}, window_size_list, steps_threshold_list)

# TODO: Best window + step threshold combination for each participant ----
# TODO: comparison across arms

gridSearch_savePlot_perId <- function(id_list, gridSearch_func, window_size_list, steps_threshold_list, soft = FALSE) {
  gridSearch_func_name <- substitute(gridSearch_func) %>% as.character()
  colors <- colorRampPalette(brewer.pal(8, "Dark2"))(length(id_list))
  
  for(i in 1:length(id_list)) {
    id <- id_list[i]
    print(sprintf("Searching for participant with id %s", id))
    
    if (soft == TRUE) {
      softmin <- dt_steps_hr[Id == id]$Value %>% quantile(0.05, na.rm = TRUE)
      softmax <- dt_steps_hr[Id == id]$Value %>% quantile(0.95, na.rm = TRUE)
      
      dt_best <- gridSearch_func(dt_steps_hr[Id == id & Value < softmax & Value > softmin], window_size_list, steps_threshold_list)  
    } else {
      dt_best <- gridSearch_func(dt_steps_hr[Id == id], window_size_list, steps_threshold_list)  
    }
   
    
    window_size <- dt_best$window_size
    steps_threshold <- dt_best$steps_threshold
    
    dt_steps_hr[, rolling_sum_steps := NULL]
    dt_steps_hr[Id == id, rolling_sum_steps := roll_sum(Steps, window_size, align = "right", fill = NA)]
    
    dt_steps_hr[, isRHR := FALSE]
    dt_steps_hr[(Id == id) & (rolling_sum_steps <= steps_threshold),
                isRHR := TRUE]
    
    show_linePerGroup(dt_steps_hr[isRHR == TRUE & Id == id], "ActivityMin", "Value", "Id") +
      scale_color_manual(values = colors[i])
    print(sprintf("%s_window=%d_steps=%d_isRHR=TRUE_%s_soft=%s.png", id, window_size, steps_threshold, gridSearch_func_name, as.character(soft)))
    sprintf("%s_window=%d_steps=%d_isRHR=TRUE_%s_soft=%s.png", id, window_size, steps_threshold, gridSearch_func_name, as.character(soft)) %>%
      save_plot_temp()
    
    show_linePerGroup(dt_steps_hr[isRHR == FALSE & Id == id], "ActivityMin", "Value", "Id") +
      scale_color_manual(values = colors[i])
    sprintf("%s_window=%d_steps=%d_isRHR=FALSE_%s_soft=%s.png", id, window_size, steps_threshold, gridSearch_func_name, as.character(soft)) %>%
      save_plot_temp()
  }
}

# sample 3 participants
set.seed(0)
id_sample <- sample(id_list, 3)

# step threshold search over hundreds
window_size_list <- c(1, 5, 10, 30, 60)  # minutes
steps_threshold_list <- c(0, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000)  # num. steps

gridSearch_savePlot_perId(id_sample, gridSearch_diff_window_steps, window_size_list, steps_threshold_list, soft=TRUE)
