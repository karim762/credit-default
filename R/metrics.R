# Scores for predicted default probabilities p against outcomes y in {0, 1}.

log_loss <- function(y, p, eps = 1e-15) {
  p <- pmin(pmax(p, eps), 1 - eps)
  -mean(y * log(p) + (1 - y) * log(1 - p))
}

brier <- function(y, p) mean((p - y)^2)

auc <- function(y, p) {
  r <- rank(p)
  n1 <- sum(y == 1)
  n0 <- length(y) - n1
  (sum(r[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}

scores <- function(y, p) {
  c(log_loss = log_loss(y, p), brier = brier(y, p), auc = auc(y, p))
}
