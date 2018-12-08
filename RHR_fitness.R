# Tip: use RStudio's document outline for navigating this file

# Import ----
library(data.table)
library(magrittr)
library(ggplot2)
library(RColorBrewer)
library(RcppRoll)

# contains commonly used functions
source("utils_custom.R")

# Load Cleaned Data ----
# see the cleaning directory for details of how this data was cleaned

load("cleaning/RData_clean/dt_fitness.RData")

# Fitness defined as BMI ----

# check that all weight and height measurements are made on the same date (for the same person)
all(dt_fitness[!is.na(Weight_lbs), .(Id, Date)] == dt_fitness[!is.na(Height_inches), .(Id, Date)])
# [1] TRUE

# using the above check, we can calculate BMI for a row by simply using the weight and height values in the same row
# BMI formula from: https://www.cdc.gov/nccdphp/dnpao/growthcharts/training/bmiage/page5_2.html
dt_fitness[, BMI := Weight_lbs/(Height_inches^2) * 703]

# remove participants with only <=1 BMI measurement (we can't find the **change** (over time) in fitness/BMI for these participants)
id_list <- dt_fitness$Id %>% unique()
dt_id <- data.table(Id = id_list)  # table of unique participant ids
dt_numMeasurements_perId <- dt_fitness[!is.na(BMI), .N, by = Id]  # num. non-NA BMI measurements per participant

# join to make sure we include all participants, even those who have 0 non-NA BMI measurements
dt_numMeasurements_perId <- dt_numMeasurements_perId[dt_id, on = "Id"]
dt_numMeasurements_perId[is.na(N), N := 0]

dt_id_enoughMeasurements <- dt_numMeasurements_perId[N > 1, .(Id)]  # participants with strictly more than 1 BMI measurement

dt_fitness <- dt_fitness[dt_id_enoughMeasurements, on = "Id"]

# remove rows with NA BMI values
dt_fitness <- dt_fitness[!is.na(BMI)]

# are there participants with more than 2 BMI measurements?
dt_fitness[, .N, by = Id][N > 2]$Id  # participant 0118 has 3 measurements

# one of these measurements seems to be the result of incorrect data entry
dt_fitness[Id == "0118"]

# BMI ranges from: https://www.nhlbi.nih.gov/health/educational/lose_wt/BMI/bmicalc.htm