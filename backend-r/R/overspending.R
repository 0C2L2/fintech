# ============================================
# Overspending Detection Module
# ============================================

#' Detect overspending issues based on financial rules
#' @param features Named list from build_feature_vector()
#' @return List of overspending flags
detect_overspending <- function(features) {
  cat("\n--- Overspending Detection ---\n")
  cat("  Checking 9 rules against user features...\n")
  # We initialize an empty list to store all the flags (warnings) we find.
  flags <- list()
  
  # Rule 1: Entertainment share
  # %||% is a custom default operator (from rlang or defined in utils.R).
  # If FINANCIAL_RULES$Entertainment is NULL or missing, it defaults to 0.20 (20%).
  ent_rule <- FINANCIAL_RULES$Entertainment %||% 0.20
  
  if (features$entertainment_share > ent_rule) {
    # c() is the combine function in R.
    # Here, we append a new nested list (representing a single flag) to the existing flags list.
    flags <- c(flags, list(list(
      issue = "High entertainment spending",
      severity = "medium",
      # sprintf() formats strings with variables. %.0f%% means "format as a float with 0 decimals, then add a % sign"
      explanation = sprintf(
        "Entertainment accounts for %.0f%% of your spending (threshold: %.0f%%)",
        features$entertainment_share * 100, ent_rule * 100
      ),
      category = "Entertainment",
      value = features$entertainment_share
    )))
  }
  
  # Rule 2: Rent share
  rent_rule <- FINANCIAL_RULES$Rent %||% 0.40
  if (features$rent_share > rent_rule) {
    flags <- c(flags, list(list(
      issue = "High rent burden",
      severity = "high",
      explanation = sprintf(
        "Rent accounts for %.0f%% of your spending (threshold: %.0f%%)",
        features$rent_share * 100, rent_rule * 100
      ),
      category = "Rent",
      value = features$rent_share
    )))
  }
  
  # Rule 3: Savings rate < 10% (when income is set)
  if (features$income > 0 && features$savings_rate < 0.10) {
    flags <- c(flags, list(list(
      issue = "Low savings rate",
      severity = "high",
      explanation = sprintf(
        "Savings rate is %.1f%% (recommended: at least 10%%)",
        features$savings_rate * 100
      ),
      category = "Savings",
      value = features$savings_rate
    )))
  }
  
  # Rule 4: Food share
  food_rule <- FINANCIAL_RULES$Food %||% 0.30
  if (features$food_share > food_rule) {
    flags <- c(flags, list(list(
      issue = "High food spending",
      severity = "medium",
      explanation = sprintf(
        "Food accounts for %.0f%% of your spending (threshold: %.0f%%)",
        features$food_share * 100, food_rule * 100
      ),
      category = "Food",
      value = features$food_share
    )))
  }
  
  # Rule 5: Total expense exceeds income
  if (features$income > 0 && features$total_expense > features$income) {
    flags <- c(flags, list(list(
      issue = "Spending exceeds income",
      severity = "critical",
      explanation = sprintf(
        "Total expenses ($%.0f) exceed income ($%.0f) by $%.0f",
        features$total_expense, features$income,
        features$total_expense - features$income
      ),
      category = "Overall",
      value = features$total_expense / features$income
    )))
  }
  
  # Rule 6: Expense growth > 20% month-over-month
  grow_rule <- 0.20 # Trend rules usually remain fixed
  if (features$expense_growth > grow_rule) {
    flags <- c(flags, list(list(
      issue = "Rapid expense growth",
      severity = "medium",
      explanation = sprintf(
        "Expenses grew %.0f%% compared to last month (threshold: %.0f%%)",
        features$expense_growth * 100, grow_rule * 100
      ),
      category = "Trend",
      value = features$expense_growth
    )))
  }
  
  # Rule 7: Transport share
  trans_rule <- FINANCIAL_RULES$Transport %||% 0.25
  if (features$transport_share > trans_rule) {
    flags <- c(flags, list(list(
      issue = "High transport costs",
      severity = "low",
      explanation = sprintf(
        "Transport accounts for %.0f%% of your spending (threshold: %.0f%%)",
        features$transport_share * 100, trans_rule * 100
      ),
      category = "Transport",
      value = features$transport_share
    )))
  }
  
  # Rule 8: Discretionary spending share
  disc_rule <- FINANCIAL_RULES$Discretionary %||% 0.40
  if (features$total_expense > 0) {
    disc_share <- features$discretionary_spending / features$total_expense
    if (disc_share > disc_rule) {
      flags <- c(flags, list(list(
        issue = "High discretionary spending",
        severity = "medium",
        explanation = sprintf(
          "Discretionary spending is %.0f%% of total (threshold: %.0f%%)",
          disc_share * 100, disc_rule * 100
        ),
        category = "Discretionary",
        value = disc_share
      )))
    }
  }
  
  # Rule 9: Custom Budget Thresholds
  if (!is.null(features$category_breakdown) && length(features$category_breakdown) > 0) {
    for (cat in features$category_breakdown) {
      # Only alert if threshold is set (> 0) and exceeded
      if (!is.null(cat$threshold) && cat$threshold > 0 && cat$amount > cat$threshold) {
        flags <- c(flags, list(list(
          issue = sprintf("Budget exceeded: %s", cat$category),
          severity = "high",
          explanation = sprintf(
            "You spent $%.2f on %s, exceeding your set budget of $%.0f",
            cat$amount, cat$category, cat$threshold
          ),
          category = cat$category,
          value = cat$amount / cat$threshold
        )))
      }
    }
  }
  
  cat("  Total flags triggered:", length(flags), "\n")
  if (length(flags) > 0) {
    for (f in flags) {
      cat("    !", f$issue, "[", f$severity, "]\n")
    }
  } else {
    cat("    No overspending issues detected\n")
  }
  cat("--- Done ---\n")
  return(flags)
}

#' Calculate a financial health score (0-100)
#' @param features Named list from build_feature_vector()
#' @param flags List of overspending flags
#' @return Numeric: score from 0 to 100
calculate_financial_score <- function(features, flags) {
  cat("\n--- Financial Health Score Calculation ---\n")
  score <- 100
  cat("  Starting score: 100\n")
  
  # Deduct points per flag by severity
  for (flag in flags) {
    if (flag$severity == "critical") { score <- score - 25; cat("    -25 (critical):", flag$issue, "\n") }
    else if (flag$severity == "high") { score <- score - 15; cat("    -15 (high):", flag$issue, "\n") }
    else if (flag$severity == "medium") { score <- score - 10; cat("    -10 (medium):", flag$issue, "\n") }
    else if (flag$severity == "low") { score <- score - 5; cat("     -5 (low):", flag$issue, "\n") }
  }
  
  # Bonus points for good savings rate
  if (features$savings_rate > 0.20) { score <- score + 10; cat("    +10 (savings > 20%)\n") }
  if (features$savings_rate > 0.30) { score <- score + 5; cat("     +5 (savings > 30%)\n") }
  
  # Ensure bounds
  score <- max(0, min(100, score))
  
  cat("  Final score:", score, "/ 100\n")
  cat("--- Done ---\n")
  return(round(score))
}

# ============================================
# Human-like diagnostic print: Active Rule Thresholds
# Runs when this module is sourced so an analyst can immediately
# see what thresholds are configured before running any analysis.
# ============================================
cat("\n--- Overspending Rules: Active Thresholds ---\n")
cat(sprintf("  Rule 1  Entertainment share    > %.0f%%   [severity: medium]\n",
    (FINANCIAL_RULES$Entertainment %||% 0.20) * 100))
cat(sprintf("  Rule 2  Rent share             > %.0f%%   [severity: high]\n",
    (FINANCIAL_RULES$Rent %||% 0.40) * 100))
cat(sprintf("  Rule 3  Savings rate           < 10%%   [severity: high]\n"))
cat(sprintf("  Rule 4  Food share             > %.0f%%   [severity: medium]\n",
    (FINANCIAL_RULES$Food %||% 0.30) * 100))
cat(sprintf("  Rule 5  Spending exceeds income         [severity: critical]\n"))
cat(sprintf("  Rule 6  Expense growth MoM     > 20%%   [severity: medium]\n"))
cat(sprintf("  Rule 7  Transport share        > %.0f%%   [severity: low]\n",
    (FINANCIAL_RULES$Transport %||% 0.25) * 100))
cat(sprintf("  Rule 8  Discretionary share   > %.0f%%   [severity: medium]\n",
    (FINANCIAL_RULES$Discretionary %||% 0.40) * 100))
cat(sprintf("  Rule 9  Custom category budget exceeded [severity: high]\n"))
cat("----------------------------------------------\n")

#' Plot frequency of each overspending rule firing across a list of flag batches
#' @param all_flags_list A list-of-lists (each element = flags for one user-month)
#' @param output_path File path to save PNG (e.g. "outputs/flag_frequency.png")
#' Useful for batch admin analysis of seeded or real user data.
plot_flag_frequency <- function(all_flags_list, output_path = "outputs/flag_frequency.png") {
  library(ggplot2)
  library(dplyr)
  
  # Flatten all flags and count by issue label
  issue_counts <- list()
  for (flags in all_flags_list) {
    for (flag in flags) {
      issue <- flag$issue
      sev   <- flag$severity
      key   <- issue
      if (is.null(issue_counts[[key]])) {
        issue_counts[[key]] <- list(count = 0, severity = sev)
      }
      issue_counts[[key]]$count <- issue_counts[[key]]$count + 1
    }
  }
  
  if (length(issue_counts) == 0) {
    cat("No flags found — skipping flag frequency plot.\n")
    return(invisible(NULL))
  }
  
  freq_df <- data.frame(
    Issue    = names(issue_counts),
    Count    = sapply(issue_counts, `[[`, "count"),
    Severity = sapply(issue_counts, `[[`, "severity"),
    stringsAsFactors = FALSE
  )
  freq_df <- freq_df[order(-freq_df$Count), ]
  freq_df$Issue <- factor(freq_df$Issue, levels = rev(freq_df$Issue))
  
  sev_colors <- c(critical = "#dc2626", high = "#f97316", medium = "#eab308", low = "#3b82f6")
  
  cat("\n--- Human-like Diagnostic: Overspending Flag Frequencies ---\n")
  for (i in seq_len(nrow(freq_df))) {
    cat(sprintf("  [%-8s] %-40s  triggered %d times\n",
        freq_df$Severity[i], as.character(freq_df$Issue[i]), freq_df$Count[i]))
  }
  
  p <- ggplot(freq_df, aes(x = Issue, y = Count, fill = Severity)) +
    geom_bar(stat = "identity", alpha = 0.9) +
    coord_flip() +
    scale_fill_manual(values = sev_colors) +
    theme_minimal(base_size = 12) +
    labs(
      title    = "Overspending Rule — Flag Frequency",
      subtitle = "How often each of the 9 rules triggered across the analysed population",
      x = "Rule", y = "Number of times triggered", fill = "Severity"
    ) +
    theme(
      plot.title    = element_text(face = "bold", hjust = 0.5),
      plot.subtitle = element_text(color = "gray40", hjust = 0.5)
    )
  
  dir.create(dirname(output_path), showWarnings = FALSE, recursive = TRUE)
  ggsave(output_path, plot = p, width = 9, height = 6, dpi = 300)
  cat(sprintf("✓ Flag frequency chart saved to %s\n", output_path))
  invisible(p)
}

# ============================================
# Diagnostic Plot: Single User's Overspending Flags
# Call this in RStudio to see a user's flag severity breakdown
# Example: plot_user_flags(flags)
# ============================================
plot_user_flags <- function(flags) {
  library(ggplot2)
  library(plotly)
  
  cat("\n--- Plotting: User Overspending Flags ---\n")
  
  if (length(flags) == 0) {
    cat("No flags to plot — user is clean!\n")
    return(invisible(NULL))
  }
  
  df <- data.frame(
    Issue = sapply(flags, function(f) f$issue),
    Severity = sapply(flags, function(f) f$severity),
    Value = sapply(flags, function(f) round(f$value * 100, 1)),
    stringsAsFactors = FALSE
  )
  
  # Penalty column for bar height
  penalty_map <- c(critical = 25, high = 15, medium = 10, low = 5)
  df$Penalty <- penalty_map[df$Severity]
  df$Issue <- factor(df$Issue, levels = rev(df$Issue))
  
  sev_colors <- c(critical = "#dc2626", high = "#f97316", medium = "#eab308", low = "#3b82f6")
  
  p <- ggplot(df, aes(x = Issue, y = Penalty, fill = Severity)) +
    geom_bar(stat = "identity", alpha = 0.9) +
    coord_flip() +
    scale_fill_manual(values = sev_colors) +
    geom_text(aes(label = paste0("-", Penalty, " pts")), hjust = -0.1, size = 3.5) +
    labs(
      title = "Overspending Flags — Score Deductions",
      subtitle = paste(length(flags), "flags triggered | Total deduction:",
                       sum(df$Penalty), "points"),
      x = "Flag", y = "Points deducted from score"
    ) +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold"))
  
  print(ggplotly(p))
  cat("Plot displayed in Viewer\n")
  return(invisible(p))
}

# ============================================
# Diagnostic Plot: Financial Health Score Gauge
# Shows the 0-100 score as a colored bar
# Example: plot_score_gauge(score)
# ============================================
plot_score_gauge <- function(score) {
  library(ggplot2)
  library(plotly)
  
  cat("\n--- Plotting: Financial Health Score ---\n")
  cat("  Score:", score, "/ 100\n")
  
  # Determine color zone
  color <- if (score >= 80) "#10b981"
           else if (score >= 60) "#eab308"
           else if (score >= 40) "#f97316"
           else "#dc2626"
  
  label <- if (score >= 80) "Excellent"
           else if (score >= 60) "Good"
           else if (score >= 40) "Fair"
           else "Poor"
  
  df <- data.frame(
    Category = c("Score", "Remaining"),
    Value = c(score, 100 - score)
  )
  
  p <- ggplot(df, aes(x = "", y = Value, fill = Category)) +
    geom_bar(stat = "identity", width = 0.4) +
    coord_flip() +
    scale_fill_manual(values = c("Score" = color, "Remaining" = "#1e1b4b")) +
    labs(
      title = paste("Financial Health Score:", score, "/", "100"),
      subtitle = paste("Rating:", label),
      x = "", y = ""
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 16),
      legend.position = "none",
      axis.text = element_blank(),
      panel.grid = element_blank()
    )
  
  print(ggplotly(p))
  cat("Plot displayed in Viewer\n")
  return(invisible(p))
}

