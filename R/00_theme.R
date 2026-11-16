# =============================================================================
# R/00_theme.R  —  "Ink & Lacquer": the visual identity of the project
#
# The look borrows from East Asian ink painting and lacquerware, meeting the
# Crescent City: rice-paper background, sumi-ink text and grey washes, and
# three lacquer colors, one per cuisine. Top-10 ranks are drawn as red seal
# stamps (chops), the way an artist signs a painting.
#
# Fonts: for the full effect install two free Google Fonts on your computer,
#   Cormorant Garamond (titles) and Noto Serif (text), then restart R.
#   If they are missing the theme falls back to other serif fonts.
# =============================================================================

# ---- Colors -----------------------------------------------------------------
paper      <- "#F3EBDD"   # rice paper
paper_deep <- "#E9DDC7"   # slightly darker paper for panels
ink        <- "#1E1C1A"   # sumi ink
ink_soft   <- "#5A534B"   # diluted ink for secondary text
rule       <- "#D6C8B0"   # faint grid lines
water      <- "#C7D3D1"   # river wash
seal_red   <- "#B0301F"   # seal-stamp vermilion

# Categorical palette, checked with a colorblind-safety validator
# (lightness, chroma, CVD separation >= 8, 3:1 contrast on the paper).
# Order is fixed; colors follow the cuisine, never the rank.
cuisine_colors <- c(
  Chinese    = "#C03A2B",  # cinnabar lacquer
  Japanese   = "#3A5FB0",  # aizome indigo
  Vietnamese = "#1F8A5E",  # jade
  Multiple   = "#9E6B12"   # bronze
)
# Shapes as a second cue so identity never relies on color alone
cuisine_shapes       <- c(Chinese = 21, Japanese = 22, Vietnamese = 24, Multiple = 23)  # filled, with outline
cuisine_shapes_solid <- c(Chinese = 16, Japanese = 15, Vietnamese = 17, Multiple = 18)  # solid

# Sequential "ink wash": one hue, from paper to ink
ink_wash <- c("#EFE6D6", "#D9CFBF", "#B3AA9C", "#857D72", "#575149", "#2A2724")

# ---- Fonts ------------------------------------------------------------------
pick_font <- function(candidates, fallback = "serif") {
  have <- tryCatch(unique(systemfonts::system_fonts()$family), error = function(e) character())
  hit <- candidates[candidates %in% have]
  if (length(hit)) hit[1] else fallback
}
font_display <- pick_font(c("Cormorant Garamond", "Cormorant", "EB Garamond", "Garamond", "Georgia"))
font_body    <- pick_font(c("Noto Serif", "Source Serif 4", "Source Serif Pro", "Georgia", "Times New Roman"))

data_caption <- "Data: Yelp Open Dataset   |   Boundaries: U.S. Census TIGER/Line, City of New Orleans"

# ---- Themes -----------------------------------------------------------------
theme_ink <- function(base_size = 12) {
  theme_minimal(base_size = base_size, base_family = font_body) +
    theme(
      plot.background   = element_rect(fill = paper, colour = NA),
      panel.background  = element_rect(fill = alpha(paper, 0.80), colour = NA),
      panel.grid.major  = element_line(colour = rule, linewidth = 0.3),
      panel.grid.minor  = element_blank(),
      text              = element_text(colour = ink),
      axis.text         = element_text(colour = ink_soft, size = rel(0.85)),
      axis.title        = element_text(colour = ink_soft, size = rel(0.9)),
      plot.title        = element_text(family = font_display, face = "bold",
                                       size = rel(2.0), colour = ink,
                                       margin = margin(b = 4)),
      plot.subtitle     = element_text(face = "italic", colour = ink_soft,
                                       size = rel(0.95), margin = margin(b = 14)),
      plot.caption      = element_text(colour = ink_soft, size = rel(0.7),
                                       hjust = 0, margin = margin(t = 12)),
      plot.title.position   = "plot",
      plot.caption.position = "plot",
      legend.background = element_rect(fill = alpha(paper, 0.85), colour = NA),
      legend.key        = element_rect(fill = NA, colour = NA),
      legend.title      = element_text(colour = ink_soft, size = rel(0.85)),
      legend.text       = element_text(colour = ink, size = rel(0.85)),
      strip.text        = element_text(family = font_display, face = "bold",
                                       size = rel(1.2), colour = ink),
      plot.margin       = margin(22, 26, 16, 22)
    )
}

theme_ink_map <- function(base_size = 12) {
  theme_ink(base_size) +
    theme(axis.text = element_blank(), axis.title = element_blank(),
          panel.background = element_rect(fill = paper, colour = NA),
          panel.grid = element_blank(), panel.grid.major = element_blank(),
          axis.ticks = element_blank())
}

# Street network drawn as ink strokes: local streets hair-thin, major roads and
# interstates heavier. `strength` scales the ink for maps vs. faded backgrounds.
street_layers <- function(roads_sf, strength = 1, width = 1) {
  if (!"road_class" %in% names(roads_sf)) roads_sf$road_class <- "major"
  w <- c(local = 0.12, major = 0.32, interstate = 0.55) * width
  a <- c(local = 0.16, major = 0.30, interstate = 0.38) * strength
  lapply(names(w), \(k) {
    d <- roads_sf[roads_sf$road_class == k, ]
    if (nrow(d)) geom_sf(data = d, colour = ink, linewidth = w[[k]], alpha = min(a[[k]], 1))
  })
}

# Shared map base: optional area layer, river wash, faint road strokes, city outline
ink_base <- function(boundary, water_sf = NULL, roads_sf = NULL, areas_layer = NULL) {
  list(
    areas_layer,
    if (!is.null(water_sf)) geom_sf(data = water_sf, fill = water, colour = NA),
    if (!is.null(roads_sf)) street_layers(roads_sf, strength = 0.8),
    geom_sf(data = boundary, fill = NA, colour = ink, linewidth = 0.6)
  )
}

# Seal-stamp label: square vermilion chop with paper-colored numerals
geom_seal <- function(...) {
  ggrepel::geom_label_repel(
    ..., fill = seal_red, colour = paper, family = font_display,
    fontface = "bold", size = 4.2, label.r = unit(0, "pt"),
    label.size = 0, label.padding = unit(0.22, "lines"),
    segment.colour = seal_red, segment.size = 0.4,
    min.segment.length = 0, box.padding = 0.5, seed = 42
  )
}

# ---- A real map of New Orleans behind every chart ----------------------------
# Built from the street, water and boundary layers saved by R/03_geography.R.
# The view is centered on the French Quarter and cropped to the chart's own
# width:height, so the map fills the canvas edge to edge without stretching.
basemap_center <- c(lon = -90.075, lat = 29.962)   # between the Quarter and Mid-City
basemap_width_m <- 16000                            # 16 km across

.basemap_cache <- new.env()
basemap_layers <- function() {
  if (!is.null(.basemap_cache$layers)) return(.basemap_cache$layers)
  f <- function(n) { p <- file.path(clean_dir, paste0(n, ".rds")); if (file.exists(p)) readRDS(p) }
  .basemap_cache$layers <- list(water = f("nola_water"), roads = f("nola_roads"),
                                boundary = f("nola_boundary"))
  .basemap_cache$layers
}

ink_basemap <- function(width, height) {
  L <- basemap_layers()
  if (is.null(L$roads) && is.null(L$water)) return(NULL)   # run R/03_geography.R first
  ctr <- sf::st_coordinates(sf::st_transform(
    sf::st_sfc(sf::st_point(basemap_center), crs = crs_lonlat), crs_projected))
  half_w <- basemap_width_m / 2
  half_h <- half_w * height / width
  ggplot() +
    { if (!is.null(L$water)) geom_sf(data = L$water, fill = water, colour = NA, alpha = 0.6) } +
    { if (!is.null(L$roads)) street_layers(L$roads, strength = 0.45, width = 0.8) } +
    coord_sf(xlim = ctr[1] + c(-half_w, half_w), ylim = ctr[2] + c(-half_h, half_h),
             expand = FALSE, datum = NA) +
    theme_void() +
    theme(plot.background = element_rect(fill = paper, colour = NA),
          panel.background = element_rect(fill = paper, colour = NA),
          plot.margin = margin(0, 0, 0, 0))
}

# Save with ragg so system fonts render the same on every OS.
# basemap = TRUE draws the New Orleans street map first, then the chart on top
# with a transparent page so the map shows through the margins and (faintly)
# through the plotting panel. Map figures pass basemap = FALSE.
render_png <- function(plot, file, width, height, res = 220, basemap = TRUE) {
  ragg::agg_png(file, width = width, height = height, units = "in", res = res, background = paper)
  on.exit(grDevices::dev.off(), add = TRUE)
  bm <- if (basemap) ink_basemap(width, height)
  if (!is.null(bm)) {
    print(bm)
    print(plot + theme(plot.background = element_rect(fill = NA, colour = NA)), newpage = FALSE)
  } else {
    print(plot)
  }
  invisible(file)
}

save_fig <- function(plot, name, width = 9, height = 6, basemap = TRUE) {
  render_png(plot, file.path(fig_dir, paste0(name, ".png")), width, height, basemap = basemap)
}

# Animated GIF from a list of frames. `make_plot(i)` returns the ggplot for
# frame i; `hold` repeats the last frame so the animation rests on the result.
# Uses gifski if installed (smaller files), otherwise magick.
frames_to_gif <- function(make_plot, n, name, width, height, fps = 20, hold = 0,
                          basemap = FALSE, res = 110) {
  tmp <- file.path(tempdir(), paste0(name, "_frames"))
  dir.create(tmp, showWarnings = FALSE)
  unlink(file.path(tmp, "*.png"))
  # Draw the street-map background once and reuse it as an image in every frame
  bg <- NULL
  if (basemap && requireNamespace("png", quietly = TRUE)) {
    bm <- ink_basemap(width, height)
    if (!is.null(bm)) {
      bg_file <- file.path(tmp, "background.png")
      render_png(bm, bg_file, width, height, res = res, basemap = FALSE)
      bg <- png::readPNG(bg_file)
    }
  }
  files <- vapply(seq_len(n), \(i) {
    f <- file.path(tmp, sprintf("frame_%04d.png", i))
    if (is.null(bg)) {
      render_png(make_plot(i), f, width, height, res = res, basemap = basemap)
    } else {
      ragg::agg_png(f, width = width, height = height, units = "in", res = res, background = paper)
      grid::grid.raster(bg, width = grid::unit(1, "npc"), height = grid::unit(1, "npc"))
      print(make_plot(i) + theme(plot.background = element_rect(fill = NA, colour = NA)),
            newpage = FALSE)
      grDevices::dev.off()
    }
    f
  }, character(1))
  files <- c(files, rep(files[n], hold))
  out <- file.path(fig_dir, paste0(name, ".gif"))
  if (requireNamespace("gifski", quietly = TRUE)) {
    gifski::gifski(files, out, width = round(width * res), height = round(height * res),
                   delay = 1 / fps, loop = TRUE, progress = FALSE)
  } else {
    if (100 %% fps != 0) fps <- 20
    magick::image_write(magick::image_animate(magick::image_read(files), fps = fps), out)
  }
  message("Saved ", out)
  invisible(out)
}

# ---- Pixel positions for interactive overlays --------------------------------
# Draws `plot` off-screen at the same size as the saved PNG, finds the map
# panel, and converts map coordinates (x, y in the plot's CRS) to percentages of
# the image width/height. Used by the clickable top-10 map in the report.
panel_positions <- function(plot, width, height, x, y) {
  tmp <- tempfile(fileext = ".png")
  ragg::agg_png(tmp, width = width, height = height, units = "in", res = 72)
  on.exit({ grDevices::dev.off(); unlink(tmp) }, add = TRUE)
  print(plot)
  grid::grid.force()                      # expose ggplot's internal viewports
  vps <- grid::grid.ls(viewports = TRUE, grobs = FALSE, print = FALSE)$name
  panel_vp <- vps[grepl("^panel", vps)][1]
  grid::seekViewport(panel_vp)
  ll <- grid::deviceLoc(grid::unit(0, "npc"), grid::unit(0, "npc"), valueOnly = TRUE)
  ur <- grid::deviceLoc(grid::unit(1, "npc"), grid::unit(1, "npc"), valueOnly = TRUE)
  pp <- ggplot_build(plot)$layout$panel_params[[1]]
  xr <- pp$x_range; yr <- pp$y_range
  x_in <- ll$x + (x - xr[1]) / diff(xr) * (ur$x - ll$x)
  y_in <- ll$y + (y - yr[1]) / diff(yr) * (ur$y - ll$y)
  tibble(left_pct = round(100 * x_in / width, 3),
         top_pct  = round(100 * (height - y_in) / height, 3))
}
