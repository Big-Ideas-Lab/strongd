library(data.table)
library(magrittr)

FILE_PATH = "RData_clean/dt_steps.RData"

"Cleaning steps data..."

# raw steps data
dt_steps <- fread("data_raw/minuteStepsWide_merged.csv")

# every value in the Id column has 10 characters:
# dt_hr$Id %>% nchar() %>% unique()

# the last 4 characters in each value of the Id column are the identifying characters/numbers
dt_steps$Id <- dt_steps$Id %>% substring(7, 10)

# convert time to POSIXct class
dt_steps$ActivityHour <- as.POSIXct(dt_steps$ActivityHour, format = "%m/%d/%Y %I:%M:%S %p", tz = "GMT")
# note: GMT does not have daylight saving time (DST) and therefore will not omit invalid DST times as NA

# convert one entry/row per hour format to one entry/row per minute format
# initialize data table for storing per minute steps data
nrow <- nrow(dt_steps)*60  # need 60 per minute entries for each original per hour entry
dt_steps_perMin <- data.table(Id = as.character(rep(NA,nrow)), 
                              ActivityMin = as.POSIXct(rep(NA,nrow)), 
                              Steps = as.numeric(rep(NA,nrow)))

attributes(dt_steps_perMin$ActivityMin)$tzone <- "GMT"

"Converting per hour table format to per minute table format (this will take a long time, watch the progress bar)..."
# progress bar
pb <- txtProgressBar(min = 1, max = nrow(dt_steps), style = 3)
for (i in 1:nrow(dt_steps)) {
  id <- dt_steps[i, Id]
  min <- dt_steps[i, ActivityHour]
  steps_vec <- dt_steps[i, 3:ncol(dt_steps)] %>% as.numeric()  # length=60
  
  # create 60 per minute entries for each original per hour entry
  for (k in 1:60) {
    set(dt_steps_perMin,
        i = (i-1L)*60L + k,
        j = colnames(dt_steps_perMin),
        value = list(id, min, steps_vec[k]))
    
    min = min + 60  # increment by 60s=1min
  }
  
  # progress bar
  setTxtProgressBar(pb, i)
}

close(pb)

save(dt_steps_perMin, file = FILE_PATH)

"Done! The clean steps data is stored at the relative path:"
FILE_PATH
