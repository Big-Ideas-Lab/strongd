source("utils.R")
load("RData_intermediate/dt_steps_hr_labeled.RData")
load("../RHR_estimation/dt_metrics.RData")

# consider only participants who have RHR estimates
id_list <- dt_metrics$Id
dt_steps_hr_labeled <- dt_steps_hr_labeled[Id %in% id_list]

# remove days when the number of steps is always zero
dt_steps_hr_labeled[, Date := as.Date(ActivityMin)]
keep <- dt_steps_hr_labeled[, sum(Steps), by = c("Id", "Date")][V1 != 0, .(Id, Date)]

setkey(dt_steps_hr_labeled, Id, Date)
setkey(keep, Id, Date)
dt_steps_hr_labeled <- dt_steps_hr_labeled[keep]

# show_linePerGroup(dt_steps_hr_labeled[Id == "0004" & Activity == 0 & ActivityMin > "2017-09-01" & ActivityMin < "2017-09-02"], "ActivityMin", "Value")

# rolling summary features of steps, HR and HR-RHR ----
# max, min, median, 25th and 75th percentiles
# mean, sd
# TODO: fft features (Ellis et al., 2016)

dt_steps_hr_labeled[, Date := NULL]

# HR-RHR and isRHR
dt_steps_hr_labeled[, HRminusRHR := 0]
for (id in id_list) {
  rhr <- dt_metrics[Id == id]$RHR_median
  dt_steps_hr_labeled[Id == id, HRminusRHR := Value - rhr]
}

setkey(dt_steps_hr_labeled, Id, ActivityMin)

window_size <- 5  # minutes
fun_list <- list(quote(max), quote(min), quote(median), quote(mean), quote(sd))
names <- c("max", "min", "median", "mean", "sd")
        
# progress bar
pb <- txtProgressBar(min = 1, max = length(fun_list), style = 3)
for (i in 1:length(fun_list)) {
  dt_steps_hr_labeled[,
                      (paste("Steps", names[i], sep = "_")) := rollapply(Steps, window_size, fun_list[[i]], na.rm = TRUE, align = "right", partial = TRUE),
                      by = Id]
  
  dt_steps_hr_labeled[,
                      (paste("HR", names[i], sep = "_")) := rollapply(Value, window_size, fun_list[[i]], na.rm = TRUE, align = "right", partial = TRUE),
                      by = Id]
  
  dt_steps_hr_labeled[,
                      (paste("HRminusRHR", names[i], sep = "_")) := rollapply(HRminusRHR, window_size, fun_list[[i]], na.rm = TRUE, align = "right", partial = TRUE),
                      by = Id]
  
  # progress bar
  setTxtProgressBar(pb, i)
}         

close(pb)

# HR_sd minues the estimated RHR sd
dt_steps_hr_labeled[, HR_sd_minus_RHR_sd := 0]
for (id in id_list) {
  rhr_sd <- dt_metrics[Id == id]$RHR_sd
  dt_steps_hr_labeled[Id == id, HR_sd_minus_RHR_sd := HR_sd - rhr_sd]
}

# quantiles
dt_steps_hr_labeled[,
                    Steps_25 := rollapply(Steps, window_size, quantile, probs = 0.25, na.rm = TRUE, align = "right", partial = TRUE),
                    by = Id]

dt_steps_hr_labeled[,
                    Steps_75 := rollapply(Steps, window_size, quantile, probs = 0.75, na.rm = TRUE, align = "right", partial = TRUE),
                    by = Id]
dt_steps_hr_labeled[,
                    HR_25 := rollapply(Value, window_size, quantile, probs = 0.25, na.rm = TRUE, align = "right", partial = TRUE),
                    by = Id]

dt_steps_hr_labeled[,
                    HR_75 := rollapply(Value, window_size, quantile, probs = 0.75, na.rm = TRUE, align = "right", partial = TRUE),
                    by = Id]

dt_steps_hr_labeled[,
                    HRminusRHR_25 := rollapply(HRminusRHR, window_size, quantile, probs = 0.25, na.rm = TRUE, align = "right", partial = TRUE),
                    by = Id]

dt_steps_hr_labeled[,
                    HRminusRHR_75 := rollapply(HRminusRHR, window_size, quantile, probs = 0.75, na.rm = TRUE, align = "right", partial = TRUE),
                    by = Id]

# set infinite values to NA
for(col in colnames(dt_steps_hr_labeled)) {
  set(dt_steps_hr_labeled, i = which(is.infinite(dt_steps_hr_labeled[[col]])), j = col, value = NA)
}

dt_features <- dt_steps_hr_labeled
save(dt_features, file = "RData_intermediate/dt_features.RData")

# TODO: debug rolling (pearson) correlation between steps and HR
# corr <- function(x) cor(x[[1]], x[[2]])
# dt_steps_hr_labeled[,
#                     corr_steps_hr := rollapply(.SD[, .(Value, Steps)], window_size, corr, align = "right", partial = TRUE, by.column=FALSE),
#                     by = Id]

# Farrahi et al. (2019):
# time domain
# frequency domain
# wavelet

# Ellis et al. (2016):
# table of features and summary functions
# fourier transform features seem to work especially well

