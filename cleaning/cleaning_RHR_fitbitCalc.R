library(data.table)
library(magrittr)

FILE_PATH = "RData_clean/dt_rhr_fitbitCalc.RData"

"Cleaning daily resting heart rate data (calculated by Fitbit)..."

# raw daily activity data
dt_dailyActivity <- fread("data_raw/dailyActivity_merged.csv")

# extract daily RHR measurements
dt_rhr <- dt_dailyActivity[, .(Id, RestingHeartRate, ActivityDate)]
# preview: dt_rhr %>% head()
# this data has missing values; to see the ratio (~26.4%) of missing values to the number of observations:
# dt_rhr$RestingHeartRate %>% is.na() %>% sum() %>% divide_by(nrow(dt_rhr))

# every value in the Id column has 10 characters:
# dt_rhr$Id %>% nchar() %>% unique()

# the last 4 characters in each value of the Id column are the identifying characters/numbers
dt_rhr$Id <- dt_rhr$Id %>% substring(7, 10)

# convert ActivityDate column to Date class
dt_rhr$ActivityDate <- as.Date(dt_rhr$ActivityDate, format = "%m/%d/%Y")
# check: 
# dt_rhr$ActivityDate %>% class()

save(dt_rhr, file = FILE_PATH)

"Done! The clean daily resting heart rate data (calculated by Fitbit) is stored at the relative path:"
FILE_PATH