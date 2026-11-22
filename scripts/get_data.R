# Download the UCI "default of credit card clients" data set (Yeh & Lien, 2009)
# and store it as data/credit.rds.
#
#   Rscript scripts/get_data.R
#
# The raw spreadsheet is checked against its MD5 and against a few totals that
# any untouched copy must reproduce, so a modified mirror cannot slip through.

url <- "https://archive.ics.uci.edu/static/public/350/default+of+credit+card+clients.zip"
xls_name <- "default of credit card clients.xls"
xls_md5 <- "b81a8619fcef71f222f549b7a9aed1e0"

raw_dir <- file.path("data", "raw")
dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
xls_path <- file.path(raw_dir, xls_name)

if (!file.exists(xls_path)) {
  zip_path <- tempfile(fileext = ".zip")
  download.file(url, zip_path, mode = "wb", quiet = TRUE)
  unzip(zip_path, files = xls_name, exdir = raw_dir)
  unlink(zip_path)
}

if (unname(tools::md5sum(xls_path)) != xls_md5) {
  message("MD5 differs from the reference copy; checking the contents instead.")
}

x <- readxl::read_excel(xls_path, skip = 1)
x <- as.data.frame(x)
names(x)[names(x) == "default payment next month"] <- "default"
names(x)[names(x) == "PAY_0"] <- "PAY_1"   # the source skips PAY_1

stopifnot(
  nrow(x) == 30000,
  ncol(x) == 25,
  sum(x$default) == 6636,
  sum(x$LIMIT_BAL) == 5024529680,
  sum(x$BILL_AMT1) == 1536699927
)

x$ID <- NULL
x[] <- lapply(x, as.integer)
saveRDS(x, file.path("data", "credit.rds"))
cat("data/credit.rds:", nrow(x), "clients,", sum(x$default), "defaults\n")
