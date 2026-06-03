# ============================================
# Seeding Script: Kaggle Users & Time-Series History
# ============================================

# -----------------------------------------------
# Step 0: Set working directory
# We need to be inside the backend-r folder
# -----------------------------------------------
current_dir <- getwd()

if (basename(current_dir) == "scripts") {
  setwd(dirname(current_dir))
} else if (dir.exists("backend-r")) {
  setwd(file.path(current_dir, "backend-r"))
} else if (dir.exists("C:/Users/rashi/Desktop/finteach/backend-r")) {
  # Fallback if RStudio opened in Documents by default
  setwd("C:/Users/rashi/Desktop/finteach/backend-r")
}

cat("Working directory is:", getwd(), "\n")

source("R/db.R")
source("R/utils.R")
source("R/auth.R")
source("R/rules.R")
source("R/features.R")
source("R/clustering.R")
source("R/prediction.R")
source("R/overspending.R")
source("R/recommendations.R")

library(bcrypt)
library(jsonlite)

cat("=== Seeding Kaggle Users & Transactions ===\n\n")

# Recreate database to ensure clean schema
cat("Re-initializing SQLite database...\n")
if (file.exists(DB_PATH)) {
  file.remove(DB_PATH)
}
init_db()

# Load preprocessed Kaggle features CSV
features_csv <- file.path("data", "kaggle_preprocessed_features.csv")
if (!file.exists(features_csv)) {
  stop("Preprocessed Kaggle features file not found! Please run preprocess_data.R first.")
}

data_df <- read.csv(features_csv, stringsAsFactors = FALSE)
unique_users <- unique(data_df$user_id)
cat(sprintf("Loaded preprocessed dataset containing %d total users.\n", length(unique_users)))

# Quick look at the data we're seeding
cat("\n--- Dataset structure ---\n")
cat("Total rows:", nrow(data_df), "| Columns:", ncol(data_df), "\n")
cat("Months per user:", nrow(data_df) / length(unique_users), "\n")
cat("Column names:\n")
print(colnames(data_df))

# Seed first 100 users for the application UI
users_to_seed <- head(unique_users, 100)
pw_hash <- hashpw("password123")

# Map of CSV category names to DB category names
category_mapping <- list(
  Rent = "Rent",
  Loan_Repayment = "Loan Repayment",
  Insurance = "Insurance",
  Groceries = "Groceries",
  Transport = "Transport",
  Eating_Out = "Eating Out",
  Entertainment = "Entertainment",
  Utilities = "Utilities",
  Healthcare = "Healthcare",
  Education = "Education",
  Miscellaneous = "Miscellaneous"
)

cat("\n--- Category mapping (CSV column -> DB name) ---\n")
for (csv_name in names(category_mapping)) {
  cat("  ", csv_name, "->", category_mapping[[csv_name]], "\n")
}

cat("\nStarting seeding process (100 users)...\n")

# Track stats for final summary
all_scores <- c()
all_clusters <- c()
all_flag_counts <- c()

for (i in 1:length(users_to_seed)) {
  u_id <- users_to_seed[i]

  # Get user base demographic data from the first available record
  user_records <- data_df[data_df$user_id == u_id, ]
  user_records <- user_records[order(user_records$month), ] # Ascending order

  base_rec <- user_records[1, ]
  db_user_id <- new_uuid()

  # Insert user
  db_execute(
    "INSERT INTO users (id, full_name, email, password_hash, role, created_at, updated_at) VALUES (?, ?, ?, ?, 'user', datetime('now'), datetime('now'))",
    params = list(db_user_id, base_rec$full_name, base_rec$email, pw_hash)
  )

  # Seed categories for this user in DB
  seed_user_categories(db_user_id)

  # Retrieve created categories mapping (name -> ID)
  cats_df <- db_query("SELECT id, name FROM categories WHERE user_id = ?", params = list(db_user_id))

  # Loop through months (6 months of history)
  for (m_idx in 1:nrow(user_records)) {
    month_rec <- user_records[m_idx, ]
    month_str <- month_rec$month

    # Insert income record
    db_execute(
      "INSERT INTO income (id, user_id, amount, income_month, source, created_at, updated_at) VALUES (?, ?, ?, ?, 'Salary', datetime('now'), datetime('now'))",
      params = list(new_uuid(), db_user_id, month_rec$Income, month_str)
    )

    # Insert expense records for each of the 11 categories.
    # We iterate over the named list `category_mapping` where names are CSV columns and values are DB names.
    for (col_name in names(category_mapping)) {
      db_cat_name <- category_mapping[[col_name]]
      # Find the specific category ID from the DB that matches this user's category name.
      cat_id <- cats_df$id[tolower(cats_df$name) == tolower(db_cat_name)][1]
      amount <- month_rec[[col_name]]

      # db_execute() safely runs a parametrized SQL INSERT query.
      # The `?` placeholders are replaced by the variables in `params`, which prevents SQL injection attacks.
      db_execute(
        "INSERT INTO expenses (id, user_id, category_id, amount, expense_month, expense_type, created_at, updated_at) VALUES (?, ?, ?, ?, ?, 'expense', datetime('now'), datetime('now'))",
        params = list(new_uuid(), db_user_id, cat_id, amount, month_str)
      )
    }

    # Insert monthly snapshot summary (the total target savings and income for that month)
    db_execute(
      "INSERT INTO monthly_snapshots (id, user_id, month, income, total_expense, total_savings, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'))",
      params = list(new_uuid(), db_user_id, month_str, month_rec$Income, month_rec$total_expense, month_rec$Desired_Savings)
    )

    # ----------------------------------------------------
    # RUN THE MODELS ON THE FRESHLY INSERTED DATABASE DATA
    # ----------------------------------------------------

    # Extract feature vector directly from DB queries (just like a real user in the app)
    features <- build_feature_vector(db_user_id, month_str)

    # 1. Which persona do they fit?
    cluster_label <- assign_cluster(features)
    # 2. How much will they save next month?
    predicted <- predict_savings(features, db_user_id)
    # 3. What financial limits are they breaking?
    flags <- detect_overspending(features)
    # 4. What is their final 0-100 score?
    score <- calculate_financial_score(features, flags)
    # 5. What should they do to improve?
    recommendations <- generate_recommendations(features, flags, cluster_label, predicted)

    # Clean the R objects before inserting them into SQLite database.
    # as.character() and as.numeric() cast R's complex data types into raw strings and numbers.
    # unname() strips out any labels attached to the variables by the models.
    p_cluster_label <- as.character(unname(cluster_label))[1]
    p_predicted <- as.numeric(unname(predicted))[1]

    # jsonlite::toJSON() converts an R list into a JSON string format.
    # SQLite doesn't support complex objects, so we store lists/arrays as raw JSON strings.
    p_flags_json <- paste(as.character(toJSON(flags, auto_unbox = TRUE)), collapse = "")
    p_recs_json <- paste(as.character(toJSON(recommendations, auto_unbox = TRUE)), collapse = "")

    p_score <- as.numeric(unname(score))[1]

    # Save all the AI results back into the DB for the frontend dashboard to read.
    db_execute(
      "INSERT INTO analysis_results (id, user_id, month, cluster_label, predicted_savings, overspending_flags, recommendations, financial_score, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))",
      params = list(new_uuid(), db_user_id, month_str, p_cluster_label, p_predicted, p_flags_json, p_recs_json, p_score)
    )

    # Track for summary
    all_scores <- c(all_scores, p_score)
    all_clusters <- c(all_clusters, p_cluster_label)
    all_flag_counts <- c(all_flag_counts, length(flags))
  }

  if (i %% 10 == 0) {
    cat(sprintf("✓ Seeded %d / 100 users...\n", i))
  }
}

cat("\n=== Seeding Complete! ===\n")
cat("Users seeded: 100\n")
cat("Months per user: 6\n")
cat("Total records: 600 user-months\n")

cat("\n--- Score Summary ---\n")
cat("  Min score: ", min(all_scores), "\n")
cat("  Mean score:", round(mean(all_scores), 1), "\n")
cat("  Max score: ", max(all_scores), "\n")
cat("  Median:    ", median(all_scores), "\n")

cat("\n--- Cluster Distribution ---\n")
cluster_counts <- table(all_clusters)
for (cl in names(cluster_counts)) {
  cat("  ", cl, ":", cluster_counts[[cl]], "assignments\n")
}

cat("\n--- Overspending Flags ---\n")
cat("  Total flags across all user-months:", sum(all_flag_counts), "\n")
cat("  Average flags per user-month:", round(mean(all_flag_counts), 2), "\n")
cat("  Users with 0 flags:", sum(all_flag_counts == 0), "\n")
cat("  Users with 3+ flags:", sum(all_flag_counts >= 3), "\n")

# ============================================
# Final Diagnostic Plots
# ============================================
cat("\nGenerating summary plots for seeded users...\n")
library(ggplot2)
library(plotly)
dir.create("outputs", showWarnings = FALSE)

# 1. Financial Score Distribution
df_scores <- data.frame(Score = all_scores)
p1 <- ggplot(df_scores, aes(x = Score)) +
  geom_histogram(fill = "#10b981", color = "white", bins = 20, alpha = 0.8) +
  labs(
    title = "Financial Health Score Distribution (600 user-months)",
    x = "Health Score", y = "Count"
  ) +
  theme_minimal()
print(ggplotly(p1))
ggsave("outputs/seed_score_distribution.png", plot = p1, width = 7, height = 5)

# 2. Cluster Distribution
df_clusters <- as.data.frame(table(Cluster = all_clusters))
p2 <- ggplot(df_clusters, aes(x = Cluster, y = Freq, fill = Cluster)) +
  geom_bar(stat = "identity", alpha = 0.9) +
  coord_flip() +
  scale_fill_brewer(palette = "Set2") +
  labs(
    title = "Cluster Assignment Distribution",
    x = "", y = "Count"
  ) +
  theme_minimal() +
  theme(legend.position = "none")
print(ggplotly(p2))
ggsave("outputs/seed_cluster_distribution.png", plot = p2, width = 8, height = 4)

# 3. Flag Counts
df_flags <- data.frame(Flags = all_flag_counts)
p3 <- ggplot(df_flags, aes(x = Flags)) +
  geom_bar(fill = "#f97316", color = "white", alpha = 0.8) +
  scale_x_continuous(breaks = 0:max(all_flag_counts)) +
  labs(
    title = "Number of Overspending Flags per User-Month",
    x = "Flags Triggered", y = "Count"
  ) +
  theme_minimal()
print(ggplotly(p3))
ggsave("outputs/seed_flags_distribution.png", plot = p3, width = 7, height = 5)

cat("Done! Plots displayed in Viewer and saved to outputs/.\n")
