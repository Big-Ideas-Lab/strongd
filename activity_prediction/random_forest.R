# tutorials used:
# caret: https://www.analyticsvidhya.com/blog/2016/12/practical-guide-to-implement-machine-learning-with-caret-package-in-r-with-practice-problem/
# ranger: https://uc-r.github.io/random_forests
# http://www.rebeccabarter.com/blog/2017-11-17-caret_tutorial/

source("utils.R")
load("RData_intermediate/dt_features.RData")

# reproducibility
set.seed(0)

# remove the 3rd category (combination of strength and aerobic exercises)
dt_features <- dt_features[Activity != 3]

# different sets of features
Steps_features <- colnames(dt_features)[startsWith(colnames(dt_features), "Steps_")]

HR_features <- colnames(dt_features)[startsWith(colnames(dt_features), "HR_")]
HR_features <- HR_features[HR_features != "HR_sd_minus_RHR_sd"]

RHR_features <- colnames(dt_features)[startsWith(colnames(dt_features), "HRminusRHR_")] %>% c("HR_sd_minus_RHR_sd")

Steps_HR_features <- c(Steps_features, HR_features)
Steps_RHR_features <- c(Steps_features, RHR_features)

# label
dt_features$Activity <- dt_features$Activity %>% as.factor()
label_name <- "Activity"

# train/validation-test split with respect to participants
id_list <- dt_features$Id %>% unique()
train_validate_ids <- sample(id_list, ceiling(0.8*length(id_list)))
test_ids <- setdiff(id_list, train_validate_ids)
save(test_ids, file = "test_ids.RData")

# train-validation split with respect to participants
train_ids <- sample(train_validate_ids, ceiling(0.6*length(id_list)))
save(train_ids, file = "train_ids.RData")
validate_ids <- setdiff(train_validate_ids, train_ids)

# standardize and impute missing values (with the median) per participant
dt_preprocessed <- copy(dt_features)
for (id in id_list) {
  preprocessing <- preProcess(dt_features[Id == id], method = c("center", "scale", "medianImpute"))
  dt_preprocessed[Id == id] <- data.table(predict(preprocessing, newdata = dt_features[Id == id]))
}

train <- dt_preprocessed[Id %in% train_ids]
save(train, file = "train.RData")
validate <- dt_preprocessed[Id %in% validate_ids]
test <- dt_preprocessed[Id %in% test_ids]
save(test, file = "test.RData")
feature_sets <- list(Steps_features, Steps_HR_features, Steps_RHR_features)
names <- c("Steps_features", "Steps_HR_features", "Steps_RHR_features")
for (i in 1:length(feature_sets)) {
  feature_set <- feature_sets[[i]]
  name <- names[i]
  
  # hyperparameter search grid
  grid <- expand.grid(
    num_trees = seq(200, 1000, by = 200),
    max_depth = seq(20, 100, by = 20),
    sample_size = c(0.632, 1),
    validation_acc = 0,
    validation_meanF1 = 0,
    validation_F1_0 = 0,
    validation_F1_1 = 0,
    validation_F1_2 = 0
  )
  
  # small grid for testing this function
  # grid <- expand.grid(
  #   num_trees = c(100, 200),
  #   max_depth = c(10, 20),
  #   sample_size = c(0.632, 1),
  #   validation_acc = 0,
  #   validation_meanF1 = 0,
  #   validation_F1_0 = 0,
  #   validation_F1_1 = 0,
  #   validation_F1_2 = 0
  # )
  
  # list for saving confusion matrices
  confMats <- list()
  
  # progress bar
  pb <- txtProgressBar(min = 1, max = nrow(grid), style = 3)
  for(i in 1:nrow(grid)) {
    # random forest model
    rf <- ranger(
      formula = Activity ~ ., 
      data = train[, c(feature_set, "Activity"), with = FALSE], 
      num.trees = grid$num_trees[i],
      max.depth = grid$max_depth[i],
      sample.fraction = grid$sample_size[i],
      importance = "impurity",
      verbose = TRUE,
      oob.error = FALSE
    )
    
    # rf <- ranger(
    #   formula = Activity ~ ., 
    #   data = train[, c(feature_set_1, "Activity"), with = FALSE], 
    #   num.trees = grid$num_trees[1],
    #   max.depth = grid$max_depth[1],
    #   sample.fraction = grid$sample_size[1],
    #   importance = "impurity",
    #   verbose = TRUE
    # )
    
    pred <- predict(rf, validate)
    confMat <- confusionMatrix(pred$predictions, validate$Activity, mode = 'everything')
    
    confMats[[i]] <- confMat
    grid$validation_acc[i] <- confMat$overall["Accuracy"]
    grid$validation_meanF1[i] <- mean(confMat$byClass[, "F1"])
    grid$validation_F1_0[i] <- confMat$byClass[1, "F1"]
    grid$validation_F1_1[i] <- confMat$byClass[2, "F1"]
    grid$validation_F1_2[i] <- confMat$byClass[3, "F1"]
    
    # progress bar
    setTxtProgressBar(pb, i)
  }
  close(pb)
  
  save(grid, file = paste(name, "grid.RData", sep = "_"))
  save(confMats, file = paste(name, "confMats.RData", sep = "_"))
}
