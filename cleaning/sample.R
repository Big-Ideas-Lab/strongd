library(data.table)
library(magrittr)
library(lubridate)

FILE1 <- "data_raw/20170801_20180315_heartrate_seconds_merged.csv"
FILE2 <- "data_raw/20180316_20180701_heartrate_seconds_merged.csv"
FILE3 <- "data_raw/20180702_20180927_heartrate_seconds_merged.csv"
NUM_DAYS_PER_ID <- 85
NEW_FILENAME <- sprintf("RData_intermediate/allHR_%ddays.RData", NUM_DAYS_PER_ID)
NIGHT_START <- 22  # hours
NIGHT_END <- 6  # hours

"Reading in csv files..."
dt1 <- fread(FILE1)
dt2 <- fread(FILE2)
dt3 <- fread(FILE3)

"Combining separate csv files into one large data table..."
dt_all <- rbindlist(list(dt1, dt2, dt3))
rm(dt1, dt2, dt3)
id_list <- dt_all$Id %>% unique()

"Cleaning Time column..."
# convert time to POSIXct class (this can take some time...)
# dt_all$Time <- as.POSIXct(dt_all$Time, format = "%m/%d/%Y %I:%M:%S %p", tz = "GMT")
dt_all$Time <- fast_strptime(dt_all$Time, "%m/%d/%Y %I:%M:%S %p", tz = "GMT", lt = FALSE)
# note: GMT does not have daylight saving time (DST) and therefore will not omit invalid DST times as NA
save(dt_all, file = "RData_intermediate/20170801_20180927_heartrate_seconds_merged_all_posixct.RData")

"Removing night-time measurements..."
# remove night/sleep-time heart rate values
dt_all <- dt_all[hour(Time) < NIGHT_START & hour(Time) > NIGHT_END]
save(dt_all, file = "RData_intermediate/20170801_20180927_heartrate_seconds_merged_all_posixct_day.RData")

"Storing sample data tables..."
# store a sample dt for each participant inside a list
dt_sample_list <- list()
for (id in id_list) {
  print(sprintf("Sampling for participant %s.", id))
  start_time <- dt_all[Id == id]$Time %>% min(na.rm = TRUE)
  end_time <- start_time + 60*60*24*NUM_DAYS_PER_ID
  dt_sample_list <- c(dt_sample_list, list(dt_all[Id == id & Time >= start_time & Time <= end_time]))
}

"Concatenating sample data tables..."
# concatenate the sample dts into one dt
dt_sample <- rbindlist(dt_sample_list)

"Saving..."
save(dt_sample, file = NEW_FILENAME)
