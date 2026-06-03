# -----------------------------------------------
# train_prediction.R
# This script trains a Random Forest model to
# predict how much a user will save next month.
# Run preprocess_data.R first before this!
# -----------------------------------------------

library(randomForest)
library(ggplot2)
library(plotly) # for interactive plots you can zoom/pan/hover

# -----------------------------------------------
# Step 0: Set working directory
# -----------------------------------------------
current_dir <- getwd()

if (basename(current_dir) == "scripts") {
  setwd(dirname(current_dir))
} else if (dir.exists("backend-r")) {
  setwd(file.path(current_dir, "backend-r"))
}

cat("Working directory is:", getwd(), "\n")


# -----------------------------------------------
# Step 1: Load the preprocessed data
# -----------------------------------------------
cat("\n=== Training Random Forest Savings Prediction ===\n")

features_csv <- file.path("data", "kaggle_preprocessed_features.csv")

if (!file.exists(features_csv)) {
  stop("File not found! Please run preprocess_data.R first.")
}

data_df <- read.csv(features_csv, stringsAsFactors = FALSE)
cat("Loaded", nrow(data_df), "rows\n")

cat("\n--- First 3 rows ---\n")
print(head(data_df, 3))

cat("\n--- Missing values check ---\n")
print(colSums(is.na(data_df)))


# -----------------------------------------------
# Step 2: List the 16 predictors (features)
# These are the columns we feed into the model
# -----------------------------------------------
cat("\n--- The 16 features we use to predict next month savings ---\n")

predictors <- c(
  "Income",
  "total_expense",
  "rent_share",
  "loan_repayment_share",
  "insurance_share",
  "groceries_share",
  "transport_share",
  "eating_out_share",
  "entertainment_share",
  "utilities_share",
  "healthcare_share",
  "education_share",
  "miscellaneous_share",
  "savings_rate",
  "expense_growth",
  "avg_savings_last_3m"
)

for (i in seq_along(predictors)) {
  cat(" ", i, ".", predictors[i], "\n")
}

# Target we are trying to predict
target <- "next_month_savings"


# -----------------------------------------------
# Step 3: Check correlation between each feature and target
# This tells us which features are most related to savings
# -----------------------------------------------
cat("\n--- Correlation of each feature with next_month_savings ---\n")
cat("(closer to +1 or -1 = stronger relationship)\n\n")

for (pred in predictors) {
  vals <- data_df[[pred]]
  target_vals <- data_df[[target]]

  # Only compute where both values exist
  good_rows <- !is.na(vals) & !is.na(target_vals)

  if (sum(good_rows) > 10) {
    r <- cor(vals[good_rows], target_vals[good_rows])
    cat(" ", pred, "-> r =", round(r, 3), "\n")
  }
}


# -----------------------------------------------
# Step 4: Remove rows where target is NA
# The last month per user has no "next month" yet
# -----------------------------------------------
cat("\n--- Filtering rows ---\n")
cat("Rows before filter:", nrow(data_df), "\n")

train_subset <- data_df[!is.na(data_df[[target]]), ]
cat("Rows after removing NA target:", nrow(train_subset), "\n")


# -----------------------------------------------
# Step 5: Sample 15,000 rows if data is too large
# Random Forest is slow on very large datasets
# -----------------------------------------------
set.seed(42)

if (nrow(train_subset) > 15000) {
  cat("Dataset is large, sampling 15,000 rows for speed...\n")
  sample_rows <- sample(nrow(train_subset), 15000)
  train_subset <- train_subset[sample_rows, ]
  cat("Sampled down to:", nrow(train_subset), "rows\n")
}


# -----------------------------------------------
# Step 6: Split into training and testing sets (80/20)
# Training set: model learns from this
# Test set: we check how good the model is on new data
# -----------------------------------------------
cat("\nSplitting data 80% train / 20% test...\n")

# nrow() gets the total number of rows in the dataset.
n <- nrow(train_subset)

# sample() randomly picks a set of row numbers. We ask for 80% of the total rows.
# floor() rounds down to the nearest whole number (e.g. 80.5 -> 80)
train_rows <- sample(n, size = floor(0.8 * n))

# We use the selected row numbers to pull the training data.
train_data <- train_subset[train_rows, ]

# The minus sign [-train_rows, ] tells R to pull every row EXCEPT the training rows. This becomes our test set.
test_data <- train_subset[-train_rows, ]

cat("Training rows:", nrow(train_data), "\n")
cat("Testing rows: ", nrow(test_data), "\n")

cat("\nTarget column stats:\n")
cat(
  "  Train -> mean: $", round(mean(train_data[[target]]), 0),
  " | sd: $", round(sd(train_data[[target]]), 0), "\n"
)
cat(
  "  Test  -> mean: $", round(mean(test_data[[target]]), 0),
  " | sd: $", round(sd(test_data[[target]]), 0), "\n"
)


# -----------------------------------------------
# Step 7: Train the Random Forest model
# ntree = 100 trees, mtry = 5 features per split
# importance = TRUE so we can check feature importance after
# -----------------------------------------------
cat("\nTraining Random Forest (100 trees)... this might take a minute\n")

# as.formula() converts a string into a mathematical formula object in R.
# The formula looks like: target_variable ~ predictor1 + predictor2 + ...
# We use paste() to dynamically build this string instead of typing all 16 features manually.
model_formula <- as.formula(
  paste(target, "~", paste(predictors, collapse = " + "))
)

# randomForest() builds an ensemble of decision trees.
# - formula: defines what we are predicting and what data we are using to predict it
# - data: the training set
# - ntree = 100: builds 100 separate decision trees (more trees = more stable, but slower)
# - mtry = 5: at each split in a tree, it randomly considers 5 features to avoid relying too heavily on any single feature
# - importance = TRUE: forces the algorithm to calculate how much each feature contributes to the prediction accuracy
rf_model <- randomForest(
  model_formula,
  data       = train_data,
  ntree      = 100,
  mtry       = 5,
  importance = TRUE
)

cat("Training done!\n")

cat("\n--- Model summary ---\n")
print(rf_model)


# -----------------------------------------------
# Step 8: Test the model on the test set
# -----------------------------------------------
cat("\nTesting model on test data...\n")

# predict() takes a trained model and feeds it new data (test_data).
# It outputs the model's guess for what the savings should be.
predictions <- predict(rf_model, test_data)

# We pull the ACTUAL savings from the test data so we can compare the model's guess to reality.
actual <- test_data[[target]]

# Calculate error metrics:
# RMSE (Root Mean Squared Error): Penalizes large errors heavily. Useful for finding outliers.
rmse <- sqrt(mean((predictions - actual)^2))

# MAE (Mean Absolute Error): The average off-by-X amount in dollars.
mae <- mean(abs(predictions - actual))

# R-squared: Explains how much of the variance in actual savings is explained by our model.
# 1.0 means perfect prediction. 0.0 means the model is as good as just guessing the average savings every time.
r_squared <- 1 - sum((actual - predictions)^2) / sum((actual - mean(actual))^2)

cat("\n--- Test Results ---\n")
cat("  R squared:", round(r_squared, 4), "  (1.0 = perfect, above 0.8 is good)\n")
cat("  RMSE:     $", round(rmse, 2), "  (average prediction error)\n")
cat("  MAE:      $", round(mae, 2), "  (average absolute error)\n")


# -----------------------------------------------
# Step 9: Print feature importance
# %IncMSE = how much worse the model gets if we remove this feature
# Higher = more important
# -----------------------------------------------
cat("\n--- Feature Importance (higher = more important) ---\n")

imp <- importance(rf_model)
imp_sorted <- sort(imp[, "%IncMSE"], decreasing = TRUE)

for (feat in names(imp_sorted)) {
  cat(" ", feat, "->", round(imp_sorted[feat], 2), "%IncMSE\n")
}


# -----------------------------------------------
# Step 10: Plot feature importance (bar chart)
# -----------------------------------------------
cat("\nMaking feature importance plot...\n")

imp_df <- data.frame(
  Feature = names(imp_sorted),
  Importance = as.numeric(imp_sorted),
  stringsAsFactors = FALSE
)

# Sort so the most important is at the top of the flipped bar chart
imp_df$Feature <- factor(imp_df$Feature, levels = imp_df$Feature[order(imp_df$Importance)])

p1 <- ggplot(imp_df, aes(x = Feature, y = Importance, fill = Importance)) +
  geom_bar(stat = "identity", alpha = 0.9, show.legend = FALSE) +
  coord_flip() +
  scale_fill_gradient(low = "#c7d2fe", high = "#4338ca") +
  labs(
    title = "Random Forest Feature Importance",
    subtitle = "Higher = more important for predicting next month savings",
    x = "Feature",
    y = "% Increase in MSE when removed"
  ) +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold", hjust = 0.5))

print(ggplotly(p1)) # interactive — zoom, hover over bars
dir.create("outputs", showWarnings = FALSE)
ggsave("outputs/rf_feature_importance.png", plot = p1, width = 8, height = 6)
cat("Saved: outputs/rf_feature_importance.png\n")


# -----------------------------------------------
# Step 11: Plot Actual vs Predicted
# Dots near the red line = good predictions
# -----------------------------------------------
cat("\nMaking actual vs predicted plot...\n")

# Cap outliers at 99th percentile so the scatter looks clean
savings_cap <- quantile(c(actual, predictions), 0.99)
plot_idx <- which(abs(actual) <= savings_cap & abs(predictions) <= savings_cap)

pred_df <- data.frame(
  Actual    = actual[plot_idx],
  Predicted = as.numeric(predictions[plot_idx])
)

p2 <- ggplot(pred_df, aes(x = Actual, y = Predicted)) +
  geom_point(alpha = 0.2, color = "#4f46e5", size = 1) +
  geom_abline(slope = 1, intercept = 0, color = "red", linetype = "dashed") +
  scale_x_continuous(labels = function(x) paste0(x / 1000, "K")) +
  scale_y_continuous(labels = function(x) paste0(x / 1000, "K")) +
  labs(
    title = "Actual vs Predicted Savings",
    subtitle = paste(
      "R2 =", round(r_squared, 3), "| RMSE = $", round(rmse, 0),
      "| Top 1% outliers excluded"
    ),
    x = "Actual Savings Next Month",
    y = "Predicted Savings Next Month"
  ) +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold", hjust = 0.5))

print(ggplotly(p2)) # interactive — hover to see exact values
ggsave("outputs/rf_actual_vs_predicted.png", plot = p2, width = 7, height = 6)
cat("Saved: outputs/rf_actual_vs_predicted.png\n")


# -----------------------------------------------
# Step 12: Save the trained model
# -----------------------------------------------
dir.create("models", showWarnings = FALSE)
saveRDS(rf_model, "models/rf_savings_model.rds")
cat("\nModel saved: models/rf_savings_model.rds\n")

cat("\n=== Prediction training done! ===\n")
