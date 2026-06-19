# CSV to Excel Converter

A self-contained app that combines multiple CSV files from a folder into a
single Excel workbook — one sheet per file. It presents a guided, four-step wizard with
an in-browser folder navigator, so users never need to type file paths by hand. Built for
sandboxed research environments such as Aridhia's Digital Research Environment, where the
file system is rooted under a fixed base directory.

---

## What it does

Point the app at a folder, tick the CSV files you want, choose where to save, and it writes
a `.xlsx` workbook in which each selected CSV becomes its own worksheet.

### Features

| Feature | Notes |
|---------|-------|
| Step-by-step wizard | Four stages — **Source → Files → Output → Generate** — with a progress stepper and validated navigation (you can't advance until the current step is satisfied) |
| Visual folder browser | Modal navigator with breadcrumb trail, parent-folder (`..`) navigation, and directory/CSV listing; no manual path entry needed |
| File selection | Checkbox list of CSVs in the chosen folder, each showing its file size, with **Select all** / **Clear all** shortcuts and a live selected-count |
| One sheet per CSV | Each file is read and written to its own worksheet in the output workbook |
| Safe sheet naming | Sheet names are stripped of characters Excel disallows (`/ \ ? * [ ] :`), truncated to Excel's 31-character limit, and de-duplicated automatically |
| Smart output default | The output folder defaults to the source folder until you explicitly choose a different one |
| Filename handling | Custom output file name with an automatic `.xlsx` extension if you omit it |
| Review & status | A summary screen before generating, plus success/error feedback after writing |

---

## Requirements

R, with the following packages:

| Package | Purpose |
|---------|---------|
| shiny | Web application framework |
| bslib | Bootstrap 5 theming for the UI |
| shinyjs | Show/hide wizard panels and toggle button state |
| readxl | Excel I/O dependency |
| writexl | Writes the combined `.xlsx` workbook |

Install them with:

```r
install.packages(c("shiny", "bslib", "shinyjs", "readxl", "writexl"))
```

---

## Running the app

From an R session in the project directory:

```r
shiny::runApp("app.R")
```

Or from the command line:

```bash
Rscript -e 'shiny::runApp("app.R", launch.browser = TRUE)'
```

---

## Configuration

Paths are controlled by constants near the top of `app.R`. Adjust these to match your
environment:

| Constant | Default | Purpose |
|----------|---------|---------|
| `DEFAULT_BASE_DIR` | `/home/workspace/files` | Root directory the folder browser is locked to — users cannot navigate above it |
| `DEFAULT_OUTPUT_SUBDIR` | `Downloads` | Default sub-folder name for output |
| `DEFAULT_OUTPUT_DIR` | `<base>/Downloads` | Derived default output location |

---

## How it works

1. **Source** — Browse to and select the folder containing your CSV files.
2. **Files** — Tick the CSVs to include. File sizes are shown; use *Select all* / *Clear all* as needed.
3. **Output** — Choose the destination folder (defaults to the source folder) and set the workbook file name.
4. **Generate** — Review the summary, then click **Generate Excel file**. Each CSV is read with `read.csv()` and written as a separate sheet via `writexl::write_xlsx()`.

---

## Notes

- The folder navigator is intentionally confined to `DEFAULT_BASE_DIR`; this keeps browsing inside the research environment's permitted file area.
- CSVs are read with `stringsAsFactors = FALSE`; columns are written as-is, so any type coercion or cleaning should be done in the source files beforehand.
- Worksheet names are derived from file names and may be shortened or suffixed (e.g. `_1`) to stay within Excel's 31-character limit and remain unique.
