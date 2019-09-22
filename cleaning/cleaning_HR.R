library(data.table)
library(magrittr)

FILE_PATH_85 = "RData_clean/dt_hr.RData"
FILE_PATH_ALL = "RData_clean/dt_hr_all.RData"

"Cleaning sample of per second heart rate data (give this a few minutes)..."

# raw per second heart rate data
# note that this is only a sample of the data since the whole dataset is too large to perform EDA on;
# once I've finalized the analysis code and decided on the outputs/graphs I want, 
# I will run the final code on the full dataset

"Reading raw data..."
load("RData_intermediate/allHR_85days.RData")
load("RData_intermediate/20170801_20180927_heartrate_seconds_merged_all_posixct_day.RData")

dt_hr <- dt_sample
rm(dt_sample)
dt_hr_all <- dt_all
rm(dt_all)

# every value in the Id column has 10 characters:
# dt_hr$Id %>% nchar() %>% unique()

"Cleaning Id column..."
# the last 4 characters in each value of the Id column are the identifying characters/numbers
dt_hr$Id <- dt_hr$Id %>% substring(7, 10)
dt_hr_all$Id <- dt_hr_all$Id %>% substring(7, 10)

# "Cleaning Time column..."
# # convert time to POSIXct class (this can take some time...)
# dt_hr$Time <- as.POSIXct(dt_hr$Time, format = "%m/%d/%Y %I:%M:%S %p", tz = "GMT")
# # note: GMT does not have daylight saving time (DST) and therefore will not omit invalid DST times as NA

"Cleaning Value column..."
# convert heart rate values (originally character class) to numerical class
dt_hr$Value <- as.numeric(dt_hr$Value)
dt_hr_all$Value <- as.numeric(dt_hr_all$Value)

"Removing duplicates..."
dt_hr <- unique(dt_hr, by = c("Id", "Time"))
dt_hr_all <- unique(dt_hr_all, by = c("Id", "Time"))

"Saving..."
save(dt_hr, file = FILE_PATH_85)
save(dt_hr_all, file = FILE_PATH_ALL)

"Done! The clean sample of per second heart rate data is stored at the relative path:"
FILE_PATH_85
FILE_PATH_ALL
