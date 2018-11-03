library(data.table)
library(magrittr)

FILE_PATH = "RData_clean/dt_arm_simple.RData"

"Cleaning study arm data..."

# raw study arm data
dt_arm <- fread("Sensitive_StrongD/Sensitive_20181031_Study_Arm_Assignments_24hFitness_iPad_checkins.csv")
# there are 3 study arms: 
# dt_arm$`Survey Randomization Group` %>% unique()

# Clean study arm data ----
# after the 4th character, the `Participant Id`` column holds the sign-in date -->
# only use the first 4 characters as id
dt_arm[, id := substring(`Participant ID`, 1, 4)] 

# remove rows with an empty string in the `Survey Randomization Group` column
dt_arm <- dt_arm[`Survey Randomization Group` != ""]
# remove records that were used for testing the ipad login system
dt_arm <- dt_arm[id != "TEST"]

# dt_arm contains one record per sign-in, so let's simplify it to only indicate
# which participant belongs to which study arm
dt_arm_simple <- dt_arm[, .(arm = unique(`Survey Randomization Group`)), by = id]
# there are 3 arms: 
# dt_arm_simple$arm %>% unique()

# to check that each participant entered the same study arm category per sign-in:
# dt_arm_simple %>% nrow == dt_arm$id %>% unique() %>% length()
# when this evaluates to true, we know that each unique participant (from the original data)
# has only one corresponding row in the simplified data, i.e. has only one unique study arm that
# they entered into the ipad every time

# simplify arm column
dt_arm_simple <- dt_arm_simple[, .(id, arm = sub("Arm 1: Strength Training Only", "1", arm))]
dt_arm_simple <- dt_arm_simple[, .(id, arm = sub("Arm 2: Aerobic Training Only", "2", arm))]
dt_arm_simple <- dt_arm_simple[, .(id, arm = sub("Arm 3: Combination \\(Aerobic and Strength\\) Taining", "3", arm))]
dt_arm_simple$arm <- as.integer(dt_arm_simple$arm)

save(dt_arm_simple, file = FILE_PATH)

"Done! The clean study arm data is stored at the relative path:"
FILE_PATH
