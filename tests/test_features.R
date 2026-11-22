# Run from the repository root:
#   Rscript -e 'testthat::test_file("tests/test_features.R")'

library(testthat)
source(test_path("..", "R", "features.R"))

one_client <- function(bill, pay, code = rep(0, 6), limit = 1000) {
  x <- data.frame(LIMIT_BAL = limit, SEX = 1, EDUCATION = 2, MARRIAGE = 1, AGE = 30)
  for (t in 1:6) {
    x[[paste0("PAY_", t)]] <- code[t]
    x[[paste0("BILL_AMT", t)]] <- bill[t]
    x[[paste0("PAY_AMT", t)]] <- pay[t]
  }
  x$default <- 0
  x
}

test_that("payments are matched with the previous statement", {
  # statement of month t + 1 is paid in full in month t
  x <- one_client(bill = c(60, 50, 40, 30, 20, 10), pay = c(50, 40, 30, 20, 10, 0))
  expect_equal(unname(repayment_ratio(x)[1, ]), rep(1, 5))
})

test_that("a statement with nothing owed counts as settled", {
  x <- one_client(bill = c(100, 0, -20, 50, 50, 50), pay = c(0, 0, 0, 0, 0, 0))
  expect_equal(unname(repayment_ratio(x)[1, 1:2]), c(1, 1))
  expect_equal(unname(repayment_ratio(x)[1, 3]), 0)
})

test_that("implied spending recovers purchases from the balance identity", {
  # balance 100, pays 30, buys 50: next statement 120
  x <- one_client(bill = c(120, 100, 100, 100, 100, 100), pay = c(30, 0, 0, 0, 0, 0))
  expect_equal(unname(implied_spending(x)[1, 1]), 50)
})

test_that("status codes are split into status and months late", {
  expect_equal(as.character(pay_status(c(-2, -1, 0, 1, 3))),
               c("no_balance", "paid_full", "revolving", "late", "late"))
  x <- one_client(bill = rep(100, 6), pay = rep(0, 6), code = c(3, 2, 0, -1, 0, 0))
  f <- build_features(x)
  expect_equal(f$delay_1, 3)
  expect_equal(f$max_delay, 3)
  expect_equal(f$months_late, 2)
  expect_equal(f$worsening, 1)
})

test_that("utilisation slope is positive when the balance grows", {
  x <- one_client(bill = c(600, 500, 400, 300, 200, 100), pay = rep(0, 6))
  expect_equal(build_features(x)$util_slope, 0.1)
})

test_that("SEX and the target are not model inputs", {
  x <- one_client(bill = rep(100, 6), pay = rep(0, 6))
  expect_false(any(c("SEX", "default") %in% names(raw_features(x))))
  expect_false(any(c("SEX", "sex", "default") %in% names(build_features(x))))
})
