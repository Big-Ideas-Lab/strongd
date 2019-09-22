library(data.table)
library(magrittr)
library(ggplot2)
library(RColorBrewer)
library(zoo)
library(caret)
library(ranger)
library(xtable)


show_linePerGroup <- function(dt, x_colStr, y_colStr, group_colStr = NULL) {
  # returns a ggplot line plot (one line per unique value in the column with name group_colStr)
  
  # dt : data.table
  # x_colStr: name (character) of variable to plot on the x-axis
  # y_colStr: name (character) of variable to plot on the y-axis
  # group_colStr: name (character) of variable for which we want to plot one line per unique value
  
  plt <- 
    ggplot(data = dt) + 
    geom_line(mapping = aes_string(x = x_colStr, y = y_colStr, group = group_colStr, color = group_colStr)) +
    theme(legend.position = "none") 
  
  return(plt)
}