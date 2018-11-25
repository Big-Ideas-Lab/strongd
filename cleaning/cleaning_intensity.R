library(data.table)
library(magrittr)

FILE_PATH = "RData_clean/dt_intensity.RData"

"Cleaning per minute intensity data (give this a few minutes)..."

# raw per minute intensity data
dt_intensity <- fread("data_raw/minuteIntensitiesNarrow_merged.csv")

# every value in the Id column has 10 characters:
# dt_intensity$Id %>% nchar() %>% unique()

"Cleaning Id column..."
# the last 4 characters in each value of the Id column are the identifying characters/numbers
dt_intensity$Id <- dt_intensity$Id %>% substring(7, 10)

"Cleaning ActivityMinute column..."
# convert time to POSIXct class (this can take some time...)
dt_intensity$ActivityMinute <- as.POSIXct(dt_intensity$ActivityMinute, format = "%m/%d/%Y %I:%M:%S %p", tz = "GMT")
# note: GMT does not have daylight saving time (DST) and therefore will not omit invalid DST times as NA

"Saving..."
save(dt_intensity, file = FILE_PATH)

"Done! The clean sample of per minute intensity data is stored at the relative path:"
FILE_PATH
