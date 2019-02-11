# Goal: Investigate how physical activity (PA) activity changes over time during course of study.
# PA is represented by number of steps

# Tip: use RStudio's document outline for navigating this file

# Import ----
# contains commonly used functions and libraries
source("../utils_custom.R")

# Load Cleaned Data ----
# see the cleaning directory for details of how this data was cleaned

load("../cleaning/RData_clean/dt_steps.RData")
load("../cleaning/RData_clean/dt_arm_simple.RData")
load("../cleaning/RData_clean/dt_login_arm.RData")

steps_id_list <- dt_steps_perMin$Id %>% unique()

# Initial joins ----
# setup for join on id
dt_steps_perMin[, join_id := Id]
dt_arm_simple[, join_id := id]
setkey(dt_steps_perMin, join_id)
setkey(dt_arm_simple, join_id)

# right outer join (include all measurements from dt_steps_perMin) 
# to get the corresponding study arm for each participant in dt_steps_perMin
join_steps_arm <- dt_arm_simple[dt_steps_perMin]
dt_steps_arm <- join_steps_arm[, .(Id, arm, Steps, ActivityMin)]

# # change the category name for each arm value (1,2,3)
# dt_steps_arm$arm <- as.factor(dt_steps_arm$arm)
# # levels(dt_steps_arm$arm) outputs [1] "1" "2" "3"
# # rename the factors corresponding levels:
# levels(dt_steps_arm$arm) <- c("strength", "aerobic", "combination")

# Plots for each participant ----
arm_color <- colorRampPalette(brewer.pal(3, "Accent"))(3)
arm_folder <- c("strength", "aerobic", "combo")

set.seed(0)
id_strength_sample <- sample(id_strength, 3)
id_aerobic_sample <- sample(id_aerobic, 3)
id_combo_sample <- sample(id_combo, 3)

save_plots_perId <- function(participant_list, first_month=FALSE) {
  for (participant in participant_list) {
    arm <- dt_arm_simple[id == participant]$arm
    
    # if (first_month == TRUE) {
    #   # only plot the participant's first month in the study
    #   start_time <- dt_steps_arm[Id == participant]$ActivityMin %>% min()
    #   end_time <- start_time + 60*60*24*30  # 1 month ~= 30 days
    #   dt_plotting <- dt_steps_arm[Id == participant & ActivityMin >= start_time & ActivityMin <= end_time]
    # } else {
      # # plot over the full length of the participant's involvement in the study
      # start_time <- dt_steps_arm[Id == participant]$ActivityMin %>% min()
      # end_time <- dt_steps_arm[Id == participant]$ActivityMin %>% max()  # 1 month ~= 30 days
    dt_plotting <- dt_steps_arm[Id == participant]
    # }
    
    # plot
    show_linePerGroup(dt_plotting, "ActivityMin", "Steps", "Id") +
      scale_color_manual(values = arm_color[arm]) +
      theme(plot.title = element_text(hjust = 0.5)) +
      labs(title = sprintf("%s (%s): Steps over Time", participant, arm_folder[arm]),
           x = "Minutes",
           y = "Number of Steps") +
      scale_y_continuous(expand = c(0, 0), limits = c(0, 260)) +  # dt_steps_arm$Steps %>% max() gives 255
      geom_rect(data = dt_login_arm[Id == participant],
                aes(xmin = Date, xmax = Date + 60*60*24, ymin = 0, ymax = 260), linetype = "blank", alpha = 0.2)
    
    # save plot
    filename <- sprintf("%s_arm=%s_firstMonth=%s_steps.png", participant, arm, as.character(first_month))
    print(filename)
    ggsave(filename, path = sprintf("plots/%s/", arm_folder[arm]), width = 8, height = 6, units = "in")
  }  
}

save_plots_perId(steps_id_list)
save_plots_perId(steps_id_list, first_month = TRUE)


# Aggregate plots per study arm ----

# TODO: sum for each day

dt_steps_arm[, Date := as.Date(ActivityMin)]
dt_mean_steps <- dt_steps_arm[, .(MeanSteps = mean(Steps)), by=.(Id, Date)]
# join to get login times and study arm
dt_mean_steps[, join_id := Id]
setkey(dt_mean_steps, join_id)
join_meanSteps_arm <- dt_arm_simple[dt_mean_steps]
dt_meanSteps_arm <- join_meanSteps_arm[, .(Id, arm, MeanSteps, Date)]

# join to get mean number of steps on the login days
dt_login_arm[, join_id := Id]
dt_login_arm[, join_date := as.Date(Date)]
setkey(dt_login_arm, join_id, join_date)
dt_mean_steps[, join_date := Date]
setkey(dt_mean_steps, join_id, join_date)
join_login_meanSteps <- dt_mean_steps[dt_login_arm]
dt_login_meanSteps <- join_login_meanSteps[!is.na(MeanSteps), .(Id, Date, MeanSteps, Arm)]

for (arm_num in 1:3) {
  dt_line <- dt_meanSteps_arm[arm == arm_num]
  dt_dot <- dt_login_meanSteps[Arm == arm_num]
  arm_id_list <- dt_line$Id %>% unique()
  # plot
  # note: login days without corresponding mean step values are not plotted
  show_linePerGroup(dt_line, "Date", "MeanSteps", "Id") +
    geom_point(data = dt_dot, mapping = aes(x = Date, y = MeanSteps, color = Id)) +
    scale_color_manual(values = colorRampPalette(brewer.pal(12, "Paired"))(length(arm_id_list))) +
    theme(plot.title = element_text(hjust = 0.5)) +
    labs(title = sprintf("%s Arm: Daily Mean Steps per Minute", toTitleCase(arm_folder[arm_num])),
         x = "Day",
         y = "Mean Number of Steps per Minute") +
    scale_y_continuous(expand = c(0, 0), limits = c(0, max(dt_meanSteps_arm$MeanSteps) + 1))
  
  # save plot
  filename <- sprintf("arm=%s_meanSteps.png", arm_num)
  print(filename)
  ggsave(filename, path = sprintf("plots/%s/", arm_folder[arm_num]), width = 18, height = 6, units = "in")
}

for (arm_num in 1:3) {
  print(arm_num)
  dt_line <- dt_meanSteps_arm[arm == arm_num]
  dt_dot <- dt_login_meanSteps[Arm == arm_num]
  dt_line$Id %>% unique() %>% length() %>% print()
  dt_dot$Id %>% unique() %>% length() %>% print()
  print(dt_meanSteps_arm[arm == arm_num, .N, by=Id]$N %>% mean())
}


# for (arm_num in 1:3) {
#   dt_plotting <- dt_steps_arm[arm == arm_num]
#   # plot
#   show_linePerGroup(dt_plotting, "ActivityMin", "Steps", "Id") +
#     # scale_color_manual(values = arm_color[arm]) +
#     theme(plot.title = element_text(hjust = 0.5)) +
#     labs(title = sprintf("%s (%s): Steps over Time", participant, arm_folder[arm]),
#          x = "Minutes",
#          y = "Number of Steps") +
#     scale_y_continuous(expand = c(0, 0), limits = c(0, 260)) +  # dt_steps_arm$Steps %>% max() gives 255
#     geom_rect(data = dt_login_arm[Id == participant],
#               aes(xmin = Date, xmax = Date + 60*60*24, ymin = 0, ymax = 260), linetype = "blank", alpha = 0.2)
# }
