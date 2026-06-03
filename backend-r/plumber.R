# ============================================
# Consumer Finance MVP — Plumber API
# Main Entry Point
# ============================================

library(plumber)
library(jsonlite)

# Source all modules
source("R/utils.R")
source("R/db.R")
source("R/rules.R")
source("R/auth.R")
source("R/categories.R")
source("R/expenses.R")
source("R/features.R")
source("R/clustering.R")
source("R/prediction.R")
source("R/overspending.R")
source("R/recommendations.R")
source("R/reports.R")
source("R/income.R")
source("R/admin.R")
source("R/plots.R")

# Null-coalescing operator (ensure available globally)
if (!exists("%||%")) {
  `%||%` <- function(a, b) if (is.null(a)) b else a
}

# ============================================
# CORS Filter
# ============================================
#* @filter cors
function(req, res) {
  res$setHeader("Access-Control-Allow-Origin", "*")
  res$setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
  res$setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization")

  if (req$REQUEST_METHOD == "OPTIONS") {
    res$status <- 200
    return(list())
  }

  plumber::forward()
}

# ============================================
# Authentication Filter
# ============================================
#* @filter auth
function(req, res) {
  # Public endpoints that don't require auth
  public_paths <- c(
    "/api/auth/register",
    "/api/auth/login",
    "/api/health"
  )

  # Check if current path is public
  current_path <- req$PATH_INFO
  is_public <- any(sapply(public_paths, function(p) current_path == p))

  # Also allow Swagger docs
  if (grepl("^/__", current_path) || grepl("^/openapi", current_path)) {
    is_public <- TRUE
  }

  if (is_public) {
    plumber::forward()
    return()
  }

  # Extract token from Authorization header
  auth_header <- req$HTTP_AUTHORIZATION
  if (is.null(auth_header) || !grepl("^Bearer ", auth_header)) {
    res$status <- 401
    return(list(success = FALSE, message = "Authentication required"))
  }

  token <- sub("^Bearer ", "", auth_header)
  claims <- decode_token(token)

  if (is.null(claims)) {
    res$status <- 401
    return(list(success = FALSE, message = "Invalid or expired token"))
  }

  # Attach user info to request
  req$USER_ID <- claims$sub
  req$USER_ROLE <- claims$role

  plumber::forward()
}

# ============================================
# Health Check
# ============================================

#* Health check endpoint
#* @get /api/health
#* @serializer unboxedJSON
function() {
  list(
    status = "ok",
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
    version = "1.0.0"
  )
}

# ============================================
# Auth Endpoints
# ============================================

#* Register a new user
#* @post /api/auth/register
#* @serializer unboxedJSON
function(req, res) {
  body <- parse_body(req)

  validation <- validate_required(body, c("full_name", "email", "password"))
  if (!is.null(validation)) {
    return(error_response(res, validation, 400))
  }

  if (!validate_email(body$email)) {
    return(error_response(res, "Invalid email format", 400))
  }

  if (nchar(body$password) < 6) {
    return(error_response(res, "Password must be at least 6 characters", 400))
  }

  if (db_exists("users", "email", tolower(body$email))) {
    return(error_response(res, "Email already registered", 409))
  }

  user_id <- new_uuid()
  password_hash <- hashpw(body$password)

  db_execute(
    "INSERT INTO users (id, full_name, email, password_hash, role, created_at, updated_at) VALUES (?, ?, ?, ?, 'user', datetime('now'), datetime('now'))",
    params = list(user_id, body$full_name, tolower(body$email), password_hash)
  )

  seed_user_categories(user_id)

  token <- generate_token(user_id, "user")

  res$status <- 201
  return(success_response(
    data = list(
      token = token,
      user = list(
        id = user_id,
        full_name = body$full_name,
        email = tolower(body$email),
        role = "user"
      )
    ),
    message = "Registration successful"
  ))
}

#* Login user
#* @post /api/auth/login
#* @serializer unboxedJSON
function(req, res) {
  body <- parse_body(req)

  validation <- validate_required(body, c("email", "password"))
  if (!is.null(validation)) {
    return(error_response(res, validation, 400))
  }

  user <- db_get_one(
    "SELECT id, full_name, email, password_hash, role FROM users WHERE email = ?",
    params = list(tolower(body$email))
  )

  if (is.null(user)) {
    return(error_response(res, "Invalid email or password", 401))
  }

  if (!checkpw(body$password, user$password_hash)) {
    return(error_response(res, "Invalid email or password", 401))
  }

  token <- generate_token(user$id, user$role)

  return(success_response(
    data = list(
      token = token,
      user = list(
        id = user$id,
        full_name = user$full_name,
        email = user$email,
        role = user$role
      )
    ),
    message = "Login successful"
  ))
}

#* Get current user profile
#* @get /api/auth/me
#* @serializer unboxedJSON
function(req, res) {
  user_id <- req$USER_ID

  user <- db_get_one(
    "SELECT id, full_name, email, role, created_at FROM users WHERE id = ?",
    params = list(user_id)
  )

  if (is.null(user)) {
    return(error_response(res, "User not found", 404))
  }

  return(success_response(data = user))
}

#* Update user profile
#* @put /api/auth/profile
#* @serializer unboxedJSON
function(req, res) {
  user_id <- req$USER_ID
  body <- parse_body(req)

  updates <- c()
  params <- list()

  if (!is.null(body$full_name) && nchar(trimws(body$full_name)) > 0) {
    updates <- c(updates, "full_name = ?")
    params <- c(params, list(body$full_name))
  }

  if (!is.null(body$email) && nchar(trimws(body$email)) > 0) {
    if (!validate_email(body$email)) {
      return(error_response(res, "Invalid email format", 400))
    }
    existing <- db_get_one(
      "SELECT id FROM users WHERE email = ? AND id != ?",
      params = list(tolower(body$email), user_id)
    )
    if (!is.null(existing)) {
      return(error_response(res, "Email already in use", 409))
    }
    updates <- c(updates, "email = ?")
    params <- c(params, list(tolower(body$email)))
  }

  if (!is.null(body$password) && nchar(body$password) >= 6) {
    updates <- c(updates, "password_hash = ?")
    params <- c(params, list(hashpw(body$password)))
  }

  if (length(updates) == 0) {
    return(error_response(res, "No valid fields to update", 400))
  }

  updates <- c(updates, "updated_at = datetime('now')")
  params <- c(params, list(user_id))

  sql <- sprintf("UPDATE users SET %s WHERE id = ?", paste(updates, collapse = ", "))
  db_execute(sql, params = params)

  user <- db_get_one(
    "SELECT id, full_name, email, role, created_at FROM users WHERE id = ?",
    params = list(user_id)
  )

  return(success_response(data = user, message = "Profile updated successfully"))
}

# ============================================
# Category Endpoints
# ============================================

#* List categories
#* @get /api/categories
#* @serializer unboxedJSON
function(req, res) {
  user_id <- req$USER_ID
  # Calculate the previous month string (YYYY-MM-01)
  prev_month <- format(seq(Sys.Date(), length = 2, by = "-1 month")[2], "%Y-%m-01")

  query <- "
    SELECT
      c.id,
      c.name,
      c.is_default,
      c.threshold,
      c.created_at,
      c.updated_at,
      COALESCE((
        SELECT SUM(e.amount)
        FROM expenses e
        WHERE e.category_id = c.id AND e.expense_month = ?
      ), 0) as last_month_spent
    FROM categories c
    WHERE c.user_id = ?
    ORDER BY c.is_default DESC, c.name ASC
  "

  categories_df <- db_query(query, params = list(prev_month, user_id))

  # Get total spending for last month to calculate dollar suggestions
  total_spent_res <- db_query(
    "SELECT COALESCE(SUM(amount), 0) as total FROM expenses WHERE user_id = ? AND expense_month = ?",
    params = list(user_id, prev_month)
  )
  total_spent_prev <- total_spent_res$total[1]

  # Add default rules information
  if (nrow(categories_df) > 0) {
    categories_df$default_threshold_percent <- sapply(categories_df$name, get_default_percent)
    categories_df$suggested_threshold <- round(categories_df$default_threshold_percent * total_spent_prev, 2)
  }

  return(success_response(data = df_to_list(categories_df)))
}

#* Create category
#* @post /api/categories
#* @serializer unboxedJSON
function(req, res) {
  user_id <- req$USER_ID
  body <- parse_body(req)

  validation <- validate_required(body, c("name"))
  if (!is.null(validation)) {
    return(error_response(res, validation, 400))
  }

  existing <- db_get_one(
    "SELECT id FROM categories WHERE user_id = ? AND LOWER(name) = LOWER(?)",
    params = list(user_id, trimws(body$name))
  )
  if (!is.null(existing)) {
    return(error_response(res, "Category already exists", 409))
  }

  cat_id <- new_uuid()
  db_execute(
    "INSERT INTO categories (id, user_id, name, is_default, threshold, created_at, updated_at) VALUES (?, ?, ?, 0, ?, datetime('now'), datetime('now'))",
    params = list(cat_id, user_id, trimws(body$name), as.numeric(body$threshold %||% 0))
  )

  category <- db_get_one(
    "SELECT id, name, is_default, threshold, created_at, updated_at FROM categories WHERE id = ?",
    params = list(cat_id)
  )

  res$status <- 201
  return(success_response(data = category, message = "Category created"))
}

#* Update category
#* @put /api/categories/<id>
#* @serializer unboxedJSON
function(req, res, id) {
  user_id <- req$USER_ID
  body <- parse_body(req)

  category <- db_get_one(
    "SELECT id, name FROM categories WHERE id = ? AND user_id = ?",
    params = list(id, user_id)
  )

  if (is.null(category)) {
    return(error_response(res, "Category not found", 404))
  }

  if (category$name == "Other") {
    return(error_response(res, "Cannot rename 'Other' category", 400))
  }

  validation <- validate_required(body, c("name"))
  if (!is.null(validation)) {
    return(error_response(res, validation, 400))
  }

  db_execute(
    "UPDATE categories SET name = ?, threshold = ?, updated_at = datetime('now') WHERE id = ?",
    params = list(trimws(body$name), as.numeric(body$threshold %||% 0), id)
  )

  updated <- db_get_one(
    "SELECT id, name, is_default, threshold, created_at, updated_at FROM categories WHERE id = ?",
    params = list(id)
  )

  return(success_response(data = updated, message = "Category updated"))
}

#* Delete category
#* @delete /api/categories/<id>
#* @serializer unboxedJSON
function(req, res, id) {
  user_id <- req$USER_ID

  category <- db_get_one(
    "SELECT id, name FROM categories WHERE id = ? AND user_id = ?",
    params = list(id, user_id)
  )

  if (is.null(category)) {
    return(error_response(res, "Category not found", 404))
  }

  if (category$name == "Other") {
    return(error_response(res, "Cannot delete 'Other' category", 400))
  }

  other_cat <- db_get_one(
    "SELECT id FROM categories WHERE user_id = ? AND name = 'Other'",
    params = list(user_id)
  )

  if (!is.null(other_cat)) {
    db_execute(
      "UPDATE expenses SET category_id = ?, updated_at = datetime('now') WHERE category_id = ? AND user_id = ?",
      params = list(other_cat$id, id, user_id)
    )
  }

  db_execute("DELETE FROM categories WHERE id = ? AND user_id = ?", params = list(id, user_id))

  return(success_response(message = "Category deleted"))
}

# ============================================
# Expense Endpoints
# ============================================

#* List expenses
#* @get /api/expenses
#* @serializer unboxedJSON
function(req, res) {
  user_id <- req$USER_ID

  month <- req$argsQuery$month
  category <- req$argsQuery$category
  page <- as.integer(req$argsQuery$page %||% 1)
  limit <- as.integer(req$argsQuery$limit %||% 50)

  if (is.na(page) || page < 1) page <- 1
  if (is.na(limit) || limit < 1 || limit > 200) limit <- 50
  offset <- (page - 1) * limit

  where_clauses <- c("e.user_id = ?")
  params <- list(user_id)

  if (!is.null(month) && nchar(month) > 0) {
    parsed <- parse_month(month)
    if (!is.null(parsed)) {
      where_clauses <- c(where_clauses, "e.expense_month = ?")
      params <- c(params, list(parsed))
    }
  }

  if (!is.null(category) && nchar(category) > 0) {
    where_clauses <- c(where_clauses, "e.category_id = ?")
    params <- c(params, list(category))
  }

  where_sql <- paste(where_clauses, collapse = " AND ")

  total <- db_query(sprintf("SELECT COUNT(*) as total FROM expenses e WHERE %s", where_sql), params = params)$total[1]

  query_sql <- sprintf(
    "SELECT e.id, e.category_id, c.name as category_name, e.amount, e.expense_type, e.expense_month, e.note, e.created_at, e.updated_at
     FROM expenses e LEFT JOIN categories c ON e.category_id = c.id
     WHERE %s ORDER BY e.expense_month DESC, e.created_at DESC LIMIT ? OFFSET ?",
    where_sql
  )
  params <- c(params, list(limit, offset))

  expenses <- db_query(query_sql, params = params)

  return(success_response(data = list(
    expenses = df_to_list(expenses),
    total = total,
    page = page,
    limit = limit,
    total_pages = ceiling(max(total, 1) / limit)
  )))
}

#* Create expense
#* @post /api/expenses
#* @serializer unboxedJSON
function(req, res) {
  user_id <- req$USER_ID
  body <- parse_body(req)

  validation <- validate_required(body, c("category_id", "amount", "expense_month"))
  if (!is.null(validation)) {
    return(error_response(res, validation, 400))
  }

  amount <- as.numeric(body$amount)
  if (is.na(amount) || amount < 0) {
    return(error_response(res, "Invalid amount", 400))
  }

  cat_check <- db_get_one("SELECT id FROM categories WHERE id = ? AND user_id = ?", params = list(body$category_id, user_id))
  if (is.null(cat_check)) {
    return(error_response(res, "Category not found", 404))
  }

  expense_month <- parse_month(body$expense_month)
  if (is.null(expense_month)) {
    return(error_response(res, "Invalid month format", 400))
  }

  expense_id <- new_uuid()
  db_execute(
    "INSERT INTO expenses (id, user_id, category_id, amount, expense_type, expense_month, note, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'))",
    params = list(expense_id, user_id, body$category_id, amount, body$expense_type %||% "expense", expense_month, body$note %||% "")
  )

  expense <- db_get_one(
    "SELECT e.id, e.category_id, c.name as category_name, e.amount, e.expense_type, e.expense_month, e.note, e.created_at
     FROM expenses e LEFT JOIN categories c ON e.category_id = c.id WHERE e.id = ?",
    params = list(expense_id)
  )

  res$status <- 201
  return(success_response(data = expense, message = "Expense created"))
}

#* Update expense
#* @put /api/expenses/<id>
#* @serializer unboxedJSON
function(req, res, id) {
  user_id <- req$USER_ID
  body <- parse_body(req)

  existing <- db_get_one("SELECT id FROM expenses WHERE id = ? AND user_id = ?", params = list(id, user_id))
  if (is.null(existing)) {
    return(error_response(res, "Expense not found", 404))
  }

  updates <- c()
  params <- list()

  if (!is.null(body$category_id)) {
    cat_check <- db_get_one("SELECT id FROM categories WHERE id = ? AND user_id = ?", params = list(body$category_id, user_id))
    if (is.null(cat_check)) {
      return(error_response(res, "Category not found", 404))
    }
    updates <- c(updates, "category_id = ?")
    params <- c(params, list(body$category_id))
  }
  if (!is.null(body$amount)) {
    amt <- as.numeric(body$amount)
    if (is.na(amt) || amt < 0) {
      return(error_response(res, "Invalid amount", 400))
    }
    updates <- c(updates, "amount = ?")
    params <- c(params, list(amt))
  }
  if (!is.null(body$expense_type)) {
    updates <- c(updates, "expense_type = ?")
    params <- c(params, list(body$expense_type))
  }
  if (!is.null(body$expense_month)) {
    em <- parse_month(body$expense_month)
    if (is.null(em)) {
      return(error_response(res, "Invalid month", 400))
    }
    updates <- c(updates, "expense_month = ?")
    params <- c(params, list(em))
  }
  if (!is.null(body$note)) {
    updates <- c(updates, "note = ?")
    params <- c(params, list(body$note))
  }

  if (length(updates) == 0) {
    return(error_response(res, "No fields to update", 400))
  }

  updates <- c(updates, "updated_at = datetime('now')")
  params <- c(params, list(id))

  db_execute(sprintf("UPDATE expenses SET %s WHERE id = ?", paste(updates, collapse = ", ")), params = params)

  expense <- db_get_one(
    "SELECT e.id, e.category_id, c.name as category_name, e.amount, e.expense_type, e.expense_month, e.note, e.created_at, e.updated_at
     FROM expenses e LEFT JOIN categories c ON e.category_id = c.id WHERE e.id = ?",
    params = list(id)
  )

  return(success_response(data = expense, message = "Expense updated"))
}

#* Delete expense
#* @delete /api/expenses/<id>
#* @serializer unboxedJSON
function(req, res, id) {
  user_id <- req$USER_ID
  existing <- db_get_one("SELECT id FROM expenses WHERE id = ? AND user_id = ?", params = list(id, user_id))
  if (is.null(existing)) {
    return(error_response(res, "Expense not found", 404))
  }
  db_execute("DELETE FROM expenses WHERE id = ? AND user_id = ?", params = list(id, user_id))
  return(success_response(message = "Expense deleted"))
}

# ============================================
# Income Endpoints
# ============================================

#* List income transactions
#* @get /api/income
#* @serializer unboxedJSON
function(req, res) {
  user_id <- req$USER_ID
  month <- req$argsQuery$month
  page <- as.integer(req$argsQuery$page %||% 1)
  limit <- as.integer(req$argsQuery$limit %||% 50)

  if (is.na(page) || page < 1) page <- 1
  if (is.na(limit) || limit < 1 || limit > 200) limit <- 50
  offset <- (page - 1) * limit

  where_clauses <- c("user_id = ?")
  params <- list(user_id)

  if (!is.null(month) && nchar(month) > 0) {
    parsed <- parse_month(month)
    if (!is.null(parsed)) {
      where_clauses <- c(where_clauses, "income_month = ?")
      params <- c(params, list(parsed))
    }
  }

  where_sql <- paste(where_clauses, collapse = " AND ")
  total <- db_query(sprintf("SELECT COUNT(*) as total FROM income WHERE %s", where_sql), params = params)$total[1]

  query_sql <- sprintf(
    "SELECT id, amount, income_month, source, note, created_at, updated_at
     FROM income WHERE %s ORDER BY income_month DESC, created_at DESC LIMIT ? OFFSET ?",
    where_sql
  )
  params <- c(params, list(limit, offset))

  income_records <- db_query(query_sql, params = params)

  return(success_response(data = list(
    income = df_to_list(income_records),
    total = total,
    page = page,
    limit = limit,
    total_pages = ceiling(max(total, 1) / limit)
  )))
}

#* Create income transaction
#* @post /api/income
#* @serializer unboxedJSON
function(req, res) {
  user_id <- req$USER_ID
  body <- parse_body(req)

  validation <- validate_required(body, c("amount", "income_month", "source"))
  if (!is.null(validation)) {
    return(error_response(res, validation, 400))
  }

  amount <- as.numeric(body$amount)
  if (is.na(amount) || amount < 0) {
    return(error_response(res, "Invalid amount", 400))
  }

  income_month <- parse_month(body$income_month)
  if (is.null(income_month)) {
    return(error_response(res, "Invalid month format", 400))
  }

  income_id <- new_uuid()
  db_execute(
    "INSERT INTO income (id, user_id, amount, income_month, source, note, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'))",
    params = list(income_id, user_id, amount, income_month, body$source, body$note %||% "")
  )

  # Resync total income for the month
  sync_monthly_income(user_id, income_month)

  income_record <- db_get_one("SELECT * FROM income WHERE id = ?", params = list(income_id))
  res$status <- 201
  return(success_response(data = income_record, message = "Income created"))
}

#* Update income transaction
#* @put /api/income/<id>
#* @serializer unboxedJSON
function(req, res, id) {
  user_id <- req$USER_ID
  body <- parse_body(req)

  existing <- db_get_one("SELECT id, income_month FROM income WHERE id = ? AND user_id = ?", params = list(id, user_id))
  if (is.null(existing)) {
    return(error_response(res, "Income not found", 404))
  }

  updates <- c()
  params <- list()
  if (!is.null(body$amount)) {
    amt <- as.numeric(body$amount)
    if (is.na(amt) || amt < 0) {
      return(error_response(res, "Invalid amount", 400))
    }
    updates <- c(updates, "amount = ?")
    params <- c(params, list(amt))
  }
  if (!is.null(body$source)) {
    updates <- c(updates, "source = ?")
    params <- c(params, list(body$source))
  }
  if (!is.null(body$income_month)) {
    im <- parse_month(body$income_month)
    if (is.null(im)) {
      return(error_response(res, "Invalid month", 400))
    }
    updates <- c(updates, "income_month = ?")
    params <- c(params, list(im))
  }
  if (!is.null(body$note)) {
    updates <- c(updates, "note = ?")
    params <- c(params, list(body$note))
  }

  if (length(updates) == 0) {
    return(error_response(res, "No fields to update", 400))
  }

  updates <- c(updates, "updated_at = datetime('now')")
  params <- c(params, list(id))
  db_execute(sprintf("UPDATE income SET %s WHERE id = ?", paste(updates, collapse = ", ")), params = params)

  # Resync
  sync_monthly_income(user_id, existing$income_month)
  if (!is.null(body$income_month)) sync_monthly_income(user_id, body$income_month)

  updated <- db_get_one("SELECT * FROM income WHERE id = ?", params = list(id))
  return(success_response(data = updated, message = "Income updated"))
}

#* Delete income transaction
#* @delete /api/income/<id>
#* @serializer unboxedJSON
function(req, res, id) {
  user_id <- req$USER_ID
  existing <- db_get_one("SELECT id, income_month FROM income WHERE id = ? AND user_id = ?", params = list(id, user_id))
  if (is.null(existing)) {
    return(error_response(res, "Income not found", 404))
  }

  db_execute("DELETE FROM income WHERE id = ? AND user_id = ?", params = list(id, user_id))
  sync_monthly_income(user_id, existing$income_month)

  return(success_response(message = "Income deleted"))
}

# ============================================
# Monthly Summary Endpoints
# ============================================

#* Upsert monthly summary
#* @post /api/monthly-summary
#* @serializer unboxedJSON
function(req, res) {
  user_id <- req$USER_ID
  body <- parse_body(req)

  validation <- validate_required(body, c("month"))
  if (!is.null(validation)) {
    return(error_response(res, validation, 400))
  }

  month <- parse_month(body$month)
  if (is.null(month)) {
    return(error_response(res, "Invalid month format", 400))
  }

  income <- as.numeric(body$income %||% 0)
  total_savings <- as.numeric(body$total_savings %||% 0)

  existing <- db_get_one("SELECT id FROM monthly_snapshots WHERE user_id = ? AND month = ?", params = list(user_id, month))

  p_income <- as.numeric(unname(income))[1]
  p_total_savings <- as.numeric(unname(total_savings))[1]
  p_month <- as.character(unname(month))[1]
  p_user_id <- as.character(unname(user_id))[1]

  if (!is.null(existing)) {
    p_existing_id <- as.character(unname(existing$id))[1]
    db_execute("UPDATE monthly_snapshots SET income = ?, total_savings = ?, updated_at = datetime('now') WHERE id = ?",
      params = list(p_income, p_total_savings, p_existing_id)
    )
  } else {
    snap_id <- new_uuid()
    db_execute("INSERT INTO monthly_snapshots (id, user_id, month, income, total_savings, created_at, updated_at) VALUES (?, ?, ?, ?, ?, datetime('now'), datetime('now'))",
      params = list(snap_id, p_user_id, p_month, p_income, p_total_savings)
    )
  }

  # Calculate aggregates from transaction tables
  total_inc_agg <- db_query("SELECT COALESCE(SUM(amount), 0) as total FROM income WHERE user_id = ? AND income_month = ?",
    params = list(user_id, month)
  )$total[1]
  total_exp_agg <- db_query("SELECT COALESCE(SUM(amount), 0) as total FROM expenses WHERE user_id = ? AND expense_month = ?",
    params = list(user_id, month)
  )$total[1]

  p_total_inc <- as.numeric(unname(total_inc_agg))[1]
  p_total_exp <- as.numeric(unname(total_exp_agg))[1]

  db_execute("UPDATE monthly_snapshots SET income = ?, total_expense = ? WHERE user_id = ? AND month = ?",
    params = list(p_total_inc, p_total_exp, p_user_id, p_month)
  )

  snapshot <- db_get_one("SELECT * FROM monthly_snapshots WHERE user_id = ? AND month = ?", params = list(user_id, month))
  return(success_response(data = snapshot, message = "Monthly summary updated"))
}

#* Get monthly summary
#* @get /api/monthly-summary/<month>
#* @serializer unboxedJSON
function(req, res, month) {
  user_id <- req$USER_ID
  parsed <- parse_month(month)
  if (is.null(parsed)) {
    return(error_response(res, "Invalid month", 400))
  }

  snapshot <- db_get_one("SELECT * FROM monthly_snapshots WHERE user_id = ? AND month = ?", params = list(user_id, parsed))

  if (is.null(snapshot)) {
    total_exp <- db_query("SELECT COALESCE(SUM(amount), 0) as total FROM expenses WHERE user_id = ? AND expense_month = ?",
      params = list(user_id, parsed)
    )$total[1]
    snapshot <- list(month = parsed, income = 0, total_expense = total_exp, total_savings = 0)
  }

  return(success_response(data = snapshot))
}

# ============================================
# Analytics Endpoints
# ============================================

#* Full dashboard data
#* @get /api/analytics/dashboard
#* @serializer unboxedJSON
function(req, res) {
  user_id <- req$USER_ID
  month <- req$argsQuery$month

  if (is.null(month)) {
    month <- format(Sys.Date(), "%Y-%m-01")
  } else {
    month <- parse_month(month)
    if (is.null(month)) month <- format(Sys.Date(), "%Y-%m-01")
  }

  # Build features
  features <- build_feature_vector(user_id, month)
  cluster_label <- assign_cluster(features)
  predicted <- predict_savings(features, user_id)
  flags <- detect_overspending(features)
  score <- calculate_financial_score(features, flags)
  recommendations <- generate_recommendations(features, flags, cluster_label, predicted)

  # Get monthly history for charts
  history <- db_query(
    "SELECT month, income, total_expense, total_savings FROM monthly_snapshots
     WHERE user_id = ? ORDER BY month DESC LIMIT 12",
    params = list(user_id)
  )

  # Get recent expenses
  recent_expenses <- db_query(
    "SELECT e.id, c.name as category_name, e.amount, e.expense_month, e.note
     FROM expenses e LEFT JOIN categories c ON e.category_id = c.id
     WHERE e.user_id = ? ORDER BY e.created_at DESC LIMIT 5",
    params = list(user_id)
  )

  return(success_response(data = list(
    summary = list(
      income = features$income,
      total_expense = features$total_expense,
      total_savings = features$total_savings,
      savings_rate = features$savings_rate,
      financial_score = score
    ),
    segment = list(label = cluster_label),
    prediction = list(predicted_savings = predicted),
    alerts = flags,
    recommendations = recommendations,
    charts = list(
      category_breakdown = features$category_breakdown,
      history = df_to_list(history)
    ),
    recent_expenses = df_to_list(recent_expenses)
  )))
}

#* Run analysis for a specific month
#* @post /api/analytics/analyze
#* @serializer unboxedJSON
function(req, res) {
  user_id <- req$USER_ID
  body <- parse_body(req)

  month <- parse_month(body$month %||% format(Sys.Date(), "%Y-%m-01"))
  if (is.null(month)) {
    return(error_response(res, "Invalid month", 400))
  }

  features <- build_feature_vector(user_id, month)
  cluster_label <- assign_cluster(features)
  predicted <- predict_savings(features, user_id)
  flags <- detect_overspending(features)
  score <- calculate_financial_score(features, flags)
  recommendations <- generate_recommendations(features, flags, cluster_label, predicted)

  existing <- db_get_one("SELECT id FROM analysis_results WHERE user_id = ? AND month = ?", params = list(user_id, month))

  # Defensively typecast all parameters to length 1 atomic vectors
  p_cluster_label <- as.character(unname(cluster_label))[1]
  p_predicted <- as.numeric(unname(predicted))[1]
  p_flags_json <- paste(as.character(toJSON(flags, auto_unbox = TRUE)), collapse = "")
  p_recs_json <- paste(as.character(toJSON(recommendations, auto_unbox = TRUE)), collapse = "")
  p_score <- as.numeric(unname(score))[1]
  p_month <- as.character(unname(month))[1]
  p_user_id <- as.character(unname(user_id))[1]

  if (!is.null(existing)) {
    p_existing_id <- as.character(unname(existing$id))[1]
    db_execute(
      "UPDATE analysis_results SET cluster_label = ?, predicted_savings = ?, overspending_flags = ?, recommendations = ?, financial_score = ?, created_at = datetime('now') WHERE id = ?",
      params = list(p_cluster_label, p_predicted, p_flags_json, p_recs_json, p_score, p_existing_id)
    )
  } else {
    analysis_id <- new_uuid()
    db_execute(
      "INSERT INTO analysis_results (id, user_id, month, cluster_label, predicted_savings, overspending_flags, recommendations, financial_score, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))",
      params = list(analysis_id, p_user_id, p_month, p_cluster_label, p_predicted, p_flags_json, p_recs_json, p_score)
    )
  }

  return(success_response(data = list(
    month = month,
    cluster_label = cluster_label,
    predicted_savings = predicted,
    financial_score = score,
    overspending_flags = flags,
    recommendations = recommendations
  ), message = "Analysis complete"))
}

#* Get analysis history
#* @get /api/analytics/history
#* @serializer unboxedJSON
function(req, res) {
  user_id <- req$USER_ID
  results <- db_query(
    "SELECT month, cluster_label, predicted_savings, financial_score, created_at FROM analysis_results WHERE user_id = ? ORDER BY month DESC LIMIT 12",
    params = list(user_id)
  )
  return(success_response(data = df_to_list(results)))
}

# ============================================
# Report Endpoints
# ============================================

#* Download financial report as Excel
#* @get /api/reports/excel
#* @serializer contentType list(type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
function(req, res) {
  user_id <- req$USER_ID
  month <- req$argsQuery$month %||% format(Sys.Date(), "%Y-%m-01")
  month <- parse_month(month)
  if (is.null(month)) month <- format(Sys.Date(), "%Y-%m-01")

  result <- generate_excel_report(user_id, month)

  # Log report
  report_id <- new_uuid()
  db_execute(
    "INSERT INTO reports (id, user_id, file_name, file_path, created_at) VALUES (?, ?, ?, ?, datetime('now'))",
    params = list(report_id, user_id, result$filename, result$filepath)
  )

  res$setHeader("Access-Control-Expose-Headers", "Content-Disposition")
  res$setHeader("Content-Disposition", sprintf('attachment; filename="%s"', result$filename))

  readBin(result$filepath, "raw", n = file.info(result$filepath)$size)
}

# ============================================
# Admin Endpoints
# ============================================

#* Admin overview
#* @get /api/admin/overview
#* @serializer unboxedJSON
function(req, res) {
  if (is.null(req$USER_ROLE) || req$USER_ROLE != "admin") {
    return(error_response(res, "Admin access required", 403))
  }

  total_users <- db_query("SELECT COUNT(*) as count FROM users WHERE role = 'user'")$count[1]
  total_expenses <- db_query("SELECT COUNT(*) as count FROM expenses")$count[1]
  total_amount <- db_query("SELECT COALESCE(SUM(amount), 0) as total FROM expenses")$total[1]
  total_reports <- db_query("SELECT COUNT(*) as count FROM reports")$count[1]

  # Latest month activity
  latest_month <- db_query(
    "SELECT expense_month, COUNT(*) as count, COALESCE(SUM(amount), 0) as total
     FROM expenses
     GROUP BY expense_month
     ORDER BY expense_month DESC LIMIT 1"
  )

  latest_activity <- if (nrow(latest_month) > 0) {
    list(
      expense_month = as.character(latest_month$expense_month[1]),
      count = as.integer(latest_month$count[1]),
      total = round(as.numeric(latest_month$total[1]), 2)
    )
  } else NULL

  return(success_response(data = list(
    total_users = total_users,
    total_expenses = total_expenses,
    total_expense_amount = round(total_amount, 2),
    total_reports = total_reports,
    latest_activity = latest_activity
  )))
}

#* Admin segments
#* @get /api/admin/segments
#* @serializer unboxedJSON
function(req, res) {
  if (is.null(req$USER_ROLE) || req$USER_ROLE != "admin") {
    return(error_response(res, "Admin access required", 403))
  }

  segments <- db_query(
    "SELECT cluster_label as segment, COUNT(*) as count FROM analysis_results WHERE cluster_label IS NOT NULL GROUP BY cluster_label ORDER BY count DESC"
  )

  return(success_response(data = df_to_list(segments)))
}

#* Admin overspending summary
#* @get /api/admin/overspending
#* @serializer unboxedJSON
function(req, res) {
  if (is.null(req$USER_ROLE) || req$USER_ROLE != "admin") {
    return(error_response(res, "Admin access required", 403))
  }

  results <- db_query("SELECT overspending_flags FROM analysis_results WHERE overspending_flags IS NOT NULL ORDER BY created_at DESC LIMIT 100")

  issue_counts <- list()
  if (nrow(results) > 0) {
    for (i in 1:nrow(results)) {
      tryCatch(
        {
          flags <- fromJSON(results$overspending_flags[i])
          if (is.data.frame(flags) && "issue" %in% names(flags)) {
            for (issue in flags$issue) {
              issue_counts[[issue]] <- (issue_counts[[issue]] %||% 0) + 1
            }
          }
        },
        error = function(e) {}
      )
    }
  }

  summary_list <- lapply(names(issue_counts), function(n) list(issue = n, count = issue_counts[[n]]))
  return(success_response(data = summary_list))
}

#* Admin list all users
#* @get /api/admin/users
#* @serializer unboxedJSON
function(req, res) {
  if (is.null(req$USER_ROLE) || req$USER_ROLE != "admin") {
    return(error_response(res, "Admin access required", 403))
  }

  users <- db_query(
    "SELECT u.id, u.full_name, u.email, u.role, u.created_at,
            (SELECT COUNT(*) FROM expenses WHERE user_id = u.id) as expense_count,
            (SELECT COALESCE(SUM(amount), 0) FROM expenses WHERE user_id = u.id) as total_spent
     FROM users u
     ORDER BY u.created_at DESC"
  )

  return(success_response(data = df_to_list(users)))
}

#* Admin list all database tables
#* @get /api/admin/db/tables
#* @serializer unboxedJSON
function(req, res) {
  if (is.null(req$USER_ROLE) || req$USER_ROLE != "admin") {
    return(error_response(res, "Admin access required", 403))
  }

  con <- get_db()
  on.exit(dbDisconnect(con))
  tables <- dbListTables(con)
  return(success_response(data = tables))
}

#* Admin get raw data from a specific table
#* @get /api/admin/db/data
#* @serializer unboxedJSON
function(req, res, table = NULL) {
  if (is.null(req$USER_ROLE) || req$USER_ROLE != "admin") {
    return(error_response(res, "Admin access required", 403))
  }

  if (is.null(table) || nchar(table) == 0) {
    return(error_response(res, "Table name is required", 400))
  }

  con <- get_db()
  on.exit(dbDisconnect(con))
  all_tables <- dbListTables(con)

  if (!(table %in% all_tables)) {
    return(error_response(res, sprintf("Invalid table name: %s", table), 400))
  }

  data <- dbGetQuery(con, sprintf("SELECT * FROM %s LIMIT 100", table))
  return(success_response(data = df_to_list(data)))
}

# ============================================
# Admin Plot Endpoints — PNG image responses
# ============================================

#* @get /api/admin/plots/segmentation
#* @serializer png list(width=900, height=430)
function(req, res) {
  if (is.null(req$USER_ROLE) || req$USER_ROLE != "admin") {
    res$status <- 403
    return(invisible(NULL))
  }
  print(plot_segmentation())
}

#* @get /api/admin/plots/overspending-rules
#* @serializer png list(width=900, height=430)
function(req, res) {
  if (is.null(req$USER_ROLE) || req$USER_ROLE != "admin") {
    res$status <- 403
    return(invisible(NULL))
  }
  print(plot_overspending_rules())
}

#* @get /api/admin/plots/overspending-frequency
#* @serializer png list(width=900, height=430)
function(req, res) {
  if (is.null(req$USER_ROLE) || req$USER_ROLE != "admin") {
    res$status <- 403
    return(invisible(NULL))
  }
  print(plot_overspending_frequency())
}

#* @get /api/admin/plots/score-formula
#* @serializer png list(width=900, height=430)
function(req, res) {
  if (is.null(req$USER_ROLE) || req$USER_ROLE != "admin") {
    res$status <- 403
    return(invisible(NULL))
  }
  print(plot_score_formula())
}

#* @get /api/admin/plots/score-distribution
#* @serializer png list(width=900, height=430)
function(req, res) {
  if (is.null(req$USER_ROLE) || req$USER_ROLE != "admin") {
    res$status <- 403
    return(invisible(NULL))
  }
  print(plot_score_distribution())
}

#* @get /api/admin/plots/savings-prediction
#* @serializer png list(width=900, height=430)
function(req, res) {
  if (is.null(req$USER_ROLE) || req$USER_ROLE != "admin") {
    res$status <- 403
    return(invisible(NULL))
  }
  print(plot_savings_prediction())
}

#* @get /api/admin/plots/feature-vector
#* @serializer png list(width=900, height=430)
function(req, res) {
  if (is.null(req$USER_ROLE) || req$USER_ROLE != "admin") {
    res$status <- 403
    return(invisible(NULL))
  }
  print(plot_feature_vector())
}
