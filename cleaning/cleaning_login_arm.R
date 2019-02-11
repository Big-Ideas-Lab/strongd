library(data.table)
library(magrittr)

FILE_PATH = "RData_clean/dt_login_arm.RData"

"Cleaning iPad login and study arm data..."

# raw login and study arm data
dt_login_arm <- fread("Sensitive_StrongD/Sensitive_20181031_Study_Arm_Assignments_24hFitness_iPad_checkins.csv")
# there are 3 study arms: 
# dt_arm$`Survey Randomization Group` %>% unique()

# Clean login and arm data ----
# after the 4th character, the `Participant Id`` column holds the sign-in date -->
# only use the first 4 characters as id
dt_login_arm[, Id := substring(`Participant ID`, 1, 4)] 

# remove rows with an empty string in the `Survey Randomization Group` column
dt_login_arm <- dt_login_arm[`Survey Randomization Group` != ""]
# remove records that were used for testing the ipad login system
dt_login_arm <- dt_login_arm[Id != "TEST"]

# convert time to POSIXct class
dt_login_arm[, Date := as.POSIXct(dt_login_arm$`Survey Date`, format = "%Y-%m-%d", tz = "GMT")]
# note: GMT does not have daylight saving time (DST) and therefore will not omit invalid DST times as NA

# simplify arm column
dt_login_arm[, Arm := `Survey Randomization Group`]
dt_login_arm$Arm <- dt_login_arm[, sub("Arm 1: Strength Training Only", "1", Arm)]
dt_login_arm$Arm <- dt_login_arm[, sub("Arm 2: Aerobic Training Only", "2", Arm)]
dt_login_arm$Arm <- dt_login_arm[, sub("Arm 3: Combination \\(Aerobic and Strength\\) Taining", "3", Arm)]
dt_login_arm$Arm <- as.integer(dt_login_arm$Arm)

dt_login_arm <- dt_login_arm[, .(Id, Arm, Date)]

save(dt_login_arm, file = FILE_PATH)

"Done! The clean study arm data is stored at the relative path:"
FILE_PATH