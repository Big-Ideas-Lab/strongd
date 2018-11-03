library(data.table)
library(magrittr)

FILE_PATH = "RData_clean/dt_hr.RData"

"Cleaning sample of per second heart rate data (give this a few minutes)..."

# raw per second heart rate data
# note that this is only a sample of the data since the whole dataset is too large to perform EDA on;
# once I've finalized the analysis code and decided on the outputs/graphs I want, 
# I will run the final code on the full dataset

"Reading raw data..."
dt_hr <- fread("data_raw/20170801_20180927_heartrate_seconds_merged_sample_mergedAll.csv")

# TODO: fix data merging (don't merge the first line of csv files with the column names), the following is an inelegant quick fix...
dt_hr <- dt_hr[Value != "Value"]

# every value in the Id column has 10 characters:
# dt_hr$Id %>% nchar() %>% unique()

"Cleaning Id column..."
# the last 4 characters in each value of the Id column are the identifying characters/numbers
dt_hr$Id <- dt_hr$Id %>% substring(7, 10)

"Cleaning Time column..."
# convert time to POSIXct class (this can take some time...)
dt_hr$Time <- as.POSIXct(dt_hr$Time, format = "%m/%d/%Y %I:%M:%S %p")

"Cleaning Value column..."
# convert heart rate values (originally character class) to numerical class
dt_hr$Value <- as.numeric(dt_hr$Value)

"Saving..."
save(dt_hr, file = FILE_PATH)

"Done! The clean sample of per second heart rate data is stored at the relative path:"
FILE_PATH
