library(data.table)
library(magrittr)

FILE_PATH = "RData_clean/dt_signin.RData"

"Cleaning 24 hour fitness sign-in data..."

"Reading raw data..."
dt_signin <- fread("Sensitive_StrongD/20190410_completely_deID_StrongD_data.csv")

"Filtering and renaming columns..."
dt_signin[, (3) := NULL]
colnames(dt_signin) <- c("Id", "Time")

"Cleaning Id column..."
# every value in the Id column has 10 characters:
# dt_hr$Id %>% nchar() %>% unique()
# the last 4 characters in each value of the Id column are the identifying characters/numbers
dt_signin$Id <- dt_signin$Id %>% substring(7, 10)

"Cleaning Time column..."
# convert time to POSIXct class (this can take some time...)
dt_signin$Time <- as.POSIXct(dt_signin$Time, format = "%m/%d/%y %H:%M", tz = "GMT")
# note: GMT does not have daylight saving time (DST) and therefore will not omit invalid DST times as NA

"Saving..."
save(dt_signin, file = FILE_PATH)

"Done! The clean 24 hour fitness sign-in data are stored at the relative path:"
FILE_PATH