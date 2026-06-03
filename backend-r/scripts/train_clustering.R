# -----------------------------------------------
# train_clustering.R
# This script trains a K-Means model to group users
# into 4 spending personality clusters.
# Run preprocess_data.R first before this!
# -----------------------------------------------

library(cluster)
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
cat("\n=== Training K-Means Clustering ===\n")

features_csv <- file.path("data", "kaggle_preprocessed_features.csv")

if (!file.exists(features_csv)) {
  stop("File not found! Please run preprocess_data.R first.")
}

data_df <- read.csv(features_csv, stringsAsFactors = FALSE)
cat("Loaded", nrow(data_df), "rows\n")

# Quick look at the data
cat("\n--- First 3 rows ---\n")
print(head(data_df, 3))

cat("\n--- Missing values check ---\n")
print(colSums(is.na(data_df)))


# -----------------------------------------------
# Step 2: Pick the features we use for clustering
# We use 11 spending category shares + savings rate
# These are all between 0 and 1, no units needed
# -----------------------------------------------
cat("\n--- Features used for clustering ---\n")

cluster_features <- c(
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
  "savings_rate"
)

for (i in seq_along(cluster_features)) {
  cat(" ", i, ".", cluster_features[i], "\n")
}

# Pull out only those columns
data_subset <- data_df[, cluster_features]

cat("\nRows with complete data:", sum(complete.cases(data_subset)), "/", nrow(data_subset), "\n")
cat("\n--- Summary of clustering features ---\n")
print(summary(data_subset))


# -----------------------------------------------
# Step 3: Scale the features
# K-Means needs scaled data so no feature dominates
# scale() subtracts mean and divides by sd for each column
# -----------------------------------------------
cat("\nScaling features...\n")

# scale() is a base R function that standardizes continuous variables.
# For each column, it subtracts the column's mean (centering) and divides by the standard deviation (scaling).
# This transforms all variables to have a mean of 0 and a standard deviation of 1.
# It returns a matrix with attributes attached for the center and scale used.
scaled_data <- scale(data_subset)

# attr() extracts attributes attached to an R object.
# Here we extract the "scaled:center" (the means) and "scaled:scale" (the standard deviations)
# that scale() calculated, so we can save them in a list and apply the exact same math to future users.
scaler_params <- list(
  center = attr(scaled_data, "scaled:center"),
  scale  = attr(scaled_data, "scaled:scale")
)

cat("Scaling done. Mean and SD saved:\n")
cat("  Center (mean) values:\n")
print(round(scaler_params$center, 4))
cat("  Scale (sd) values:\n")
print(round(scaler_params$scale, 4))


# -----------------------------------------------
# Step 4: Train K-Means with k=4
# We use 4 clusters because we want 4 user personas:
#   - High Saver, Rent Burdened, Entertainment Heavy, Balanced
# nstart=25 means we try 25 random starts and pick the best
# -----------------------------------------------
cat("\nTraining K-Means with k=4, nstart=25...\n")

# set.seed() ensures reproducibility. K-Means uses random initial centroid placements.
# By setting a fixed seed, we ensure the algorithm produces the exact same clusters every time we run this script.
set.seed(42)

# kmeans() is the core unsupervised clustering algorithm in R.
# - scaled_data: the numeric matrix we are clustering
# - centers = 4: we are asking for exactly 4 groups (k=4)
# - nstart = 25: the algorithm will run 25 times with different random starting points and keep the best one (lowest variance)
# - iter.max = 100: allows up to 100 iterations per run to let centroids converge
km_model <- kmeans(scaled_data, centers = 4, nstart = 25, iter.max = 100)

cat("Training done!\n")


# -----------------------------------------------
# Step 5: Check how good the clusters are
# -----------------------------------------------
cat("\n--- Cluster sizes ---\n")
for (i in 1:4) {
  cat("  Cluster", i, "has", km_model$size[i], "members\n")
}

cat("\n--- Within-cluster sum of squares per cluster (lower = tighter clusters) ---\n")
for (i in 1:4) {
  cat("  Cluster", i, ":", round(km_model$withinss[i], 2), "\n")
}

# Extract variance metrics from the km_model object:
# totss: Total sum of squares (total variance in the entire dataset)
# betweenss: Between-cluster sum of squares (how far apart the clusters are from each other)
# tot.withinss: Total within-cluster sum of squares (how spread out data points are inside their own clusters)
total_ss <- km_model$totss
between_ss <- km_model$betweenss
within_ss <- km_model$tot.withinss

# The "variance explained" is the ratio of between-cluster variance to total variance.
# A higher percentage means the clusters are tight and well-separated.
explained_pct <- round((between_ss / total_ss) * 100, 1)

cat("\n  Total SS:         ", round(total_ss, 2), "\n")
cat("  Within-cluster SS:", round(within_ss, 2), "\n")
cat("  Between-cluster SS:", round(between_ss, 2), "\n")
cat("  Variance explained:", explained_pct, "%\n")
cat("  (Anything above 50% means clusters are well separated)\n")


# -----------------------------------------------
# Step 6: Look at cluster centers
# Un-scale them back to original units so we can understand them
# -----------------------------------------------
cat("\n--- Cluster centers (original scale) ---\n")

# Reverse the scaling: multiply by sd, then add mean
centers_unscaled <- km_model$centers
for (j in 1:ncol(centers_unscaled)) {
  centers_unscaled[, j] <- centers_unscaled[, j] * scaler_params$scale[j] + scaler_params$center[j]
}

print(round(centers_unscaled, 3))


# -----------------------------------------------
# Step 7: Save the model files
# -----------------------------------------------
dir.create("models", showWarnings = FALSE)

saveRDS(km_model, "models/kmeans_model.rds")
saveRDS(scaler_params, "models/scaler_params.rds")

cat("\nSaved: models/kmeans_model.rds\n")
cat("Saved: models/scaler_params.rds\n")


# -----------------------------------------------
# Step 8: Plot the cluster centroids
# This shows what each cluster looks like visually
# -----------------------------------------------
cat("\nMaking cluster centroid plot...\n")

# Build a simple data frame for ggplot
centers_df <- as.data.frame(centers_unscaled)
centers_df$Cluster <- paste("Cluster", 1:4)

# Turn wide format to long format so ggplot can use it
centers_long <- data.frame(
  Cluster = character(),
  Feature = character(),
  Value = numeric(),
  stringsAsFactors = FALSE
)

for (i in 1:4) {
  for (feat in cluster_features) {
    new_row <- data.frame(
      Cluster = paste("Cluster", i),
      Feature = gsub("_", " ", feat),
      Value = centers_unscaled[i, feat],
      stringsAsFactors = FALSE
    )
    centers_long <- rbind(centers_long, new_row)
  }
}

p <- ggplot(centers_long, aes(x = Feature, y = Value, fill = Cluster)) +
  geom_bar(stat = "identity", position = "dodge", alpha = 0.9) +
  coord_flip() +
  scale_fill_brewer(palette = "Set2") +
  scale_y_continuous(labels = function(x) paste0(round(x * 100), "%")) +
  labs(
    title = "K-Means Cluster Centroids",
    subtitle = paste("Variance explained:", explained_pct, "% | 4 clusters × 12 features"),
    x = "Feature",
    y = "Average share / rate (%)"
  ) +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold", hjust = 0.5))

print(ggplotly(p)) # interactive — zoom, hover to compare clusters
dir.create("outputs", showWarnings = FALSE)
ggsave("outputs/cluster_centroids.png", plot = p, width = 9, height = 6)
cat("Saved: outputs/cluster_centroids.png\n")

cat("\n=== Clustering training done! ===\n")
