# Tip: use RStudio's document outline for navigating this file

# Import ----
library(data.table)
library(magrittr)
library(ggplot2)
library(RColorBrewer)
library(RcppRoll)

# contains commonly used functions
source("utils_custom.R")

# Load Cleaned Data ----
# see the cleaning directory for details of how this data was cleaned

load("cleaning/RData_clean/dt_steps.RData")
load("cleaning/RData_clean/dt_hr.RData")

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

gridSearch_window_steps <- function(dt_steps_hr, summary_func, window_size_list, steps_threshold_list) {
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
  
  id_list <- dt_rangeHR_byId$Id  # unique ids
  dt_id <- data.table(Id = id_list)
  
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
                                           .(low_summaryHR = summary_func(Value, na.rm = TRUE)),
                                           by = Id]
      
      # summary HR where rolling_sum_steps > steps_threshold for each participant
      dt_high_summaryHR_byId <- dt_steps_hr[rolling_sum_steps > m,
                                            .(high_summaryHR = summary_func(Value, na.rm = TRUE)),
                                            by = Id]
      
      # right outer join to make sure all unique ids are included 
      # (ids without a summary value will just be padded with NAs in the summary column)
      dt_low_summaryHR_byId <- dt_low_summaryHR_byId[dt_id, on = "Id"]
      dt_high_summaryHR_byId <- dt_high_summaryHR_byId[dt_id, on = "Id"]
      
      stopifnot(dt_low_summaryHR_byId$Id == dt_high_summaryHR_byId$Id & dt_low_summaryHR_byId$Id == dt_rangeHR_byId$Id)
      
      dt_combined <- copy(dt_rangeHR_byId)
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
      sensitivity <- dt_combined[, mean(ratio_diff_range, na.rm = TRUE)]
      
      # append to results table
      dt_results[window_size == n & steps_threshold == m]$sensitivity <- sensitivity
      
      setTxtProgressBar(pb, i)
      i = i + 1
    }
    
    # cleanup
    dt_steps_hr[, rolling_sum_steps := NULL]
  }
  
  close(pb)
  
  print("Window size and num. steps combination that produces the highest sensitivity:")
  print(dt_results[which.max(dt_results$sensitivity)])
  
  return(dt_results)
}

# Search 1: All HR Values ----

# step threshold search over different orders of magnitude
window_size_list <- c(1, 5, 10, 30, 60)  # minutes
steps_threshold_list <- c(10, 50, 100, 500, 1000, 5000, 10000)  # num. steps

dt_results <- gridSearch_window_steps(dt_steps_hr, function(...) {median(...)}, window_size_list, steps_threshold_list)
# here, I use median as the summary function, but other summary functions (with the na.rm option) can be used as well
# see dt_results for the sensitive value corresponding to each possible combination

# [1] "Window size and num. steps combination that produces the highest sensitivity:"
# steps_threshold window_size sensitivity
# 1:            5000          30    0.496732

# the NaNs in dt_results indicate that steps_threshold and window_size combination has probably exceeded the max possible steps in a time window

# step threshold search over thousands
window_size_list <- c(1, 5, 10, 30, 60)  # minutes
steps_threshold_list <- c(2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000)  # num. steps
dt_results <- gridSearch_window_steps(dt_steps_hr, function(...) {median(...)}, window_size_list, steps_threshold_list)

# [1] "Window size and num. steps combination that produces the highest sensitivity:"
# steps_threshold window_size sensitivity
# 1:            5000          30    0.496732

# step threshold search over hundreds
window_size_list <- c(1, 5, 10, 30, 60)  # minutes
steps_threshold_list <- c(200, 300, 400, 500, 600, 700, 800, 900)  # num. steps
dt_results <- gridSearch_window_steps(dt_steps_hr, function(...) {median(...)}, window_size_list, steps_threshold_list)

# [1] "Window size and num. steps combination that produces the highest sensitivity:"
# steps_threshold window_size sensitivity
# 1:             900           5   0.6291139

# step threshold search over tens
window_size_list <- c(1, 5, 10, 30, 60)  # minutes
steps_threshold_list <- c(20, 30, 40, 50, 60, 70, 80, 90)  # num. steps
dt_results <- gridSearch_window_steps(dt_steps_hr, function(...) {median(...)}, window_size_list, steps_threshold_list)

# [1] "Window size and num. steps combination that produces the highest sensitivity:"
# steps_threshold window_size sensitivity
# 1:              90           1   0.2305746

# step threshold search over ones
window_size_list <- c(1, 5, 10, 30, 60)  # minutes
steps_threshold_list <- c(1, 2, 3, 4, 5, 6, 7, 8, 9)  # num. steps
dt_results <- gridSearch_window_steps(dt_steps_hr, function(...) {median(...)}, window_size_list, steps_threshold_list)

# [1] "Window size and num. steps combination that produces the highest sensitivity:"
# steps_threshold window_size sensitivity
# 1:               9           1   0.1335809

# Search 2: Below median HR Values ----

# since we're interested in **resting** heart rate, let's try this same search over HR values below some threshold
# e.g. the median: we want to observe a large sensitivity within the lower HR values rather than all HR values
medianHR <- median(dt_steps_hr$Value, na.rm = TRUE)

# step threshold search over different orders of magnitude
window_size_list <- c(1, 5, 10, 30, 60)  # minutes
steps_threshold_list <- c(10, 50, 100, 500, 1000, 5000, 10000)  # num. steps
dt_results <- gridSearch_window_steps(dt_steps_hr[Value < medianHR], function(...) {median(...)}, window_size_list, steps_threshold_list)

# [1] "Window size and num. steps combination that produces the highest sensitivity:"
# steps_threshold window_size sensitivity
# 1:            1000          10   0.2105664

# step threshold search over thousands
window_size_list <- c(1, 5, 10, 30, 60)  # minutes
steps_threshold_list <- c(2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000)  # num. steps
dt_results <- gridSearch_window_steps(dt_steps_hr[Value < medianHR], function(...) {median(...)}, window_size_list, steps_threshold_list)

# [1] "Window size and num. steps combination that produces the highest sensitivity:"
# steps_threshold window_size sensitivity
# 1:            2000          30   0.2126597

# step threshold search over hundreds
window_size_list <- c(1, 5, 10, 30, 60)  # minutes
steps_threshold_list <- c(200, 300, 400, 500, 600, 700, 800, 900)  # num. steps
dt_results <- gridSearch_window_steps(dt_steps_hr[Value < medianHR], function(...) {median(...)}, window_size_list, steps_threshold_list)

# [1] "Window size and num. steps combination that produces the highest sensitivity:"
# steps_threshold window_size sensitivity
# 1:             800          10   0.2454909

# step threshold search over tens
window_size_list <- c(1, 5, 10, 30, 60)  # minutes
steps_threshold_list <- c(20, 30, 40, 50, 60, 70, 80, 90)  # num. steps
dt_results <- gridSearch_window_steps(dt_steps_hr[Value < medianHR], function(...) {median(...)}, window_size_list, steps_threshold_list)

# [1] "Window size and num. steps combination that produces the highest sensitivity:"
# steps_threshold window_size sensitivity
# 1:              90           1   0.1762583

# step threshold search over ones
window_size_list <- c(1, 5, 10, 30, 60)  # minutes
steps_threshold_list <- c(1, 2, 3, 4, 5, 6, 7, 8, 9)  # num. steps
dt_results <- gridSearch_window_steps(dt_steps_hr[Value < medianHR], function(...) {median(...)}, window_size_list, steps_threshold_list)

# [1] "Window size and num. steps combination that produces the highest sensitivity:"
# steps_threshold window_size sensitivity
# 1:               8           5   0.1390948

# TODO: find best window + step threshold combination for each participant? ----
