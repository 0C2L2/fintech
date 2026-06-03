# ============================================
# Savings Prediction Module
# ============================================

#' Predict next month's savings
#' @param features Named list from build_feature_vector()
#' @param user_id User's UUID
#' @return Numeric: predicted savings amount
predict_savings <- function(features, user_id) {
  cat("\n--- Savings Prediction ---\n")
  cat("  User:", user_id, "\n")
  # Try loading saved Random Forest model
  model_path <- file.path(dirname(getwd()), "backend-r", "models", "rf_savings_model.rds")
  
  if (file.exists(model_path)) {
    tryCatch({
      library(randomForest)
      
      # readRDS() loads a single R object from a saved file on disk.
      # This loads the exact Random Forest model we built in train_prediction.R
      model <- readRDS(model_path)
      
      # We create a new single-row dataframe containing the features for THIS specific user.
      # The columns must perfectly match the spelling and order of the dataframe used to train the model.
      new_data <- data.frame(
        Income = features$income,
        total_expense = features$total_expense,
        rent_share = features$rent_share,
        loan_repayment_share = features$loan_repayment_share,
        insurance_share = features$insurance_share,
        groceries_share = features$groceries_share,
        transport_share = features$transport_share,
        eating_out_share = features$eating_out_share,
        entertainment_share = features$entertainment_share,
        utilities_share = features$utilities_share,
        healthcare_share = features$healthcare_share,
        education_share = features$education_share,
        miscellaneous_share = features$miscellaneous_share,
        savings_rate = features$savings_rate,
        expense_growth = features$expense_growth,
        avg_savings_last_3m = features$avg_savings_last_3m
      )
      
      # predict() feeds our single-row new_data into the loaded Random Forest model.
      # It drops the data through all 100 decision trees and averages their outputs to get the final predicted savings.
      predicted <- predict(model, new_data)
      cat("  RF model loaded successfully\n")
      cat("  Input: Income=", features$income, "| Expense=", features$total_expense,
          "| Savings rate=", round(features$savings_rate * 100, 1), "%\n")
      cat("  Predicted next month savings: $", round(as.numeric(predicted), 2), "\n")
      cat("--- Done ---\n")
      return(round(as.numeric(predicted), 2))
    }, error = function(e) {
      cat("  RF model error, falling back to simple prediction\n")
      message("RF prediction error, falling back to simple: ", e$message)
      return(simple_predict_savings(features, user_id))
    })
  } else {
    cat("  No RF model found, using simple prediction\n")
    return(simple_predict_savings(features, user_id))
  }
}

#' Simple savings prediction fallback (linear trend)
#' @param features Named list from build_feature_vector()
#' @param user_id User's UUID
#' @return Numeric: predicted savings amount
simple_predict_savings <- function(features, user_id) {
  cat("  Using simple linear trend prediction\n")
  # Get last 6 months of savings
  history <- db_query(
    "SELECT month, total_savings FROM monthly_snapshots 
     WHERE user_id = ? ORDER BY month DESC LIMIT 6",
    params = list(user_id)
  )
  
  if (nrow(history) < 2) {
    # Not enough history - use current savings or income-based estimate
    if (features$income > 0) {
      estimated <- features$income - features$total_expense
      return(round(max(estimated, 0), 2))
    }
    return(round(features$total_savings, 2))
  }
  
  # Simple linear regression on time
  history$t <- rev(seq_len(nrow(history)))
  model <- lm(total_savings ~ t, data = history)
  next_t <- max(history$t) + 1
  predicted <- predict(model, newdata = data.frame(t = next_t))
  
  return(round(max(as.numeric(predicted), 0), 2))
}

# ============================================
# Diagnostic Plot: Savings Trend + Prediction
# Call this in RStudio to visualize historical
# savings and the predicted next month value.
# Example: plot_savings_trend(user_id, predicted_value)
# ============================================
plot_savings_trend <- function(user_id, predicted_savings) {
  library(ggplot2)
  library(plotly)
  
  cat("\n--- Plotting: Savings Trend + Prediction ---\n")
  
  # Get historical savings
  history <- db_query(
    "SELECT month, income, total_expense FROM monthly_snapshots 
     WHERE user_id = ? ORDER BY month ASC",
    params = list(user_id)
  )
  
  if (nrow(history) < 2) {
    cat("Not enough history to plot (need at least 2 months)\n")
    return(invisible(NULL))
  }
  
  history$actual_savings <- history$income - history$total_expense
  
  # Add the predicted point
  last_month <- max(history$month)
  next_month <- format(as.Date(last_month) + 30, "%Y-%m-01")
  
  plot_df <- data.frame(
    Month = c(history$month, next_month),
    Savings = c(history$actual_savings, predicted_savings),
    Type = c(rep("Actual", nrow(history)), "Predicted")
  )
  plot_df$Month <- as.Date(plot_df$Month)
  
  p <- ggplot(plot_df, aes(x = Month, y = Savings, color = Type)) +
    geom_line(data = plot_df[plot_df$Type == "Actual", ], linewidth = 1) +
    geom_point(size = 3) +
    geom_point(data = plot_df[plot_df$Type == "Predicted", ],
               shape = 18, size = 5, color = "#ef4444") +
    scale_y_continuous(labels = function(x) paste0(x / 1000, "K")) +
    scale_color_manual(values = c("Actual" = "#4f46e5", "Predicted" = "#ef4444")) +
    labs(
      title = "Monthly Savings Trend + Next Month Prediction",
      subtitle = paste("User:", substr(user_id, 1, 8), "... | Predicted: $",
                       round(predicted_savings, 0)),
      x = "Month", y = "Savings"
    ) +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold"))
  
  print(ggplotly(p))
  cat("Plot displayed in Viewer\n")
  return(invisible(p))
}

# ============================================
# Diagnostic Plot: Feature Importance for a single prediction
# Shows which features had the highest values for this user
# Example: plot_prediction_inputs(features)
# ============================================
plot_prediction_inputs <- function(features) {
  library(ggplot2)
  library(plotly)
  
  cat("\n--- Plotting: Prediction Input Features ---\n")
  
  predictors <- c("Income", "total_expense", "rent_share", "loan_repayment_share",
                   "insurance_share", "groceries_share", "transport_share",
                   "eating_out_share", "entertainment_share", "utilities_share",
                   "healthcare_share", "education_share", "miscellaneous_share",
                   "savings_rate", "expense_growth", "avg_savings_last_3m")
  
  # Map to feature list names (lowercase)
  feat_keys <- c("income", "total_expense", "rent_share", "loan_repayment_share",
                  "insurance_share", "groceries_share", "transport_share",
                  "eating_out_share", "entertainment_share", "utilities_share",
                  "healthcare_share", "education_share", "miscellaneous_share",
                  "savings_rate", "expense_growth", "avg_savings_last_3m")
  
  vals <- sapply(feat_keys, function(k) as.numeric(features[[k]]))
  
  df <- data.frame(
    Feature = gsub("_", " ", predictors),
    Value = vals,
    stringsAsFactors = FALSE
  )
  df <- df[order(abs(df$Value), decreasing = TRUE), ]
  df$Feature <- factor(df$Feature, levels = rev(df$Feature))
  
  p <- ggplot(df, aes(x = Feature, y = Value, fill = Value)) +
    geom_bar(stat = "identity", alpha = 0.9, show.legend = FALSE) +
    coord_flip() +
    scale_fill_gradient2(low = "#ef4444", mid = "#e2e8f0", high = "#4f46e5", midpoint = 0) +
    labs(
      title = "Prediction Input Features (This User)",
      subtitle = "Feature values fed into the Random Forest model",
      x = "Feature", y = "Value"
    ) +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold"))
  
  print(ggplotly(p))
  cat("Plot displayed in Viewer\n")
  return(invisible(p))
}
