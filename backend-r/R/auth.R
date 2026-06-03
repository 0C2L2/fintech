# ============================================
# Authentication Module
# ============================================
# This file contains ONLY helper functions used by plumber.R route handlers.
# Route definitions (Plumber decorators + anonymous functions) live in plumber.R.
# ============================================

library(bcrypt)
library(jose)
library(jsonlite)

# JWT secret key - in production, set the JWT_SECRET environment variable
JWT_SECRET <- Sys.getenv("JWT_SECRET", "finhealth-mvp-secret-key-change-in-production-2024")
JWT_EXPIRY <- 86400 * 7 # 7 days in seconds

# Default categories to seed for new users (aligned with Kaggle feature columns)
DEFAULT_CATEGORIES <- c(
  "Rent", "Loan Repayment", "Insurance", "Groceries",
  "Transport", "Eating Out", "Entertainment", "Utilities",
  "Healthcare", "Education", "Miscellaneous"
)

#' Generate a signed JWT token for a user
#' @param user_id User's UUID string
#' @param role User's role ("user" or "admin")
#' @return Character: signed JWT string
generate_token <- function(user_id, role) {
  now <- as.numeric(Sys.time())
  claim <- jwt_claim(
    sub = user_id,
    role = role,
    iat = now,
    exp = now + JWT_EXPIRY
  )
  jwt_encode_hmac(claim, secret = charToRaw(JWT_SECRET))
}

#' Decode and validate a JWT token
#' @param token Character: JWT string (without "Bearer " prefix)
#' @return Named list of claims on success, NULL on failure or expiry
decode_token <- function(token) {
  tryCatch(
    {
      claims <- jwt_decode_hmac(token, secret = charToRaw(JWT_SECRET))
      # Explicit expiration check (jose may not enforce this)
      if (as.numeric(Sys.time()) > claims$exp) {
        return(NULL)
      }
      return(claims)
    },
    error = function(e) {
      return(NULL)
    }
  )
}

#' Seed default expense categories for a newly registered user
#' @param user_id User's UUID string
seed_user_categories <- function(user_id) {
  for (cat_name in DEFAULT_CATEGORIES) {
    cat_id <- new_uuid()
    db_execute(
      "INSERT INTO categories (id, user_id, name, is_default, created_at, updated_at) VALUES (?, ?, ?, 1, datetime('now'), datetime('now'))",
      params = list(cat_id, user_id, cat_name)
    )
  }
}

# ============================================
# Auth Route Handlers
# ============================================

#' Register a new user
#' @post /api/auth/register
#' @serializer unboxedJSON
function(req, res) {
  body <- parse_body(req)

  # Validate required fields
  validation <- validate_required(body, c("full_name", "email", "password"))
  if (!is.null(validation)) {
    return(error_response(res, validation, 400))
  }

  # Validate email format
  if (!validate_email(body$email)) {
    return(error_response(res, "Invalid email format", 400))
  }

  # Check password length
  if (nchar(body$password) < 6) {
    return(error_response(res, "Password must be at least 6 characters", 400))
  }

  # Check if email already exists
  if (db_exists("users", "email", tolower(body$email))) {
    return(error_response(res, "Email already registered", 409))
  }

  # Create user
  user_id <- new_uuid()
  password_hash <- hashpw(body$password)

  db_execute(
    "INSERT INTO users (id, full_name, email, password_hash, role, created_at, updated_at) VALUES (?, ?, ?, ?, 'user', datetime('now'), datetime('now'))",
    params = list(user_id, body$full_name, tolower(body$email), password_hash)
  )

  # Seed default categories
  seed_user_categories(user_id)

  # Generate token
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

#' Login user
#' @post /api/auth/login
#' @serializer unboxedJSON
function(req, res) {
  body <- parse_body(req)

  # Validate required fields
  validation <- validate_required(body, c("email", "password"))
  if (!is.null(validation)) {
    return(error_response(res, validation, 400))
  }

  # Find user by email
  user <- db_get_one(
    "SELECT id, full_name, email, password_hash, role FROM users WHERE email = ?",
    params = list(tolower(body$email))
  )

  if (is.null(user)) {
    return(error_response(res, "Invalid email or password", 401))
  }

  # Verify password
  if (!checkpw(body$password, user$password_hash)) {
    return(error_response(res, "Invalid email or password", 401))
  }

  # Generate token
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

#' Get current user profile
#' @get /api/auth/me
#' @serializer unboxedJSON
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

#' Update user profile
#' @put /api/auth/profile
#' @serializer unboxedJSON
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
    # Check if new email is taken by another user
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

  # Return updated user
  user <- db_get_one(
    "SELECT id, full_name, email, role, created_at FROM users WHERE id = ?",
    params = list(user_id)
  )

  return(success_response(data = user, message = "Profile updated successfully"))
}
