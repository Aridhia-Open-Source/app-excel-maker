library(shiny)
library(bslib)
library(shinyjs)
library(readxl)
library(writexl)

# --- Configuration ---
DEFAULT_BASE_DIR      <- "/home/workspace/files"
DEFAULT_OUTPUT_SUBDIR <- "Downloads"
DEFAULT_OUTPUT_DIR    <- file.path(DEFAULT_BASE_DIR, DEFAULT_OUTPUT_SUBDIR)

`%||%` <- function(a, b) if (is.null(a)) b else a

# --- Helpers ---------------------------------------------------------------

fmt_size <- function(bytes) {
  if (is.na(bytes)) return("")
  units <- c("B", "KB", "MB", "GB")
  i <- 1
  while (bytes >= 1024 && i < length(units)) { bytes <- bytes / 1024; i <- i + 1 }
  if (i == 1) sprintf("%d %s", as.integer(bytes), units[i])
  else        sprintf("%.1f %s", bytes, units[i])
}

safe_sheet_name <- function(f) {
  nm <- sub("\\.csv$", "", f, ignore.case = TRUE)
  nm <- gsub("[/\\\\?*\\[\\]:]", "_", nm)
  substr(nm, 1, 31)
}

list_items <- function(dir, file_pattern = "\\.csv$") {
  if (!dir.exists(dir)) return(list(dirs = character(0), files = character(0)))
  items      <- list.files(dir, full.names = FALSE, all.files = FALSE)
  full_paths <- file.path(dir, items)
  is_dir     <- dir.exists(full_paths)
  list(
    dirs  = sort(items[is_dir]),
    files = sort(items[!is_dir & grepl(file_pattern, items, ignore.case = TRUE)])
  )
}

STEP_LABELS <- c("Source", "Files", "Output", "Generate")
N_STEPS     <- length(STEP_LABELS)

# --- UI --------------------------------------------------------------------

ui <- page_fluid(
  useShinyjs(),
  theme = bs_theme(
    version = 5,
    primary = "#2c7be5",
    success = "#00b074",
    base_font = font_google("Inter", local = FALSE)
  ),
  tags$head(tags$style(HTML("
    body { overflow-y: hidden; }            /* the wizard fits on screen; no page scroll */
    .wizard-wrap { max-width: 720px; margin: 1.25rem auto 0; width: 100%; }

    /* Step bar */
    .stepper { display: flex; align-items: center; margin: .5rem 0 1.25rem; }
    .stepper .step { display: flex; align-items: center; gap: 8px; }
    .stepper .dot  { width: 30px; height: 30px; border-radius: 50%; flex: 0 0 30px;
                     display: flex; align-items: center; justify-content: center;
                     font-weight: 700; background: #e9ecef; color: #6c757d;
                     transition: background .15s; }
    .stepper .step.active .dot { background: #2c7be5; color: #fff; }
    .stepper .step.done   .dot { background: #00b074; color: #fff; }
    .stepper .label { font-size: .9rem; color: #adb5bd; white-space: nowrap; }
    .stepper .step.active .label { color: #212529; font-weight: 600; }
    .stepper .step.done   .label { color: #495057; }
    .stepper .line { flex: 1 1 auto; height: 2px; background: #e9ecef; margin: 0 12px; }
    .stepper .line.done { background: #00b074; }

    /* Step body keeps a steady height so panels don't jump as you navigate */
    .step-body { min-height: 320px; }

    /* Folder modal navigator */
    .breadcrumb-nav   { margin-bottom: 12px; font-weight: 600; color: #6c757d; }
    .breadcrumb-nav a { cursor: pointer; text-decoration: none; }
    .breadcrumb-nav a:hover { text-decoration: underline; }
    .file-item        { padding: 7px 10px; cursor: pointer; border-bottom: 1px solid #eee;
                        border-radius: 4px; }
    .file-item:hover  { background-color: #f1f5f9; }
    .directory        { color: #2c3e50; font-weight: 500; }
    .csv-file         { color: #00875a; }
    .text-muted-empty { padding: 20px; text-align: center; color: #999; }
    .dir-list-scroll  { max-height: 46vh; overflow-y: auto; border: 1px solid #e9ecef;
                        border-radius: 8px; padding: 4px; }
    .modal-current    { font-family: monospace; font-size: .8rem; color: #6c757d;
                        margin-right: auto; align-self: center; word-break: break-all; }

    /* Path badges + file list */
    .path-badge { display: inline-block; font-family: monospace; font-size: .85rem;
                  background: #eef2f7; color: #344563; padding: 4px 10px;
                  border-radius: 6px; word-break: break-all; }
    .path-empty { color: #adb5bd; font-style: italic; }
    .csv-list-scroll { max-height: 50vh; overflow-y: auto; padding-right: 6px;
                       border: 1px solid #e9ecef; border-radius: 8px; }
    .csv-list-scroll .shiny-options-group { margin: 0; padding: 8px 12px; }
    .csv-list-scroll .checkbox { padding: 3px 0; }

    .btn-folder { width: 100%; }
    .review-line { padding: 4px 0; }
    .review-line .k { color: #6c757d; display: inline-block; min-width: 120px; }
  "))),

  div(
    class = "wizard-wrap",
    h3("CSV to Excel Converter", class = "mb-1"),
    p("Combine CSV files from a folder into a single Excel workbook, one sheet per file.",
      class = "text-muted small mb-2"),

    uiOutput("stepper"),

    card(
      card_body(
        class = "step-body",

        # ---- Step 1: Source ----
        div(id = "step1",
          h5("Select the folder containing your CSV files"),
          p(class = "text-muted small", "Browse to the folder, then continue."),
          actionButton("btn_select_source", "Choose source folder",
                       icon = icon("folder-open"), class = "btn-primary btn-folder"),
          div(class = "mt-3", uiOutput("source_path_display"))
        ),

        # ---- Step 2: Files ----
        shinyjs::hidden(div(id = "step2",
          h5("Choose which CSV files to include"),
          div(class = "d-flex gap-2 my-2",
              actionButton("select_all", "Select all", class = "btn-sm btn-outline-secondary"),
              actionButton("clear_all",  "Clear all",  class = "btn-sm btn-outline-secondary")),
          uiOutput("file_select_area"),
          div(class = "mt-2 text-muted small", textOutput("file_count", inline = TRUE))
        )),

        # ---- Step 3: Output ----
        shinyjs::hidden(div(id = "step3",
          h5("Where should the Excel file be saved?"),
          actionButton("btn_select_output", "Choose output folder",
                       icon = icon("folder-open"), class = "btn-primary btn-folder"),
          div(class = "mt-2 mb-3", uiOutput("output_path_display")),
          textInput("output_name", "Excel file name", value = "combined_output.xlsx",
                    width = "100%")
        )),

        # ---- Step 4: Generate ----
        shinyjs::hidden(div(id = "step4",
          h5("Review and generate"),
          uiOutput("review"),
          div(class = "mt-3",
              input_task_button("generate", "Generate Excel file",
                                icon = icon("file-excel"),
                                label_busy = "Writing file...",
                                class = "btn-success btn-lg btn-folder")),
          div(class = "mt-3", uiOutput("status_msg"))
        ))
      )
    ),

    # ---- Navigation ----
    div(class = "d-flex justify-content-between mt-3",
        actionButton("back_btn", tagList(icon("arrow-left"), " Back"),
                     class = "btn-outline-secondary"),
        actionButton("next_btn", tagList("Next ", icon("arrow-right")),
                     class = "btn-primary"))
  )
)

# --- Server ----------------------------------------------------------------

server <- function(input, output, session) {

  step            <- reactiveVal(1)
  source_path     <- reactiveVal(NULL)
  output_path     <- reactiveVal(NULL)
  output_user_set <- reactiveVal(FALSE)   # TRUE once the user picks an output folder explicitly
  status          <- reactiveVal(NULL)
  last_file       <- reactiveVal(NULL)

  # Is a given step's requirement satisfied?
  valid_step <- function(i) {
    switch(as.character(i),
      "1" = !is.null(source_path()),
      "2" = length(input$csv_selection) > 0,
      "3" = !is.null(output_path()) && nzchar(trimws(input$output_name %||% "")),
      "4" = TRUE,
      FALSE)
  }

  # ---- Step bar ----
  output$stepper <- renderUI({
    cur <- step()
    pieces <- list()
    for (i in seq_len(N_STEPS)) {
      cls <- "step"
      if (i == cur) cls <- paste(cls, "active")
      else if (i < cur && valid_step(i)) cls <- paste(cls, "done")
      dot_content <- if (i < cur && valid_step(i)) icon("check") else as.character(i)
      pieces[[length(pieces) + 1]] <-
        div(class = cls, div(class = "dot", dot_content),
            span(class = "label", STEP_LABELS[i]))
      if (i < N_STEPS)
        pieces[[length(pieces) + 1]] <-
          div(class = if (i < cur) "line done" else "line")
    }
    div(class = "stepper", pieces)
  })

  # ---- Show only the active step panel ----
  observe({
    cur <- step()
    for (i in seq_len(N_STEPS)) shinyjs::toggle(id = paste0("step", i), condition = i == cur)
  })

  # ---- Navigation buttons ----
  observe({
    cur <- step()
    shinyjs::toggleState("back_btn", cur > 1)
    if (cur < N_STEPS) {
      shinyjs::show("next_btn")
      shinyjs::toggleState("next_btn", valid_step(cur))
    } else {
      shinyjs::hide("next_btn")   # last step uses the Generate button instead
    }
  })

  observeEvent(input$next_btn, {
    if (step() < N_STEPS && valid_step(step())) step(step() + 1)
  })
  observeEvent(input$back_btn, {
    if (step() > 1) step(step() - 1)
  })

  # ---- Folder modal: body (breadcrumb fixed + scrollable list) ----
  generate_modal_content <- function(current_dir, root_dir, nav_input_id,
                                      file_pattern = "\\.csv$") {
    items <- list_items(current_dir, file_pattern)
    escaped_root <- gsub("([.\\\\])", "\\\\\\1", root_dir)
    rel_path     <- sub(paste0("^", escaped_root), "", current_dir)
    parts        <- Filter(nchar, strsplit(rel_path, "/")[[1]])

    crumbs <- tagList(
      tags$a("root", onclick = sprintf(
        "Shiny.setInputValue('%s','%s',{priority:'event'})", nav_input_id, root_dir)), " / ")
    for (i in seq_along(parts)) {
      p <- file.path(root_dir, paste(parts[1:i], collapse = "/"))
      crumbs <- tagList(crumbs,
        tags$a(parts[i], onclick = sprintf(
          "Shiny.setInputValue('%s','%s',{priority:'event'})", nav_input_id, p)), " / ")
    }

    tagList(
      div(class = "breadcrumb-nav", crumbs),
      div(class = "dir-list-scroll",
        if (current_dir != root_dir)
          div(class = "file-item directory",
              onclick = sprintf("Shiny.setInputValue('%s','%s',{priority:'event'})",
                                nav_input_id, dirname(current_dir)),
              icon("arrow-up"), " .."),
        lapply(items$dirs, function(d)
          div(class = "file-item directory",
              onclick = sprintf("Shiny.setInputValue('%s','%s',{priority:'event'})",
                                nav_input_id, file.path(current_dir, d)),
              icon("folder"), " ", d)),
        lapply(items$files, function(f)
          div(class = "file-item csv-file", icon("file-csv"), " ", f)),
        if (!length(items$dirs) && !length(items$files))
          p(class = "text-muted-empty", "No items found here.")
      )
    )
  }

  modal_footer <- function(current_dir, select_input_id) {
    tagList(
      span(class = "modal-current", current_dir),
      modalButton("Cancel"),
      tags$button(
        tagList(icon("check"), sprintf(' Select "%s"', basename(current_dir))),
        class = "btn btn-success",
        onclick = sprintf("Shiny.setInputValue('%s','%s',{priority:'event'})",
                          select_input_id, current_dir))
    )
  }

  open_source_modal <- function(dir) {
    showModal(modalDialog(
      title = "Select source folder",
      generate_modal_content(dir, DEFAULT_BASE_DIR, "nav_to_source", "\\.csv$"),
      size = "l", easyClose = TRUE,
      footer = modal_footer(dir, "select_source_folder")))
  }
  open_output_modal <- function(dir) {
    showModal(modalDialog(
      title = "Select output folder",
      generate_modal_content(dir, DEFAULT_BASE_DIR, "nav_to_output"),
      size = "l", easyClose = TRUE,
      footer = modal_footer(dir, "select_output_folder")))
  }

  observeEvent(input$btn_select_source, {
    cur <- source_path()
    open_source_modal(if (!is.null(cur) && dir.exists(cur)) cur else DEFAULT_BASE_DIR)
  })
  observeEvent(input$btn_select_output, {
    start <- output_path() %||% source_path() %||% DEFAULT_BASE_DIR
    if (!dir.exists(start)) start <- DEFAULT_BASE_DIR
    open_output_modal(start)
  })

  observeEvent(input$nav_to_source, {
    if (dir.exists(input$nav_to_source)) open_source_modal(input$nav_to_source)
    else showNotification("Directory not found", type = "error")
  })
  observeEvent(input$nav_to_output, {
    if (dir.exists(input$nav_to_output)) open_output_modal(input$nav_to_output)
    else showNotification("Directory not found", type = "error")
  })

  observeEvent(input$select_source_folder, {
    sel <- input$select_source_folder
    if (dir.exists(sel)) {
      source_path(sel)
      if (!output_user_set()) output_path(sel)   # default output to the source folder
      removeModal()
      showNotification(paste("Source folder set to:", sel), type = "message")
    } else showNotification("Directory not found", type = "error")
  })
  observeEvent(input$select_output_folder, {
    sel <- input$select_output_folder
    if (dir.exists(sel)) {
      output_path(sel); output_user_set(TRUE)
      removeModal()
      showNotification(paste("Output folder set to:", sel), type = "message")
    } else showNotification("Directory not found", type = "error")
  })

  # ---- Path displays ----
  render_path <- function(path, empty_text) {
    if (!is.null(path)) span(class = "path-badge", path)
    else span(class = "path-empty", empty_text)
  }
  output$source_path_display <- renderUI(render_path(source_path(), "No source folder selected."))
  output$output_path_display <- renderUI(render_path(output_path(), "No output folder selected."))

  # ---- CSV files in source ----
  csv_files <- reactive({
    req(source_path())
    dir_path <- source_path()
    if (!dir.exists(dir_path)) return(data.frame(name = character(0), size = numeric(0)))
    files <- sort(list.files(dir_path, pattern = "\\.csv$", ignore.case = TRUE))
    if (!length(files)) return(data.frame(name = character(0), size = numeric(0)))
    sizes <- file.info(file.path(dir_path, files))$size
    data.frame(name = files, size = sizes, stringsAsFactors = FALSE)
  })

  output$file_select_area <- renderUI({
    if (is.null(source_path()))
      return(p(class = "text-muted mb-0", "Choose a source folder first."))
    df <- csv_files()
    if (!nrow(df))
      return(p(class = "text-muted mb-0", "No CSV files found in the selected folder."))
    div(class = "csv-list-scroll",
        checkboxGroupInput(
          "csv_selection", label = NULL,
          choiceNames  = lapply(seq_len(nrow(df)), function(i)
            span(df$name[i],
                 span(class = "text-muted small", sprintf("  (%s)", fmt_size(df$size[i]))))),
          choiceValues = df$name,
          selected     = df$name))
  })

  observeEvent(input$select_all,
    updateCheckboxGroupInput(session, "csv_selection", selected = csv_files()$name))
  observeEvent(input$clear_all,
    updateCheckboxGroupInput(session, "csv_selection", selected = character(0)))

  output$file_count <- renderText({
    n <- length(input$csv_selection); tot <- nrow(csv_files())
    sprintf("%d of %d file%s selected", n, tot, if (n == 1) "" else "s")
  })

  # ---- Review (step 4) ----
  output$review <- renderUI({
    fn <- basename(input$output_name %||% "combined_output.xlsx")
    if (!grepl("\\.xlsx$", fn, ignore.case = TRUE)) fn <- paste0(fn, ".xlsx")
    tagList(
      div(class = "review-line", span(class = "k", "Source folder:"),
          span(class = "path-badge", source_path() %||% "-")),
      div(class = "review-line", span(class = "k", "Files selected:"),
          sprintf("%d", length(input$csv_selection))),
      div(class = "review-line", span(class = "k", "Output folder:"),
          span(class = "path-badge", output_path() %||% "-")),
      div(class = "review-line", span(class = "k", "File name:"), tags$code(fn))
    )
  })

  # ---- Generate ----
  observeEvent(input$generate, {
    status(NULL); last_file(NULL)
    req(source_path(), output_path(), input$csv_selection)

    out_filename <- basename(input$output_name)
    if (!nzchar(out_filename)) out_filename <- "combined_output.xlsx"
    if (!grepl("\\.xlsx$", out_filename, ignore.case = TRUE))
      out_filename <- paste0(out_filename, ".xlsx")
    final_output_path <- file.path(output_path(), out_filename)

    tryCatch({
      dfs_list <- lapply(input$csv_selection, function(fn)
        read.csv(file.path(source_path(), fn), stringsAsFactors = FALSE))
      nms <- vapply(input$csv_selection, safe_sheet_name, character(1))
      nms <- substr(make.unique(nms, sep = "_"), 1, 31)
      names(dfs_list) <- nms

      write_xlsx(dfs_list, path = final_output_path)
      last_file(final_output_path)
      status(list(type = "success",
                  msg = paste("Saved", length(dfs_list), "sheet(s) to:", final_output_path)))
      showNotification("Excel file created", type = "message")
    }, error = function(e) {
      status(list(type = "error", msg = paste("Error creating file:", e$message)))
      showNotification(paste("Error:", e$message), type = "error")
    })
  })

  output$status_msg <- renderUI({
    s <- status(); if (is.null(s)) return(NULL)
    cls <- if (s$type == "success") "alert alert-success" else "alert alert-danger"
    ic  <- if (s$type == "success") icon("circle-check") else icon("triangle-exclamation")
    div(class = paste(cls, "mb-0 py-2"), ic, " ", s$msg)
  })
}

shinyApp(ui = ui, server = server)