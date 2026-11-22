# Feature construction for the credit card default data.
#
# Month index t = 1 is September 2005 (the latest month), t = 6 is April 2005.
# The payment made in month t settles the statement issued in month t + 1, so
# repayment and spending are built from PAY_AMT_t and BILL_AMT_{t+1}.

months <- 1:6

status_levels <- c("no_balance", "paid_full", "revolving", "late")

pay_matrix <- function(x, prefix, t = months) {
  as.matrix(x[paste0(prefix, t)])
}

# PAY_t codes: -2, -1 and 0 are statuses, 1..9 are months of delay.
# The ordering of the codes is not the ordering of risk (0 is safer than -1),
# so they are split into a status and a number of months late.
pay_status <- function(code) {
  s <- ifelse(code <= -2, "no_balance",
       ifelse(code == -1, "paid_full",
       ifelse(code == 0, "revolving", "late")))
  factor(s, levels = status_levels)
}

repayment_ratio <- function(x, cap = 1) {
  pay  <- pay_matrix(x, "PAY_AMT", 1:5)
  owed <- pay_matrix(x, "BILL_AMT", 2:6)
  r <- ifelse(owed > 0, pay / pmax(owed, 1), 1)   # nothing owed counts as settled
  pmin(r, cap)
}

implied_spending <- function(x) {
  bill_now  <- pay_matrix(x, "BILL_AMT", 1:5)
  bill_prev <- pay_matrix(x, "BILL_AMT", 2:6)
  pay       <- pay_matrix(x, "PAY_AMT", 1:5)
  bill_now - bill_prev + pay      # new purchases plus interest and fees
}

slope <- function(m) {
  # least-squares slope over time, oldest month first, one value per row
  tt <- rev(seq_len(ncol(m))) - 1         # column 1 is the latest month
  tt <- tt - mean(tt)
  drop(sweep(m, 1, rowMeans(m)) %*% tt) / sum(tt^2)
}

clean_demographics <- function(x) {
  data.frame(
    education = factor(
      ifelse(x$EDUCATION %in% 1:3, c("graduate", "university", "high_school")[pmax(x$EDUCATION, 1)], "other"),
      levels = c("university", "graduate", "high_school", "other")
    ),
    marriage = factor(
      ifelse(x$MARRIAGE == 1, "married", ifelse(x$MARRIAGE == 2, "single", "other")),
      levels = c("single", "married", "other")
    ),
    age = x$AGE
  )
}

build_features <- function(x) {
  limit <- x$LIMIT_BAL
  code  <- pay_matrix(x, "PAY_")
  delay <- pmax(code, 0)
  util  <- pay_matrix(x, "BILL_AMT") / limit
  repay <- repayment_ratio(x)
  spend <- implied_spending(x) / limit

  out <- data.frame(
    log_limit      = log(limit),
    status_1       = pay_status(code[, 1]),
    delay_1        = delay[, 1],
    max_delay      = apply(delay, 1, max),
    months_late    = rowSums(delay > 0),
    months_full    = rowSums(code == -1),
    months_revolv  = rowSums(code == 0),
    worsening      = as.integer(delay[, 1] > delay[, 2]),
    util_1         = util[, 1],
    util_mean      = rowMeans(util),
    util_slope     = slope(util),
    repay_1        = repay[, 1],
    repay_mean     = rowMeans(repay),
    months_no_pay  = rowSums(pay_matrix(x, "PAY_AMT", 1:5) == 0 & pay_matrix(x, "BILL_AMT", 2:6) > 0),
    spend_1        = spend[, 1],
    spend_mean     = rowMeans(spend)
  )
  cbind(clean_demographics(x), out)
}

# The original columns, without ID, SEX and the target.
raw_features <- function(x) {
  x[setdiff(names(x), c("SEX", "default"))]
}
