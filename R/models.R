# Penalised logistic regression (glmnet) and gradient boosting (xgboost).
#
# Every preprocessing step that looks at the data (quantiles, spline knots) is
# fitted on the training rows only and then applied to new rows.

library(glmnet)
library(xgboost)

# ---- preprocessing -----------------------------------------------------------

# For the logistic regression: factors become dummies, continuous columns are
# winsorised at the 0.5% and 99.5% quantiles and expanded in a natural cubic
# spline, so that the model is additive but not linear. Count-like columns with
# few values are kept as they are.
prep_logit_fit <- function(df, df_spline = 4, min_unique = 12) {
  lapply(df, function(v) {
    if (is.factor(v)) return(list(type = "factor", levels = levels(v)))
    if (length(unique(v)) < min_unique) return(list(type = "plain"))
    lim <- quantile(v, c(0.005, 0.995), names = FALSE)
    w <- pmin(pmax(v, lim[1]), lim[2])
    # interior knots at quantiles of the distinct values: several features have
    # a mass point (a ratio of exactly 1, a balance of 0) that would otherwise
    # pull every knot onto the same value
    inner <- quantile(unique(w), seq_len(df_spline - 1) / df_spline, names = FALSE)
    basis <- splines::ns(w, knots = inner, Boundary.knots = lim)
    list(type = "spline", lim = lim, basis = basis)
  })
}

prep_logit_apply <- function(prep, df) {
  cols <- Map(function(p, v, name) {
    m <- switch(p$type,
      factor = sapply(p$levels[-1], function(l) as.numeric(v == l)),
      plain  = matrix(as.numeric(v)),
      spline = predict(p$basis, pmin(pmax(v, p$lim[1]), p$lim[2]))
    )
    m <- matrix(m, nrow = length(v))
    colnames(m) <- if (ncol(m) == 1) name else paste0(name, "_", if (p$type == "factor") p$levels[-1] else seq_len(ncol(m)))
    m
  }, prep, df[names(prep)], names(prep))
  do.call(cbind, cols)
}

# For boosting: trees need no scaling, factors become one column per level.
xgb_matrix <- function(df) {
  cols <- lapply(names(df), function(name) {
    v <- df[[name]]
    if (!is.factor(v)) return(setNames(data.frame(as.numeric(v)), name))
    setNames(as.data.frame(sapply(levels(v), function(l) as.numeric(v == l))), paste0(name, "_", levels(v)))
  })
  as.matrix(do.call(cbind, cols))
}

# ---- logistic regression -----------------------------------------------------

# Out-of-fold log loss along a common lambda path, for each alpha. Returns the
# grid with its cross-validated log loss.
tune_logit <- function(df, y, fold, alphas = c(0, 0.5, 1), n_lambda = 60) {
  X_all <- prep_logit_apply(prep_logit_fit(df), df)
  out <- list()
  for (a in alphas) {
    lambda <- glmnet(X_all, y, family = "binomial", alpha = a, nlambda = n_lambda)$lambda
    oof <- matrix(NA_real_, length(y), length(lambda))
    for (k in sort(unique(fold))) {
      tr <- fold != k
      prep <- prep_logit_fit(df[tr, , drop = FALSE])
      fit <- glmnet(prep_logit_apply(prep, df[tr, , drop = FALSE]), y[tr],
                    family = "binomial", alpha = a, lambda = lambda)
      oof[!tr, ] <- predict(fit, prep_logit_apply(prep, df[!tr, , drop = FALSE]), type = "response")
    }
    ll <- apply(oof, 2, function(p) log_loss(y, p))
    out[[length(out) + 1]] <- data.frame(alpha = a, lambda = lambda, log_loss = ll)
  }
  do.call(rbind, out)
}

fit_logit <- function(df, y, alpha, lambda) {
  prep <- prep_logit_fit(df)
  X <- prep_logit_apply(prep, df)
  # glmnet is more stable when fitted along a path ending at the chosen lambda
  path <- exp(seq(log(max(lambda * 50, 0.1)), log(lambda), length.out = 30))
  fit <- glmnet(X, y, family = "binomial", alpha = alpha, lambda = path)
  structure(list(prep = prep, fit = fit, lambda = lambda), class = "logit_model")
}

predict.logit_model <- function(object, newdata, ...) {
  X <- prep_logit_apply(object$prep, newdata)
  as.vector(predict(object$fit, X, s = object$lambda, type = "response"))
}

# ---- gradient boosting -------------------------------------------------------

xgb_grid <- function(n, seed = 1) {
  set.seed(seed)
  data.frame(
    max_depth        = sample(2:6, n, replace = TRUE),
    min_child_weight = round(exp(runif(n, log(1), log(50))), 1),
    subsample        = round(runif(n, 0.6, 1), 2),
    colsample_bytree = round(runif(n, 0.5, 1), 2),
    lambda           = round(exp(runif(n, log(0.1), log(20))), 2),
    gamma            = ifelse(runif(n) < 0.5, 0, round(exp(runif(n, log(0.01), log(2))), 3))
  )
}

xgb_params <- function(row, eta = 0.03, nthread = 2) {
  list(objective = "binary:logistic", eval_metric = "logloss", eta = eta,
       max_depth = row$max_depth, min_child_weight = row$min_child_weight,
       subsample = row$subsample, colsample_bytree = row$colsample_bytree,
       lambda = row$lambda, gamma = row$gamma, nthread = nthread)
}

# Cross-validated log loss of each configuration, with the number of trees
# chosen by early stopping on the mean validation loss.
tune_xgb <- function(X, y, fold, grid, eta = 0.03, max_rounds = 3000, seed = 1) {
  dtrain <- xgb.DMatrix(X, label = y)
  folds <- lapply(sort(unique(fold)), function(k) which(fold == k))
  res <- lapply(seq_len(nrow(grid)), function(i) {
    set.seed(seed + i)
    cv <- xgb.cv(xgb_params(grid[i, ], eta), dtrain, nrounds = max_rounds, folds = folds,
                 early_stopping_rounds = 100, verbose = FALSE)
    log <- cv$evaluation_log
    best <- which.min(log$test_logloss_mean)
    data.frame(grid[i, ], nrounds = best, log_loss = log$test_logloss_mean[best])
  })
  do.call(rbind, res)
}

fit_xgb <- function(X, y, row, nrounds, eta = 0.03, seed = 1) {
  set.seed(seed)
  params <- xgb_params(row, eta)
  params$seed <- seed
  xgb.train(params, xgb.DMatrix(X, label = y), nrounds = nrounds, verbose = 0)
}
