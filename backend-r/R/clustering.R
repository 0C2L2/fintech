# ============================================
# K-Means Clustering Module
# ============================================

library(cluster)

# Cluster label mapping
CLUSTER_LABELS <- c(
  "Balanced Budgeter",
  "High Saver",
  "Rent-Burdened User",
  "Entertainment-Heavy Spender"
)

#' Assign financial segment to a user based on features
#' @param features Named list from build_feature_vector()
#' @return Character string: cluster label
assign_cluster <- function(features) {
  cat("\n--- Cluster Assignment ---\n")
  # Try loading saved model
  model_path <- file.path(dirname(getwd()), "backend-r", "models", "kmeans_model.rds")
  scaler_path <- file.path(dirname(getwd()), "backend-r", "models", "scaler_params.rds")
  
  if (file.exists(model_path) && file.exists(scaler_path)) {
    # Use trained model
    tryCatch({
      model <- readRDS(model_path)
      scaler <- readRDS(scaler_path)
      cat("  K-Means model loaded (k=", length(model$size), "clusters)\n")
      
      # Prepare feature vector (fully aligned with the 12 Kaggle cluster features)
      feature_vec <- data.frame(
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
        savings_rate = features$savings_rate
      )
      
      # Scale using saved parameters. We MUST subtract the exact same mean and divide by the exact same standard deviation 
      # that the training data used, otherwise the Euclidean distance calculation will be completely wrong.
      scaled <- scale(feature_vec, center = scaler$center, scale = scaler$scale)
      scaled[is.nan(scaled)] <- 0
      
      # Manual distance calculation (Euclidean distance to each of the 4 centroids)
      # We don't re-run K-Means for a single user. Instead, we measure the straight-line distance
      # from their scaled data point to the center of each of the 4 clusters.
      # apply(X, MARGIN=1, FUN) runs a function over rows (MARGIN=1) of a matrix.
      # sum((scaled_row - centroid_row)^2) is the squared Euclidean distance formula.
      dists <- apply(model$centers, 1, function(c) sum((scaled - c)^2))
      
      cat("  Distances to centroids:\n")
      for(i in seq_along(dists)) {
        cat("    - Cluster", i, "distance:", round(dists[i], 2), "\n")
      }
      
      # which.min() finds the index (1, 2, 3, or 4) of the smallest distance. 
      # The closest centroid is the user's assigned cluster!
      cluster_id <- which.min(dists)
      
      if (cluster_id <= length(CLUSTER_LABELS)) {
        cat("  Assigned label:", CLUSTER_LABELS[cluster_id], "\n")
        cat("--- Done ---\n")
        return(CLUSTER_LABELS[cluster_id])
      }
      
      cat("  Assigned label:", CLUSTER_LABELS[1], "(default)\n")
      cat("--- Done ---\n")
      return(CLUSTER_LABELS[1])
    }, error = function(e) {
      cat("  Model error, using rule-based fallback\n")
      message("Clustering model error, falling back to rules: ", e$message)
      return(rule_based_segment(features))
    })
  } else {
    cat("  No model files found, using rule-based fallback\n")
    return(rule_based_segment(features))
  }
}

#' Rule-based segmentation fallback
#' @param features Named list from build_feature_vector()
#' @return Character string: segment label
rule_based_segment <- function(features) {
  cat("  Rule-based segmentation:\n")
  savings_rate <- features$savings_rate
  rent_share <- features$rent_share
  entertainment_share <- features$entertainment_share
  food_share <- features$food_share
  cat("    savings_rate=", round(savings_rate * 100, 1), "% | rent_share=", round(rent_share * 100, 1),
      "% | ent_share=", round(entertainment_share * 100, 1), "%\n")
  
  # High Saver: savings rate > 25%
  if (savings_rate > 0.25) {
    return("High Saver")
  }
  
  # Rent-Burdened: rent > 40% of expenses
  if (rent_share > 0.40) {
    return("Rent-Burdened User")
  }
  
  # Entertainment-Heavy: entertainment > 20% of expenses
  if (entertainment_share > 0.20) {
    return("Entertainment-Heavy Spender")
  }
  
  # Default: Balanced Budgeter
  return("Balanced Budgeter")
}

# ============================================
# Diagnostic Plot: User vs Cluster Centroids
# Call this in RStudio to see where a user falls
# Example: plot_user_vs_clusters(features)
# ============================================
plot_user_vs_clusters <- function(features) {
  library(ggplot2)
  library(plotly)
  
  cat("\n--- Plotting: User vs Cluster Centroids ---\n")
  
  # Load model
  model_path <- file.path(dirname(getwd()), "backend-r", "models", "kmeans_model.rds")
  scaler_path <- file.path(dirname(getwd()), "backend-r", "models", "scaler_params.rds")
  
  if (!file.exists(model_path)) {
    cat("No model found. Run train_clustering.R first.\n")
    return(invisible(NULL))
  }
  
  model <- readRDS(model_path)
  scaler <- readRDS(scaler_path)
  
  # Feature names
  feat_names <- c("rent_share", "loan_repayment_share", "insurance_share",
                  "groceries_share", "transport_share", "eating_out_share",
                  "entertainment_share", "utilities_share", "healthcare_share",
                  "education_share", "miscellaneous_share", "savings_rate")
  
  # Un-scale centroids back to original values
  centers <- model$centers
  for (j in 1:ncol(centers)) {
    centers[, j] <- centers[, j] * scaler$scale[j] + scaler$center[j]
  }
  
  # Build comparison data frame
  plot_data <- data.frame(
    Feature = character(),
    Value = numeric(),
    Source = character(),
    stringsAsFactors = FALSE
  )
  
  # Add cluster centroids
  for (k in 1:nrow(centers)) {
    for (f in feat_names) {
      plot_data <- rbind(plot_data, data.frame(
        Feature = gsub("_", " ", f),
        Value = centers[k, f],
        Source = paste("Cluster", k),
        stringsAsFactors = FALSE
      ))
    }
  }
  
  # Add current user
  for (f in feat_names) {
    plot_data <- rbind(plot_data, data.frame(
      Feature = gsub("_", " ", f),
      Value = features[[f]],
      Source = "THIS USER",
      stringsAsFactors = FALSE
    ))
  }
  
  p <- ggplot(plot_data, aes(x = Feature, y = Value, fill = Source)) +
    geom_bar(stat = "identity", position = "dodge", alpha = 0.85) +
    coord_flip() +
    scale_y_continuous(labels = function(x) paste0(round(x * 100), "%")) +
    labs(
      title = "User Spending Profile vs Cluster Centroids",
      subtitle = "Compare this user's shares against the 4 K-Means cluster centers",
      x = "Feature", y = "Share / Rate (%)"
    ) +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold"))
  
  print(ggplotly(p))
  cat("Plot displayed in Viewer\n")
  return(invisible(p))
}
