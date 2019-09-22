source("utils.R")
load("Steps_features_grid.RData")
Steps_grid <- copy(grid)
load("Steps_HR_features_grid.RData")
Steps_HR_grid <- copy(grid)
load("Steps_RHR_features_grid.RData")
Steps_RHR_grid <- copy(grid)

Steps_grid[which.max(Steps_grid$validation_acc),]
Steps_HR_grid[which.max(Steps_HR_grid$validation_acc),]  # row 14
Steps_RHR_grid[which.max(Steps_RHR_grid$validation_acc),]  # row 13

Steps_grid[which.max(Steps_grid$validation_meanF1),]  # row 2
Steps_HR_grid[which.max(Steps_HR_grid$validation_meanF1),]  # row 14
Steps_RHR_grid[which.max(Steps_RHR_grid$validation_meanF1),]  # row 13

load("train.RData")
# different sets of features
Steps_features <- colnames(train)[startsWith(colnames(train), "Steps_")]

HR_features <- colnames(train)[startsWith(colnames(train), "HR_")]
HR_features <- HR_features[HR_features != "HR_sd_minus_RHR_sd"]

RHR_features <- colnames(train)[startsWith(colnames(train), "HRminusRHR_")] %>% c("HR_sd_minus_RHR_sd")

Steps_HR_features <- c(Steps_features, HR_features)
Steps_RHR_features <- c(Steps_features, RHR_features)

# Steps_grid row 2
Steps_rf <- ranger(
  formula = Activity ~ ., 
  data = train[, c(Steps_features, "Activity"), with = FALSE], 
  num.trees = 400,
  max.depth = 20,
  sample.fraction = 0.632,
  importance = "impurity",
  verbose = TRUE,
  oob.error = FALSE
)

# Steps_HR_grid row 14
Steps_HR_rf <- ranger(
  formula = Activity ~ ., 
  data = train[, c(Steps_HR_features, "Activity"), with = FALSE], 
  num.trees = 800,
  max.depth = 60,
  sample.fraction = 0.632,
  importance = "impurity",
  verbose = TRUE,
  oob.error = FALSE
)

# Steps_RHR_grid row 13
Steps_RHR_rf <- ranger(
  formula = Activity ~ ., 
  data = train[, c(Steps_RHR_features, "Activity"), with = FALSE], 
  num.trees = 600,
  max.depth = 60,
  sample.fraction = 0.632,
  importance = "impurity",
  verbose = TRUE,
  oob.error = FALSE
)

load("test.RData")
Steps_pred <- predict(Steps_rf, test)
Steps_confMat <- confusionMatrix(Steps_pred$predictions, test$Activity, mode = 'everything')
Steps_confMat$overall["Accuracy"]
mean(Steps_confMat$byClass[, "F1"])

Steps_HR_pred <- predict(Steps_HR_rf, test)
Steps_HR_confMat <- confusionMatrix(Steps_HR_pred$predictions, test$Activity, mode = 'everything')
Steps_HR_confMat$overall["Accuracy"]
mean(Steps_HR_confMat$byClass[, "F1"])

Steps_RHR_pred <- predict(Steps_RHR_rf, test)
Steps_RHR_confMat <- confusionMatrix(Steps_RHR_pred$predictions, test$Activity, mode = 'everything')
Steps_RHR_confMat$overall["Accuracy"]
mean(Steps_RHR_confMat$byClass[, "F1"])

Steps_RHR_rf$variable.importance[order(-Steps_RHR_rf$variable.importance)] %>% as.data.frame()

F1_df <- rbind(Steps_confMat$byClass[, "F1"], Steps_HR_confMat$byClass[, "F1"], Steps_RHR_confMat$byClass[, "F1"])
rownames(F1_df) <- c("Steps", "Steps and HR", "Steps and RHR")
colnames(F1_df) <- c("daily activity", "strength", "aerobic")

png(filename = "F1.png", width = 8, height = 4, units = "in", res = 500)
F1_df %>% 
  as.matrix() %>%
  t() %>%
  barplot(beside = TRUE, 
          main = "F1 Scores for Each Feature Set",
          xlab = "Feature Set", 
          ylab = "F1 Score",
          ylim=c(0, 1),
          col = gray.colors(length(colnames(F1_df))))

legend("topright",
       legend = colnames(F1_df),
       cex = 0.75,
       fill = gray.colors(length(colnames(F1_df))))
dev.off()

accuracy_df <- rbind(Steps_confMat$overall["Accuracy"], Steps_HR_confMat$overall["Accuracy"], Steps_RHR_confMat$overall["Accuracy"])
rownames(accuracy_df) <- c("Steps", "Steps and HR", "Steps and RHR")

png(filename = "accuracy.png", width = 8, height = 4, units = "in", res = 500)
accuracy_df %>% 
  as.matrix() %>%
  t() %>%
  barplot(beside = TRUE, 
          main = "Overall Accuracy for Each Feature Set",
          xlab = "Feature Set", 
          ylab = "Accuracy",
          ylim=c(0, 1),
          col = gray.colors(length(colnames(accuracy_df))))
dev.off()

       