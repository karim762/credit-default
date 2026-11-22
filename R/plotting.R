library(ggplot2)

palette_main <- c(dark = "#1f3b57", mid = "#4f7ca8", light = "#a9c3dd", accent = "#c0504d", grey = "#8c8c8c")

theme_report <- function(base_size = 11) {
  theme_minimal(base_size = base_size) +
    theme(
      panel.grid.minor = element_blank(),
      panel.grid.major.x = element_blank(),
      plot.title = element_text(face = "bold", size = base_size + 1),
      plot.subtitle = element_text(colour = "grey35"),
      axis.title = element_text(colour = "grey25"),
      legend.position = "top",
      legend.title = element_blank()
    )
}

percent_axis <- scales::label_percent(accuracy = 1)
