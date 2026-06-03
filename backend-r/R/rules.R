# ============================================
# Financial Rules & Thresholds Constants
# ============================================

# These percentages represent the AI's default "safe" spending limits for various categories.
# They are used both for generating overspending alerts and for suggesting budgets to the user.

FINANCIAL_RULES <- list(
  Rent = 0.40, # Max 40% for Rent
  Transport = 0.25, # Max 25% for Transport
  Food = 0.30, # Max 30% for Food
  Education = 0.15, # Max 15% for Education
  Entertainment = 0.20, # Max 20% for Entertainment
  Discretionary = 0.40, # Max 40% total for all non-essential items
  Overall = 1.00 # Total expenses should not exceed 100% of income
)

# Print all rules when this module loads
cat("\n--- Financial Rules Loaded ---\n")
cat("  These thresholds define what triggers an overspending alert:\n")
for (rule_name in names(FINANCIAL_RULES)) {
  cat("  ", rule_name, ": max", FINANCIAL_RULES[[rule_name]] * 100, "% of expenses/income\n")
}
cat("  Total rules:", length(FINANCIAL_RULES), "\n")
cat("-------------------------------\n")

#' Get the default percentage for a category name
#' @param name Category name
#' @return Numeric percentage (0-1) or 0 if no rule exists
get_default_percent <- function(name) {
  # Normalize name (lowercase)
  rules_names <- names(FINANCIAL_RULES)
  match <- rules_names[tolower(rules_names) == tolower(trimws(name))]

  if (length(match) > 0) {
    cat("  Rule lookup:", name, "-> threshold =", FINANCIAL_RULES[[match[1]]] * 100, "%\n")
    return(FINANCIAL_RULES[[match[1]]])
  }
  cat("  Rule lookup:", name, "-> no rule found, returning 0\n")
  return(0)
}
