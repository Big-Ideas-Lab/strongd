# Tip: use RStudio's document outline for navigating this file

# Import ----
library(data.table)
library(magrittr)
library(ggplot2)
library(RColorBrewer)

# contains commonly used functions
source("utils_custom.R")

# Load Cleaned Data ----
# see the cleaning directory for details of how this data was cleaned

# fast load
load("cleaning/RData_clean/dt_arm_simple.RData")
load("cleaning/RData_clean/dt_rhr_fitbitCalc.RData")

# slow load
load("cleaning/RData_clean/dt_hr.RData")
load("cleaning/RData_clean/dt_intensity.RData")

# RHR per Day using Fitbit's Calculated Daily RHR  ----
# list of all unique participant ids
id_list <- dt_rhr$Id %>% unique()  # 79 participants

# plot RHR over time for **a few** people
show_linePerGroup(dt_rhr[Id %in% id_list[1:5]], "ActivityDate", "RestingHeartRate", "Id")
# (see utils_custom.R for function definition)

# setup for join on id
dt_rhr[, join_id := Id]
dt_arm_simple[, join_id := id]
setkey(dt_rhr, join_id)
setkey(dt_arm_simple, join_id)

# right outer join (include all measurements from dt_rhr) 
# to get the corresponding study arm for each participant in dt_rhr
join_rhr_arm <- dt_arm_simple[dt_rhr]
dt_rhr_arm <- join_rhr_arm[, .(Id, arm, RestingHeartRate, ActivityDate)]

# change the category name for each arm value (1,2,3)
dt_rhr_arm$arm <- as.factor(dt_rhr_arm$arm)
# levels(dt_rhr_arm$arm) outputs [1] "1" "2" "3"
# rename the factors corresponding levels:
levels(dt_rhr_arm$arm) <- c("strength", "aerobic", "combination")

# >PLOT RHR per day for each participant, faceted by study arm ----
# each participant is represented by a uniquely colored line
show_linePerGroup(dt_rhr_arm, "ActivityDate", "RestingHeartRate", "Id") +
  facet_grid(. ~ arm) +
  scale_color_manual(values = colorRampPalette(brewer.pal(12, "Paired"))(length(id_list))) +
  xlab("Day") +
  ylab("Resting Heart Rate (Calculated by Fitbit)")

# save_plot("RHR_fitbit_perArm.png")

# >PLOT median RHR per day for each study arm, faceted by study arm ----
show_linePerGroup(dt_rhr_arm[, median(RestingHeartRate, na.rm = TRUE), by = .(arm, ActivityDate)], "ActivityDate", "V1") +
  facet_grid(. ~ arm) +
  scale_color_manual(values = colorRampPalette(brewer.pal(12, "Paired"))(length(id_list))) +
  xlab("Day") +
  ylab("Median Resting Heart Rate")

# save_plot("medianRHR_fitbit_perArm.png")

# RHR per Day using Raw Per Second HR and Per Minute Intensity Levels ----

# FIRST, we want to combine the two data.tables dt_hr and dt_intensity:
# **interpolate the intensity category for each heart rate measurement**, i.e. 
# join per second heart rate data with per minute intensity data by 
# finding the temporally closest intensity category for each heart rate measurement.

# setup for join on id and then within each unique id value, join on time
dt_hr[, join_time := Time]
dt_intensity[, join_time := ActivityMinute]

setkey(dt_hr, Id, join_time)
setkey(dt_intensity, Id, join_time)

# right outer join (include all measurements from dt_hr), interpolating the temporally closest intensity value/category for each HR measurement
join_hr_intensity <- dt_intensity[dt_hr, roll = "nearest"]

dt_hr_allIntensity <- join_hr_intensity[, .(Id, Time, Value, Intensity)]
id_list <- dt_hr_allIntensity$Id %>% unique()  # 78 participants

# SECOND, we want to join dt_hr_allIntensity with dt_arm_simple
# setup for join on id
dt_hr_allIntensity[, join_id := Id]
dt_arm_simple[, join_id := id]
setkey(dt_hr_allIntensity, join_id)
setkey(dt_arm_simple, join_id)

# right outer join (include all measurements from dt_hr_allIntensity) 
# to get the corresponding study arm for each participant in dt_hr_allIntensity
join_hr_allIntensity_arm <- dt_arm_simple[dt_hr_allIntensity]
dt_hr_allIntensity_arm <- join_hr_allIntensity_arm[, .(Id, arm, Time, Value, Intensity)]

# >PLOT: HR per Intensity Level ----
# change the category name for each arm value (1,2,3)
dt_hr_allIntensity_arm$arm <- as.factor(dt_hr_allIntensity_arm$arm)
# levels(dt_hr_allIntensity_arm$arm) outputs [1] "1" "2" "3"
# rename the factors corresponding levels:
levels(dt_hr_allIntensity_arm$arm) <- c("strength", "aerobic", "combination")

dt_hr_allIntensity_arm$Intensity <- as.factor(dt_hr_allIntensity_arm$Intensity)

# box plots take a long time to generate!
p <- ggplot(data = dt_hr_allIntensity_arm) +
  geom_boxplot(mapping = aes(x = Intensity, y = Value)) +
  xlab("Intensity Level") +
  ylab("Heart Rate")

# save_plot("HR_perIntensity_boxplot.png")

p + facet_grid(. ~ arm)

# save_plot("HR_perIntensity_perArm_boxplot.png")

# >PLOT: Delta Median HR between Highest and Lowest Intensity Level per Participant ----
# it is possible that some participants never have an intensity value in the highest/lowest 
# intensity category and therefore are not included in the following tables

medianHR_highIntensity_perId <- dt_hr_allIntensity_arm[Intensity == "3", .(medianHR_high = median(Value)), by = .(arm, Id)]
medianHR_lowIntensity_perId <- dt_hr_allIntensity_arm[Intensity == "0", .(medianHR_low = median(Value)), by = .(arm, Id)]

# inner join
setkey(medianHR_highIntensity_perId, Id)
setkey(medianHR_lowIntensity_perId, Id)
deltaHR_perId <- medianHR_highIntensity_perId[medianHR_lowIntensity_perId, nomatch = 0]
deltaHR_perId[, deltaHR := (medianHR_high - medianHR_low)]

# >PLOT: Delta Median HR between Highest and Lowest Intensity Level ----

# delta median HR for the strength arm
p1 <- ggplot(data = deltaHR_perId[arm == "strength"]) +
  geom_bar(stat = "identity", mapping = aes(x = Id, y = deltaHR)) +
  theme(axis.text.x = element_text(angle = 90))

# delta median HR for the aerobic arm
p2 <- p1 %+% deltaHR_perId[arm == "aerobic"]
# delta median HR for the combination arm
p3 <- p1 %+% deltaHR_perId[arm == "combination"]

multiplot(p1, p2, p3, cols = 3)

# RHR as HR Values During Intensity Level 0 ----
# focus on (resting) HR during lowest intensity category (0: sedentary)
dt_hr_lowIntensity <- dt_hr_allIntensity_arm[Intensity == 0][, .(Id, arm, Time, Value)]
id_list <- dt_hr_lowIntensity$Id %>% unique()

# >PLOT: RHR (Intensity 0) per Second ----
# RHR (intensity 0) per second for **a few** participants
show_linePerGroup(dt_hr_lowIntensity[Id %in% id_list[1:5]], "Time", "Value", "Id") +
  xlab("Second") +
  ylab("Resting Heart Rate (Intensity 0)")

save_plot("RHR_intensity0_perSecond.png")

# tried to plot RHR per second for **all** participants, 
# but ggplot did not manage to produce an output
# (the number of per second observations is nrow(dt_hr_lowIntensity) = 18,068,475!)

# create a column that indicates the day of each measurement
dt_hr_lowIntensity[, day := as.Date(Time)]

# create a column that indicates the daily lower/first quartile for each person


# >PLOT: minimum RHR (intensity 0) per day per arm ----
show_linePerGroup(dt_hr_lowIntensity[, .(minHR_day = min(Value)), by = .(arm, Id, day)], "day", "minHR_day", "Id") +
  facet_grid(. ~ arm) +
  scale_color_manual(values = colorRampPalette(brewer.pal(12, "Paired"))(length(id_list))) +
  xlab("Day") +
  ylab("Minimum Resting Heart Rate (Intensity 0)")

save_plot("minRHR_intensity0_perDay_perArm.png")

# >PLOT: lower quartile RHR (intensity 0) per day per arm ----
show_linePerGroup(dt_hr_lowIntensity[, .(quart1HR_day = quantile(Value)[2]), by = .(arm, Id, day)], "day", "quart1HR_day", "Id") +
  facet_grid(. ~ arm) +
  scale_color_manual(values = colorRampPalette(brewer.pal(12, "Paired"))(length(id_list))) +
  xlab("Day") +
  ylab("Lower Quartile Resting Heart Rate (Intensity 0)")

save_plot("quart1RHR_intensity0_perDay_perArm.png")


