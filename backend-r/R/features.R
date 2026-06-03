# ============================================
# Feature Engineering Module
# ============================================

library(dplyr)
library(tidyr)

#' Build monthly feature vector for a user
#' @param user_id User's UUID
#' @param month Target month (YYYY-MM-DD format)
#' @return Named list of features
build_feature_vector <- function(user_id, month) {
  cat("\n--- Building feature vector ---\n")
  cat("  User:", user_id, "| Month:", month, "\n")
  # Get monthly snapshot
  snapshot <- db_get_one(
    "SELECT income, total_expense, total_savings FROM monthly_snapshots WHERE user_id = ? AND month = ?",
    params = list(user_id, month)
  )
  
  income <- if (!is.null(snapshot)) snapshot$income else 0
  total_savings <- if (!is.null(snapshot)) snapshot$total_savings else 0
  
  # db_query is our custom wrapper around RSQLite's dbGetQuery.
  # We use COALESCE(SUM(amount), 0) to ensure that if a user has no expenses, 
  # it returns 0 instead of NA (which would break the math later).
  exp_sum <- db_query(
    "SELECT COALESCE(SUM(amount), 0) as total FROM expenses WHERE user_id = ? AND expense_month = ?",
    params = list(user_id, month)
  )
  total_expense <- exp_sum$total[1]

  cat("  Income:", income, "| Expense:", total_expense, "| Savings:", income - total_expense, "\n")
  
  # This SQL query performs a LEFT JOIN.
  # It takes all the user's base categories from the 'categories' table
  # and joins them with their actual spending in the 'expenses' table for this month.
  # The GROUP BY ensures we get exactly one row per category with the sum of all their purchases in it.
  category_data <- db_query(
    "SELECT c.name as category, c.threshold, COALESCE(SUM(e.amount), 0) as amount
     FROM categories c
     LEFT JOIN expenses e ON e.category_id = c.id AND e.expense_month = ?
     WHERE c.user_id = ?
     GROUP BY c.name, c.threshold",
    params = list(month, user_id)
  )
  
  # Build category shares
  get_cat_amount <- function(cat_name) {
    if (nrow(category_data) == 0) return(0)
    val <- category_data$amount[tolower(category_data$category) == tolower(cat_name)]
    if (length(val) == 0) return(0)
    return(val[1])
  }
  
  rent <- get_cat_amount("Rent")
  loan_repayment <- get_cat_amount("Loan Repayment")
  insurance <- get_cat_amount("Insurance")
  groceries <- get_cat_amount("Groceries")
  transport <- get_cat_amount("Transport")
  eating_out <- get_cat_amount("Eating Out")
  entertainment <- get_cat_amount("Entertainment")
  utilities <- get_cat_amount("Utilities")
  healthcare <- get_cat_amount("Healthcare")
  education <- get_cat_amount("Education")
  miscellaneous <- get_cat_amount("Miscellaneous")
  
  # Total Savings in the database is actually the user's TARGET/GOAL savings
  target_savings <- if (!is.null(snapshot)) snapshot$total_savings else 0
  
  # Actual Savings is what's left over
  actual_savings <- income - total_expense
  
  # Calculate shares (avoid division by zero)
  safe_div <- function(num, denom) {
    if (denom == 0) return(0)
    return(num / denom)
  }
  
  rent_share <- safe_div(rent, total_expense)
  loan_repayment_share <- safe_div(loan_repayment, total_expense)
  insurance_share <- safe_div(insurance, total_expense)
  groceries_share <- safe_div(groceries, total_expense)
  transport_share <- safe_div(transport, total_expense)
  eating_out_share <- safe_div(eating_out, total_expense)
  entertainment_share <- safe_div(entertainment, total_expense)
  utilities_share <- safe_div(utilities, total_expense)
  healthcare_share <- safe_div(healthcare, total_expense)
  education_share <- safe_div(education, total_expense)
  miscellaneous_share <- safe_div(miscellaneous, total_expense)
  
  # Essential vs discretionary spending
  essential_spending <- rent + loan_repayment + insurance + groceries + transport + utilities + healthcare + education
  discretionary_spending <- eating_out + entertainment + miscellaneous
  
  # Savings rate based on ACTUAL performance
  savings_rate <- safe_div(actual_savings, income)

  # Print the calculated shares so we can verify
  cat("  Category shares: rent=", round(rent_share, 3),
      " groceries=", round(groceries_share, 3),
      " entertainment=", round(entertainment_share, 3),
      " transport=", round(transport_share, 3), "\n")
  cat("  Savings rate:", round(savings_rate * 100, 1), "%\n")
  cat("  Essential:", essential_spending, "| Discretionary:", discretionary_spending, "\n")
  
  # Get historical data for trends
  history <- db_query(
    "SELECT month, income, total_expense, total_savings 
     FROM monthly_snapshots 
     WHERE user_id = ? AND month < ? 
     ORDER BY month DESC LIMIT 6",
    params = list(user_id, month)
  )
  
  # Expense growth rate (vs previous month)
  expense_growth <- 0
  if (nrow(history) > 0) {
    prev_expense <- history$total_expense[1]
    if (prev_expense > 0) {
      expense_growth <- (total_expense - prev_expense) / prev_expense
    }
  }
  cat("  Expense growth vs last month:", round(expense_growth * 100, 1), "%\n")
  
  # Rolling averages (last 3 months)
  avg_savings_last_3m <- 0
  rolling_expense_sd <- 0
  if (nrow(history) >= 3) {
    # Calculate historical actual savings for rolling average
    hist_actual_savings <- history$income - history$total_expense
    avg_savings_last_3m <- mean(hist_actual_savings[1:3], na.rm = TRUE)
    rolling_expense_sd <- sd(history$total_expense[1:3], na.rm = TRUE)
    if (is.na(rolling_expense_sd)) rolling_expense_sd <- 0
  } else if (nrow(history) > 0) {
    avg_savings_last_3m <- mean(history$income - history$total_expense, na.rm = TRUE)
  }
  
  features <- list(
    user_id = user_id,
    month = month,
    income = income,
    total_expense = total_expense,
    total_savings = actual_savings, # UI expects actual surplus here
    target_savings = target_savings, # Keep goal separate
    actual_savings = actual_savings,
    essential_spending = essential_spending,
    discretionary_spending = discretionary_spending,
    rent = rent,
    loan_repayment = loan_repayment,
    insurance = insurance,
    groceries = groceries,
    transport = transport,
    eating_out = eating_out,
    entertainment = entertainment,
    utilities = utilities,
    healthcare = healthcare,
    education = education,
    miscellaneous = miscellaneous,
    food = groceries + eating_out, # Combined food for overspending/recommendations rules
    rent_share = round(rent_share, 4),
    loan_repayment_share = round(loan_repayment_share, 4),
    insurance_share = round(insurance_share, 4),
    groceries_share = round(groceries_share, 4),
    transport_share = round(transport_share, 4),
    eating_out_share = round(eating_out_share, 4),
    entertainment_share = round(entertainment_share, 4),
    utilities_share = round(utilities_share, 4),
    healthcare_share = round(healthcare_share, 4),
    education_share = round(education_share, 4),
    miscellaneous_share = round(miscellaneous_share, 4),
    food_share = round(groceries_share + eating_out_share, 4), # Combined food share for overspending rules
    savings_rate = round(savings_rate, 4),
    expense_growth = round(expense_growth, 4),
    avg_savings_last_3m = round(avg_savings_last_3m, 2),
    rolling_expense_sd = round(rolling_expense_sd, 2),
    category_breakdown = df_to_list(category_data)
  )
  
  cat("  Feature vector built:", length(features), "fields\n")
  cat("--- Done ---\n")
  return(features)
}

#' Get historical feature vectors for a user
#' @param user_id User's UUID
#' @param n_months Number of months to look back
#' @return Data frame of monthly features
get_history_features <- function(user_id, n_months = 12) {
  months <- db_query(
    "SELECT DISTINCT month FROM monthly_snapshots WHERE user_id = ? ORDER BY month DESC LIMIT ?",
    params = list(user_id, n_months)
  )
  
  if (nrow(months) == 0) return(NULL)
  
  features_list <- lapply(months$month, function(m) {
    f <- build_feature_vector(user_id, m)
    # Remove nested list for data frame
    f$category_breakdown <- NULL
    data.frame(f, stringsAsFactors = FALSE)
  })
  
  do.call(rbind, features_list)
}
