# Train/test split and cross-validation folds, both stratified on the target.

stratified_split <- function(y, test_share = 0.25, seed = 2005) {
  set.seed(seed)
  test <- unlist(lapply(split(seq_along(y), y), function(i) sample(i, round(test_share * length(i)))))
  is_test <- logical(length(y))
  is_test[test] <- TRUE
  is_test
}

stratified_folds <- function(y, k = 5, seed = 2005) {
  set.seed(seed)
  fold <- integer(length(y))
  for (i in split(seq_along(y), y)) {
    fold[i] <- sample(rep_len(seq_len(k), length(i)))
  }
  fold
}
