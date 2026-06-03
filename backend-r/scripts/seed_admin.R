setwd("C:/Users/rashi/Desktop/finteach/backend-r")
source("R/db.R")
library(bcrypt)

admin_email <- "admin@finteach.com"
pw_hash <- hashpw("admin123")

# Check if admin already exists
if (db_exists("users", "email", admin_email)) {
  cat("Admin account already exists!\n")
} else {
  db_execute(
    "INSERT INTO users (id, full_name, email, password_hash, role, created_at, updated_at) VALUES (?, ?, ?, ?, 'admin', datetime('now'), datetime('now'))",
    params = list(new_uuid(), "System Admin", admin_email, pw_hash)
  )
  cat("Admin account created successfully!\n")
  cat("Email:", admin_email, "\n")
  cat("Password: admin123\n")
}
