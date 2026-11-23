# Class imbalance: SMOTE for mixed data and the prior correction.

# SMOTE (Chawla et al., 2002) with the nominal handling of SMOTE-NC: continuous
# columns are interpolated between a minority client and one of its k nearest
# minority neighbours, while integer-valued columns (counts, flags, one-hot
# levels, months of delay) are copied as a block from whichever of the two is
# nearer to the interpolated point. Interpolating them would create clients who
# are 2.4 months late or 0.3 married.
#
# Returns the minority rows needed to balance the classes.
smote_nc <- function(X, y, k = 5, seed = 1) {
  set.seed(seed)
  minority <- X[y == 1, , drop = FALSE]
  n_new <- sum(y == 0) - sum(y == 1)
  discrete <- apply(X, 2, function(v) all(v == round(v)))
  scale <- apply(X, 2, sd)
  scale[scale == 0] <- 1
  nn <- FNN::get.knn(sweep(minority, 2, scale, "/"), k = k)$nn.index

  i <- sample.int(nrow(minority), n_new, replace = TRUE)
  j <- nn[cbind(i, sample.int(k, n_new, replace = TRUE))]
  u <- runif(n_new)

  out <- minority[i, , drop = FALSE]
  out[, !discrete] <- minority[i, !discrete] + u * (minority[j, !discrete] - minority[i, !discrete])
  from_j <- u > 0.5
  out[from_j, discrete] <- minority[j[from_j], discrete]
  out
}

# A model trained with the positives weighted by w, or with the positives
# oversampled w times, estimates odds that are w times too large. Dividing the
# odds by w recovers probabilities on the original scale.
prior_correct <- function(p, w) {
  p / (p + w * (1 - p))
}

# Calibration intercept and slope: logistic regression of the outcome on the
# predicted log-odds. A calibrated model has intercept 0 and slope 1.
calibration_fit <- function(y, p) {
  eta <- qlogis(pmin(pmax(p, 1e-6), 1 - 1e-6))
  slope <- unname(coef(glm(y ~ eta, family = binomial))[2])
  intercept <- unname(coef(glm(y ~ offset(eta), family = binomial))[1])
  c(intercept = intercept, slope = slope)
}

# Mean predicted probability and observed default rate by bins of prediction.
reliability <- function(y, p, n_bins = 10) {
  bin <- cut(p, unique(quantile(p, seq(0, 1, length.out = n_bins + 1))), include.lowest = TRUE)
  data.frame(
    predicted = tapply(p, bin, mean),
    observed  = tapply(y, bin, mean),
    n         = as.vector(table(bin))
  )
}
