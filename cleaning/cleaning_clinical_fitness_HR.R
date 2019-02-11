library(data.table)
library(magrittr)

FILE_PATH_FITNESS = "RData_clean/dt_fitness.RData"
FILE_PATH_HR = "RData_clean/dt_hr_clinical.RData"

"Extracting and cleaning fitness + HR data (subset of clinical data)..."

# raw clinical data
dt_clinical <- fread("Sensitive_StrongD/Sensitive_20181031_StrongD_clinic_demog_fitnessSurvey.csv")

# extract relevant fitness measurements
dt_fitness <- dt_clinical[, .(Id = `Participant ID`, 
                              Date = `Date of Study Visit`, 
                              Weight_lbs = `Weight (lbs)`, 
                              Height_inches = `Height (inches)`,
                              Waist_inches = `Waist Circumference (inches)`)]

# extract relevant HR measurements
dt_hr_clinical <- dt_clinical[, .(Id = `Participant ID`, 
                                  Date = `Date of Study Visit`,
                                  HR_perMin_lying = `Pulse Reading Lying Down (bpm)`,
                                  HR_perMin_sitting = `Pulse Reading Sitting (bpm)`,
                                  HR_perMin_standing = `Pulse Reading Standing (bpm)`,
                                  RHR = `Resting Heart Rate`)]

# every value in the Id column has 10 characters:
# dt_fitness$Id %>% nchar() %>% unique()
# dt_hr_clinical$Id %>% nchar() %>% unique()

# the last 4 characters in each value of the Id column are the identifying characters/numbers
dt_fitness$Id <- dt_fitness$Id %>% substring(7, 10)
dt_hr_clinical$Id <- dt_hr_clinical$Id %>% substring(7, 10)

# remove rows with an empty date value (other measurement values in this row are mostly also empty/NA)
dt_fitness <- dt_fitness[Date != ""]
dt_hr_clinical <- dt_hr_clinical[Date != ""]

# convert Date column to Date class
# notice small %y (as opposed to %Y) because the year in the raw date is given with 2 digits (as opposed to all 4)
dt_fitness$Date <- as.Date(dt_fitness$Date, format = "%m/%d/%y")
dt_hr_clinical$Date <- as.Date(dt_hr_clinical$Date, format = "%m/%d/%y")
# check: 
# dt_fitness$Date %>% class()
# dt_hr_clinical$Date %>% class()

# remove rows where all RHR-related measurements are NA
dt_hr_clinical <- dt_hr_clinical[!is.na(HR_perMin_lying) | !is.na(HR_perMin_sitting) | !is.na(HR_perMin_standing) | !is.na(RHR)]

save(dt_fitness, file = FILE_PATH_FITNESS)
save(dt_hr_clinical, file = FILE_PATH_HR)

"Done! The clean fitness and HR data (subset of clinical data) are stored at the respective relative paths:"
FILE_PATH_FITNESS
FILE_PATH_HR