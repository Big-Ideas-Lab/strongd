library(data.table)
library(magrittr)

# GOAL: remove participants with too few measurements in their first 85-day time period
# too few: less than half of the mean number of measurements

load("RData_clean/dt_hr.RData")
load("RData_clean/dt_hr_clinical.RData")

mean_num <- dt_hr[, .N, by=Id]$N %>% mean()
keep <- dt_hr[, .N >= 0.5*mean_num, by = Id][V1 == TRUE]$Id
dt_hr <- dt_hr[Id %in% keep]
save(dt_hr, file = "RData_clean/dt_hr_filtered.RData")
