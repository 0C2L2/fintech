# -----------------------------------------------
# preprocess_data.R
# This script loads the raw CSV, cleans it,
# creates 6 months of history per user,
# calculates useful features, and saves the result.
# -----------------------------------------------

library(dplyr)
library(ggplot2)
library(tidyr)
library(plotly) # for interactive plots you can zoom/pan/hover

# -----------------------------------------------
# Step 0: Set working directory
# We need to be inside the backend-r folder
# -----------------------------------------------
current_dir <- getwd()

if (basename(current_dir) == "scripts") {
  setwd(dirname(current_dir))
} else if (dir.exists("backend-r")) {
  setwd(file.path(current_dir, "backend-r"))
}

cat("Working directory is:", getwd(), "\n")


# -----------------------------------------------
# Step 1: Load the CSV file
# -----------------------------------------------
csv_path <- "c:/Users/rashi/Desktop/finteach/data.csv"

cat("Loading CSV from:", csv_path, "\n")

if (!file.exists(csv_path)) {
  stop("ERROR: CSV file not found! Check the path above.")
}

df <- read.csv(csv_path, stringsAsFactors = FALSE)

cat("Loaded", nrow(df), "rows and", ncol(df), "columns\n")


# -----------------------------------------------
# Step 2: Look at the raw data
# -----------------------------------------------
cat("\n--- First look at the data ---\n")
print(head(df, 5))

cat("\n--- Column names ---\n")
print(colnames(df))

cat("\n--- Data types ---\n")
print(str(df))

cat("\n--- Missing values per column ---\n")
na_counts <- colSums(is.na(df))
print(na_counts)

cat("\n--- How many rows have at least one missing value? ---\n")
rows_with_na <- sum(!complete.cases(df))
cat(rows_with_na, "rows have missing values\n")

cat("\n--- Basic summary stats ---\n")
print(summary(df))


# -----------------------------------------------
# Step 3: Clean the data
# Fill NA with 0 and remove negative values
# -----------------------------------------------
cat("\nCleaning data...\n")

# Check for negatives before cleaning
cat("\n--- Negative values in numeric columns (before cleaning) ---\n")
num_cols <- names(df)[sapply(df, is.numeric)]
for (col in num_cols) {
  neg_count <- sum(df[[col]] < 0, na.rm = TRUE)
  if (neg_count > 0) {
    cat(" ", col, "has", neg_count, "negative values\n")
  }
}

# Fill NAs with 0
for (col in num_cols) {
  df[[col]][is.na(df[[col]])] <- 0
}

# Clamp negatives to 0 for money columns
money_cols <- c(
  "Income", "Rent", "Loan_Repayment", "Insurance", "Groceries",
  "Transport", "Eating_Out", "Entertainment", "Utilities",
  "Healthcare", "Education", "Miscellaneous", "Desired_Savings"
)

for (col in money_cols) {
  if (col %in% colnames(df)) {
    df[[col]] <- pmax(0, df[[col]])
  }
}

cat("Done. NAs filled with 0, negative money values set to 0\n")
cat("\n--- Missing values after cleaning ---\n")
print(colSums(is.na(df)))


# -----------------------------------------------
# Step 4: Simulate 6 months of history per user
# Each user gets 6 rows (one per month)
# with small random noise on variable expenses
# -----------------------------------------------
cat("\nSimulating 6 months of history for each user...\n")

n_users <- nrow(df)
n_months <- 6
cat(n_users)
# Repeat each row 6 times
ts_df <- df[rep(1:n_users, each = n_months), ]

# Add user identifiers
ts_df$user_id <- rep(paste0("kaggle_user_", 1:n_users), each = n_months)
ts_df$full_name <- rep(paste0("Kaggle User ", sprintf("%05d", 1:n_users)), each = n_months)
ts_df$email <- rep(paste0("kaggle_user_", 1:n_users, "@finhealth.com"), each = n_months)

# Create month labels (most recent first, then reverse to oldest first)
month_dates <- format(seq(Sys.Date(), length.out = n_months, by = "-1 month"), "%Y-%m-01")
month_dates <- rev(month_dates)
ts_df$month <- rep(month_dates, times = n_users)

cat("Month dates created:\n")
print(unique(ts_df$month))

# Add small random noise to variable expenses (5% standard deviation)
# Fixed costs like Rent and Insurance stay the same every month
variable_cols <- c(
  "Income", "Groceries", "Transport", "Eating_Out",
  "Entertainment", "Utilities", "Healthcare", "Miscellaneous"
)

set.seed(42)
for (col in variable_cols) {
  noise <- rnorm(nrow(ts_df), mean = 1.0, sd = 0.05)
  ts_df[[col]] <- pmax(0, round(ts_df[[col]] * noise, 2))
}

cat("Added noise. Total rows now:", nrow(ts_df), "\n")

cat("\n--- Sample of first user's 6 months ---\n")
first_user <- ts_df[ts_df$user_id == "kaggle_user_1", c("user_id", "month", "Income", "Rent", "Groceries")]
print(first_user)


# -----------------------------------------------
# Step 5: Calculate features
# total expenses, category shares, savings rate,
# month-over-month growth, rolling savings average,
# and next month savings (ML target)
# -----------------------------------------------
cat("\nCalculating features...\n")

# Total expense
ts_df$total_expense <- ts_df$Rent + ts_df$Loan_Repayment + ts_df$Insurance +
  ts_df$Groceries + ts_df$Transport + ts_df$Eating_Out + ts_df$Entertainment +
  ts_df$Utilities + ts_df$Healthcare + ts_df$Education + ts_df$Miscellaneous

# Actual savings this month
ts_df$actual_savings <- ts_df$Income - ts_df$total_expense

# Savings rate (what % of income is saved)
ts_df$savings_rate <- ifelse(ts_df$Income > 0, ts_df$actual_savings / ts_df$Income, 0)
ts_df$savings_rate <- pmax(-1, pmin(1, ts_df$savings_rate)) # clamp between -100% and +100%

# Category shares (what % of total expenses goes to each category)
ts_df$rent_share <- ifelse(ts_df$total_expense > 0, ts_df$Rent / ts_df$total_expense, 0)
ts_df$loan_repayment_share <- ifelse(ts_df$total_expense > 0, ts_df$Loan_Repayment / ts_df$total_expense, 0)
ts_df$insurance_share <- ifelse(ts_df$total_expense > 0, ts_df$Insurance / ts_df$total_expense, 0)
ts_df$groceries_share <- ifelse(ts_df$total_expense > 0, ts_df$Groceries / ts_df$total_expense, 0)
ts_df$transport_share <- ifelse(ts_df$total_expense > 0, ts_df$Transport / ts_df$total_expense, 0)
ts_df$eating_out_share <- ifelse(ts_df$total_expense > 0, ts_df$Eating_Out / ts_df$total_expense, 0)
ts_df$entertainment_share <- ifelse(ts_df$total_expense > 0, ts_df$Entertainment / ts_df$total_expense, 0)
ts_df$utilities_share <- ifelse(ts_df$total_expense > 0, ts_df$Utilities / ts_df$total_expense, 0)
ts_df$healthcare_share <- ifelse(ts_df$total_expense > 0, ts_df$Healthcare / ts_df$total_expense, 0)
ts_df$education_share <- ifelse(ts_df$total_expense > 0, ts_df$Education / ts_df$total_expense, 0)
ts_df$miscellaneous_share <- ifelse(ts_df$total_expense > 0, ts_df$Miscellaneous / ts_df$total_expense, 0)

cat("Category shares calculated\n")

# Check: print the shares to see if they look right
cat("\n--- Category shares for first 5 rows ---\n")
share_cols <- c(
  "rent_share", "loan_repayment_share", "insurance_share",
  "groceries_share", "transport_share", "eating_out_share",
  "entertainment_share", "utilities_share", "healthcare_share",
  "education_share", "miscellaneous_share"
)
print(round(head(ts_df[, share_cols], 5), 3))

cat("\n--- Summary of all category shares ---\n")
print(summary(ts_df[, share_cols]))


# Sort by user and month so lags work correctly
ts_df <- ts_df[order(ts_df$user_id, ts_df$month), ]

# Calculate lag features per user
# Using dplyr group_by + lag/lead (fast, vectorized — no slow for-loop)
cat("Calculating lag features (grouped by user)...\n")

ts_df <- ts_df %>%
  group_by(user_id) %>%
  mutate(
    # Previous month's expense (for growth calculation)
    prev_expense = lag(total_expense, 1),
    expense_growth = ifelse(!is.na(prev_expense) & prev_expense > 0,
      (total_expense - prev_expense) / prev_expense, 0
    ),

    # Previous savings values
    prev_savings_1 = lag(actual_savings, 1),
    prev_savings_2 = lag(actual_savings, 2),
    prev_savings_3 = lag(actual_savings, 3),

    # Rolling average of last 3 months savings
    avg_savings_last_3m = case_when(
      !is.na(prev_savings_1) & !is.na(prev_savings_2) & !is.na(prev_savings_3)
      ~ (prev_savings_1 + prev_savings_2 + prev_savings_3) / 3,
      !is.na(prev_savings_1) & !is.na(prev_savings_2)
      ~ (prev_savings_1 + prev_savings_2) / 2,
      !is.na(prev_savings_1) ~ prev_savings_1,
      TRUE ~ 0
    ),

    # Next month savings = the ML prediction target
    next_month_savings = lead(actual_savings, 1)
  ) %>%
  ungroup()

# Fix any NaN or Inf that can come from division
ts_df$expense_growth[is.nan(ts_df$expense_growth)] <- 0
ts_df$expense_growth[is.infinite(ts_df$expense_growth)] <- 0

cat("Lag features calculated\n")

cat("\n--- Feature engineering check ---\n")
cat("Dataset shape:", nrow(ts_df), "rows,", ncol(ts_df), "columns\n")
cat("\n--- Summary of key features ---\n")
print(summary(ts_df[, c("Income", "total_expense", "actual_savings", "savings_rate")]))
cat("\n--- NAs after feature engineering (from lag columns, this is normal) ---\n")
lag_nas <- colSums(is.na(ts_df))
print(lag_nas[lag_nas > 0])


# -----------------------------------------------
# Step 6: Save the processed data
# -----------------------------------------------
data_dir <- "data"
dir.create(data_dir, showWarnings = FALSE)

output_csv <- file.path(data_dir, "kaggle_preprocessed_features.csv")
write.csv(ts_df, output_csv, row.names = FALSE)
cat("\nSaved to:", output_csv, "\n")


# -----------------------------------------------
# Step 7: Make some plots to understand the data
# -----------------------------------------------
cat("\nMaking diagnostic plots...\n")

dir.create("outputs", showWarnings = FALSE)

# Use only the most recent month for distribution plots
latest_month <- max(ts_df$month)
current <- ts_df[ts_df$month == latest_month, ]
cat("Using latest month for plots:", latest_month, "(", nrow(current), "users )\n")

# Plot 1: Income histogram
# Cap at 99th percentile so extreme outliers don't crush the chart
income_cap <- quantile(current$Income, 0.99)
median_income <- median(current$Income)
cat("Income 99th percentile:", income_cap, " | Median:", median_income, "\n")

p1 <- ggplot(current[current$Income <= income_cap, ], aes(x = Income)) +
  geom_histogram(fill = "#4f46e5", color = "white", bins = 50, alpha = 0.85) +
  geom_vline(xintercept = median_income, color = "#ef4444", linetype = "dashed", linewidth = 0.8) +
  scale_x_continuous(labels = function(x) paste0(x / 1000, "K")) +
  labs(
    title = "Monthly Income Distribution",
    subtitle = paste(
      "Based on", nrow(current), "users | Red line = median |",
      "Top 1% outliers excluded for clarity"
    ),
    x = "Monthly Income",
    y = "Count"
  ) +
  theme_minimal()

print(ggplotly(p1)) # interactive plot — zoom, pan, hover in RStudio Viewer
ggsave("outputs/income_distribution.png", plot = p1, width = 8, height = 5)
cat("Saved: outputs/income_distribution.png\n")

# Plot 2: Savings rate density
p2 <- ggplot(current, aes(x = savings_rate)) +
  geom_density(fill = "#10b981", alpha = 0.5) +
  geom_vline(xintercept = 0, color = "red", linetype = "dashed") +
  labs(
    title = "Savings Rate Distribution",
    x = "Savings Rate (savings / income)",
    y = "Density"
  ) +
  theme_minimal()

print(ggplotly(p2)) # interactive plot
ggsave("outputs/savings_rate_distribution.png", plot = p2, width = 8, height = 5)
cat("Saved: outputs/savings_rate_distribution.png\n")

# Plot 3: Average spending by category (bar chart)
spend_cols <- c(
  "Rent", "Loan_Repayment", "Insurance", "Groceries", "Transport",
  "Eating_Out", "Entertainment", "Utilities", "Healthcare",
  "Education", "Miscellaneous"
)

avg_spend <- colMeans(current[, spend_cols])
avg_df <- data.frame(Category = names(avg_spend), Mean = as.numeric(avg_spend))
avg_df$Category <- gsub("_", " ", avg_df$Category)
avg_df <- avg_df[order(-avg_df$Mean), ]
avg_df$Category <- factor(avg_df$Category, levels = rev(avg_df$Category))

p3 <- ggplot(avg_df, aes(x = Category, y = Mean, fill = Mean)) +
  geom_bar(stat = "identity", alpha = 0.9, show.legend = FALSE) +
  coord_flip() +
  scale_fill_gradient(low = "#c7d2fe", high = "#4338ca") +
  labs(
    title = "Average Monthly Spending by Category",
    x = "Category",
    y = "Average Amount"
  ) +
  theme_minimal()

print(ggplotly(p3)) # interactive plot
ggsave("outputs/average_spending_breakdown.png", plot = p3, width = 8, height = 5)
cat("Saved: outputs/average_spending_breakdown.png\n")

# Plot 4: Feature correlation heatmap
cat("\nCalculating correlation between features...\n")
feature_cols <- c(
  "rent_share", "loan_repayment_share", "insurance_share",
  "groceries_share", "transport_share", "eating_out_share",
  "entertainment_share", "utilities_share", "healthcare_share",
  "education_share", "miscellaneous_share", "savings_rate"
)

cor_df <- na.omit(ts_df[, feature_cols])
cor_matrix <- cor(cor_df)

# Turn into long format for ggplot
cor_long <- as.data.frame(as.table(cor_matrix))
colnames(cor_long) <- c("Feature1", "Feature2", "Correlation")

p4 <- ggplot(cor_long, aes(x = Feature1, y = Feature2, fill = Correlation)) +
  geom_tile(color = "white") +
  scale_fill_gradient2(low = "#ef4444", mid = "white", high = "#10b981", midpoint = 0) +
  theme_minimal(base_size = 9) +
  labs(title = "Feature Correlation Heatmap") +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

print(ggplotly(p4)) # interactive plot
ggsave("outputs/feature_correlation_heatmap.png", plot = p4, width = 8, height = 7)
cat("Saved: outputs/feature_correlation_heatmap.png\n")

cat("\n=== Preprocessing done! ===\n")
