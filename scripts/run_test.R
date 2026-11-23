# Class imbalance study (cross-validation on the training set), then the final
# fit on the whole training set and the single evaluation on the test set.
#
#   Rscript scripts/run_cv.R      # first
#   Rscript scripts/run_test.R
#
# Writes results/imbalance.rds and results/test.rds.

source("R/features.R")
source("R/protocol.R")
source("R/metrics.R")
source("R/models.R")
source("R/imbalance.R")

cv <- readRDS("results/cv.rds")
x <- readRDS("data/credit.rds")
is_test <- cv$is_test
train <- x[!is_test, ]
test <- x[is_test, ]
y <- train$default
fold <- cv$fold
K <- max(fold)

f_train <- build_features(train)
f_test <- build_features(test)
X <- xgb_matrix(f_train)
X_test <- xgb_matrix(f_test)

best_xgb <- cv$tuning$xgb_engineered$best
best_logit <- cv$tuning$logit_engineered$best
w <- sum(y == 0) / sum(y == 1)

# ---- imbalance: none, class weights, SMOTE-NC, all with the same booster ----

fit_variant <- function(Xtr, ytr, variant, seed) {
  if (variant == "smote") {
    syn <- smote_nc(Xtr, ytr, seed = seed)
    Xtr <- rbind(Xtr, syn)
    ytr <- c(ytr, rep(1, nrow(syn)))
  }
  weight <- if (variant == "weights") ifelse(ytr == 1, sum(ytr == 0) / sum(ytr == 1), 1) else NULL
  params <- xgb_params(best_xgb)
  params$seed <- seed
  xgb.train(params, xgb.DMatrix(Xtr, label = ytr, weight = weight),
            nrounds = best_xgb$nrounds, verbose = 0)
}

variants <- c("none", "weights", "smote")
imb <- sapply(variants, function(v) {
  p <- numeric(length(y))
  for (k in 1:K) {
    tr <- fold != k
    p[!tr] <- predict(fit_variant(X[tr, ], y[tr], v, seed = k), X[!tr, ])
  }
  cat("imbalance:", v, "done\n")
  p
})

saveRDS(list(y = y, oof = imb, w = w), "results/imbalance.rds", compress = "xz")

# ---- final models on the whole training set, scored once on the test set ----

xgb_final <- fit_xgb(X, y, best_xgb, best_xgb$nrounds)
logit_final <- fit_logit(f_train, y, best_logit$alpha, best_logit$lambda)
late_tr <- train$PAY_1 >= 2

pred <- list(
  constant = rep(mean(y), nrow(test)),
  rule     = ifelse(test$PAY_1 >= 2, mean(y[late_tr]), mean(y[!late_tr])),
  logit    = predict(logit_final, f_test),
  xgb      = predict(xgb_final, X_test)
)

saveRDS(list(y = test$default, pred = pred, oof = list(logit = cv$oof$logit_engineered, xgb = cv$oof$xgb_engineered)),
        "results/test.rds", compress = "xz")
xgb.save(xgb_final, "results/xgb_final.ubj")
saveRDS(logit_final, "results/logit_final.rds", compress = "xz")

print(round(t(sapply(pred, function(p) scores(test$default, p))), 4))
