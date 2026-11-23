# Reading the fitted models.

# Name of the original feature behind each column of xgb_matrix(df).
feature_groups <- function(df) {
  unlist(lapply(names(df), function(name) {
    v <- df[[name]]
    if (is.factor(v)) rep(name, nlevels(v)) else name
  }))
}

# Contribution of one feature to the log-odds of the logistic regression, as a
# function of its value, the other features held fixed. Centred at the median
# of the training data so that curves of different features can be compared.
logit_partial <- function(model, feature, values, reference) {
  p <- model$prep[[feature]]
  b <- as.matrix(coef(model$fit, s = model$lambda))[, 1]
  one <- data.frame(v = values)
  names(one) <- feature
  X <- prep_logit_apply(model$prep[feature], one)
  X0 <- prep_logit_apply(model$prep[feature], setNames(data.frame(reference), feature))
  drop(X %*% b[colnames(X)]) - drop(X0 %*% b[colnames(X0)])
}

# SHAP values of an xgboost model, summed over the columns of each feature.
shap_by_feature <- function(model, X, groups) {
  sh <- predict(model, X, predcontrib = TRUE)
  sh <- sh[, colnames(sh) != "(Intercept)", drop = FALSE]
  out <- sapply(unique(groups), function(g) rowSums(sh[, groups == g, drop = FALSE]))
  colnames(out) <- unique(groups)
  out
}
