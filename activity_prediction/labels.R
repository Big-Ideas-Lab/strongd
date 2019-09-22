# Import ----
# contains commonly used functions and libraries
source("utils.R")

# Load Cleaned Data ----
# see the cleaning directory for details of how this data was cleaned

# all daytime HR values from 1 Aug. 2017 to 27 Sep. 2018
load("../cleaning/RData_clean/dt_hr_all.RData")
dt_hr <- dt_hr_all
rm(dt_hr_all)
# steps
load("../cleaning/RData_clean/dt_steps.RData")
# study arm
load("../cleaning/RData_clean/dt_arm_simple.RData")
# timestamp labels for when participants entered the gym (24 hour fitness)
load("../cleaning/RData_clean/dt_signin.RData")

# Interpolate per second HR measurement for each per minute step measurement ----
# same as the procedure done for the RHR estimation project

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
# # remove step measurements that do not have an interpolated HR value
# dt_steps_hr <- dt_steps_hr[!is.na(Value)]
id_list <- dt_steps_hr$Id %>% unique()

setkey(dt_steps_hr, Id, ActivityMin)


# Use the sign-in and study arm data to create a labeled data set ----
# The labels indicate when participants were performing which type of activity

setkey(dt_signin, Id, Time)

# # choose observations within [sign-in - 1hr] and [sign-in + 1hr]
# dt_steps_hr[, Keep := FALSE]
# # progress bar
# pb <- txtProgressBar(min = 1, max = nrow(dt_signin), style = 3)
# for (i in 1:nrow(dt_signin)) {
#   id <- dt_signin[i, Id] 
#   start <- dt_signin[i, Time]
#   end <- start + 60*60  # participants stay in the gym for ~1hr after signing in
#   before <- start - 60*60
#   
#   dt_steps_hr[Id == id & ActivityMin >= before & ActivityMin <= end, Keep := TRUE]
#   
#   # progress bar
#   setTxtProgressBar(pb, i)
# }
# 
# close(pb)
# 
# save(dt_steps_hr, file = "RData_intermediate/dt_steps_hr_keep.RData")

load("RData_intermediate/dt_steps_hr_keep.RData")

# among the filtered measurements, label active vs not active
dt_steps_hr <- dt_steps_hr[(Keep)]

dt_steps_hr[, Keep := NULL]
dt_steps_hr[, Active := FALSE]
# Active=1: exercising in the gym
# Active=0: not exercising, assumed to apply to the observations within 1hr before the participant
# signs in to the gym

# progress bar
pb <- txtProgressBar(min = 1, max = nrow(dt_signin), style = 3)
for (i in 1:nrow(dt_signin)) {
  id <- dt_signin[i, Id]
  start <- dt_signin[i, Time]
  end <- start + 60*60  # participants stay in the gym for ~1hr after signing in
  # +10min buffer to account for e.g. locker time after participant signs in
  start_buffer <- start + 10*60
  
  dt_steps_hr[Id == id & ActivityMin >= start_buffer & ActivityMin <= end, Active := TRUE]
  
  # progress bar
  setTxtProgressBar(pb, i)
}

close(pb)

# among Active=TRUE, label non-strength/aerobic/combined (0) vs strength (1) vs aerobic (2) vs combined (3)
# (non-strength/aerobic/combined is assumed to occur during the hour before sign-in)

colnames(dt_arm_simple) <- c("Id", "Activity")
setkey(dt_steps_hr, Id)
setkey(dt_arm_simple, Id)
dt_steps_hr_labeled <- dt_arm_simple[dt_steps_hr]
dt_steps_hr_labeled[!(Active), Activity := 0]
dt_steps_hr_labeled <- dt_steps_hr_labeled[, .(Id, ActivityMin, Steps, Value, Activity)]

save(dt_steps_hr_labeled, file = "RData_intermediate/dt_steps_hr_labeled.RData")

