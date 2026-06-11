
args <- commandArgs(trailingOnly=TRUE)
path <- args[[1]]
ext <- tolower(tools::file_ext(path))
d <- NULL
err <- ""
tryCatch({
  if (ext == "sav") {
    d <- foreign::read.spss(path, to.data.frame=TRUE, use.value.labels=FALSE, trim.factor.names=TRUE)
  } else if (ext == "dta") {
    d <- foreign::read.dta(path, convert.factors=FALSE)
  }
}, error=function(e) { err <<- conditionMessage(e) })
if (!identical(err, "") || is.null(d)) {
  cat("ERROR\t", substr(gsub("[\r\n\t]+", " ", err), 1, 250), "\n", sep="")
} else {
  nms <- names(d)
  miss <- sapply(d, function(x) mean(is.na(x)))
  uniq <- sapply(d, function(x) length(unique(x[!is.na(x)])))
  head_vals <- sapply(d, function(x) paste(head(unique(as.character(x[!is.na(x)])), 4), collapse="|"))
  clean <- function(x) gsub("[\r\n\t]+", " ", as.character(x))
  cat("OK\t", nrow(d), "\t", ncol(d), "\n", sep="")
  for (i in seq_along(nms)) {
    cat(clean(nms[[i]]), "\t", sprintf("%.3f", miss[[i]]), "\t", uniq[[i]], "\t", clean(head_vals[[i]]), "\n", sep="")
  }
}
