# From probabilities to decisions.
#
# For each client the bank either keeps the account as it is or acts on it
# (cuts the limit, freezes the card, starts collection early). Per unit of
# exposure E:
#
#   keep, client repays    +r      value of keeping a good client
#   keep, client defaults  -1      loss given default, taken as the unit
#   act                     0      exposure removed, no gain and no loss
#
# r is the cost ratio: what acting on a good client costs, relative to what a
# default costs. Acting is worth it when p > r / (1 + r).

cost_threshold <- function(r) r / (1 + r)

# Value of a policy, in units of loss given default times exposure.
policy_value <- function(y, exposure, act, r) {
  sum((!act) * ((1 - y) * r - y) * exposure)
}

# Thresholds on a grid, each evaluated with the value it is meant to maximise.
best_threshold <- function(y, p, exposure, r, grid = seq(0.01, 0.9, by = 0.005)) {
  v <- sapply(grid, function(t) policy_value(y, exposure, p > t, r))
  grid[which.max(v)]
}
