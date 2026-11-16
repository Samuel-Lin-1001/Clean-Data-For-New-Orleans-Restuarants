# AI prompts used in this project

I used **Claude** (Anthropic) as a coding assistant throughout this project. Below are the prompts I gave it, in order, with what came back, where I had to re-prompt, and how I checked the results. Prompts are copied as I typed them, typos included. Where a prompt was a screenshot of an error, I describe what the screenshot showed.

---

## Phase 1: Understanding the assignment and getting started

### 1. Reading the instructions
**Prompt:** *(attached the assignment `.qmd`)* "What am I required to provide?"

**What came back:** A checklist of the 10 required deliverables, the README checklist, and requirements buried inside the step-by-step instructions (for example, explaining my definition of "New Orleans restaurant" and investigating mismatches instead of deleting them).

**How I used it:** As my project checklist. I compared it against the assignment file to make sure nothing was invented or missed.

### 2. Starting the build, and an early limit of AI
**Prompt:** "start building the project, tell me what I need first. A question: What is the best viet/chiense/japanese food in New Orleans"

**What came back:** A list of what I needed (the Yelp download, R, RStudio, Quarto, R packages) and a full project skeleton: five R scripts, a Quarto report and a README. It did **not** answer which restaurant is best. It said it couldn't know without running the analysis on the real Yelp data, which it doesn't have.

**Lesson:** The AI can write the code, but the answer to my research question has to come from my own run on the real data.

### 3. Re-prompt: getting the code tested
**Problem:** The first version of the code was written blind. The assistant said R wasn't installed in its workspace, so none of it had been run.

**Re-prompt:** "can you try to install r?"

**What came back:** It installed R in its own workspace. It still couldn't download the Yelp data or the Census maps there, so it built a small **fake dataset** with the same columns and formats as Yelp's and ran all four scripts on it. That test found three real bugs, which it fixed:
- tied restaurants were given the same rank;
- map colors didn't match the other charts;
- some chart labels were unreadable.

**How I checked:** It sent a preview report built from the fake data, clearly labeled as fake, so I could see the layout before running anything myself.

---

## Phase 2: Design

### 4. Giving the project a visual identity
**Prompt:** "lets make this interesting. Add an artistic feel to it"

**What came back:** An "Ink & Lacquer" theme: a rice-paper background, serif fonts, one lacquer color per cuisine (cinnabar, indigo, jade), and red "seal stamp" rank labels on the final map. Before using the colors, it ran a colorblind-safety check on the palette, adjusted the colors until every check passed, and added a different marker shape for each cuisine so nothing depends on color alone.

### 5. Re-prompt: making the background meaningful
**Prompt:** "replace each chart's background with an actual map of new orleans"

**What came back:** Every chart now sits on a faded map built from real Census street, river and lake data, centered on the French Quarter.

**Problem:** The first version was too dark: street lines ran through the chart titles and axis labels. The assistant noticed this from screenshots, lightened the map, and added a light paper wash behind the plotting area until the text was clearly readable.

### 6. Adding motion
**Prompt:** "is it possible to add some animation style things>"

**What came back:**
- **Two animated GIFs:** restaurants appearing on the map year by year, and total reviews growing for each cuisine.
- **Light page animations in the HTML report**, which turn off for visitors who prefer reduced motion.

**Problems found while testing:**
- The animation package showed the frames in the wrong order: the map jumped back to the first year at the end.
- A label disappeared from one chart in the last frame.

The assistant found both by pulling individual frames out of the GIFs and checking them, then rewrote the animations to draw each frame itself so the order is exact.

### 7. Re-prompt: fixing a broken image and making the map interactive
**Prompt:** "few issues to address: 1. the image attached, 2. make the map of 1-10 interactive. I want something to either popup when hovering over, or make each restuarnt clickable, making another popup on the screen and giving information about said restuarant. make it take the up a good chunk of the screen and click anywhere to close type of thing"
*(The screenshot showed a broken image in my rendered report.)*

**What came back:**
1. The broken image was an animation I hadn't generated yet. The report now leaves out any animation that doesn't exist yet instead of showing a broken image.
2. A clickable top-10 map. Hovering shows a tooltip. Clicking opens a large card with the restaurant's ratings, a breakdown of its star ratings, why it ranks where it does, and a Google Maps link. Clicking anywhere or pressing Esc closes the card. The usual package for this (`ggiraph`) wasn't available, so the assistant had R record exactly where each restaurant lands in the map image and placed the clickable spots there.

**How it was checked:** In a test browser, it confirmed that every clickable spot lines up with its map marker, that the card opens and closes correctly, and that the layout works on a phone-sized screen.

---

## Phase 3: Setup problems and debugging on my computer

### 8. File locations
**Prompt:** "wheres does all the yelp files go? where does the rds g o"

**What came back:** A folder diagram. Raw JSON goes in `data/raw/`, filtered `.rds` files are created in `data/new_orleans/`, and boundary files go in `data/boundaries/`.

### 9. Git basics
**Prompt:** "what is thr .gitnore do"

**What came back:** An explanation that `.gitignore` lists files Git should never upload, with a table of what this project ignores and why. The big one is the raw Yelp data, which is far over GitHub's 100 MB file limit.

### 10. Finding the report file
**Prompt:** "where is the qmd for my html project"

**What came back:** The file's location in the project, and a reminder that the analysis scripts have to run before the report can be rendered.

### 11. Debugging: report won't render
**Prompt:** *(screenshot of an error)* `vroom::check_path("output/tables/top10_restaurants.csv")` and `Quitting from yelp_new_orleans_project--1-.rmarkdown`

**What came back:** Two causes:
- I hadn't run the analysis scripts yet, so the results table didn't exist.
- My report file was a separately downloaded copy named `yelp_new_orleans_project (1).qmd`.

It also warned me that my project was inside a OneDrive-synced folder, which would try to upload gigabytes of Yelp data to the cloud. It then changed the report to stop with a plain-English message if the results are missing.

### 12. Debugging: script not found
**Prompt:** *(screenshot)* `source("R/run_all.R")` returned `cannot open file 'R/run_all.R': No such file or directory`

**What came back:** R's working directory wasn't the project folder. It gave me `getwd()` and `setwd()` commands, warned about the folder-inside-a-folder that Windows' "Extract All" can create, and added an RStudio project file (`.Rproj`) that sets the right folder automatically.

### 13. Re-prompt with a screenshot of my folder
**Prompt:** *(screenshot of the RStudio Files pane showing the project folder)*

**What came back:** The folder was correct, but the Files pane showing it doesn't make it R's working directory. Fix: **More → Set As Working Directory**. It also told me to rename `yelp_new_orleans_project (1).qmd`.

### 14. Re-prompt: nested project folder
**Prompt:** "the acutal R project folder is clean-dara... and yelp-new project is a file within that file, does that still work?"

**What came back:** Not as-is, because every path in the scripts is relative to the folder containing `R/`. The recommended fix was moving everything up one level, so the README and `.gitignore` also sit at the top of the GitHub repository where GitHub expects them.

### 15. Checking progress
**Prompt:** "is this done?"

**What came back:** It couldn't see my screen (no screenshot was attached), so it gave me a `file.exists()` check to confirm the move, plus a list of what was still left in the project.

### 16. Confirming the import was working
**Prompt:** *(screenshot)* `Louisiana restaurants kept: 3640 rows` / `1e+06 reviews scanned`

**What came back:** Confirmation that the chunked import was working, with about 7 runs of 1 million reviews to go. It explained that `1e+06` is R's scientific notation for 1,000,000 and changed the code to print full numbers in future runs.

### 17. A warning I misread
**Prompt:** *(screenshot)* "`geom_line()`: Each group consists of only one observation. ℹ Do you need to adjust the group aesthetic?" (I had typed "yes" into the console)

**What came back:** That message isn't a question. It's a harmless warning from the first frame of an animation, which has only one month of data. The "yes" I typed would just produce an "object not found" error. The code was changed to start the animation at month two so the warning goes away.

---

## Phase 4: Submission and checking the AI's work

### 18. What the teacher needs
**Prompt:** "now for the teacher doesnt want to run any code, he just wants to read the readme and maybe another html, will he need to run any other code?"

**What came back:** No, but it caught something I didn't know. Clicking an `.html` file inside a GitHub repository shows its raw code, not the web page. The fix was publishing with GitHub Pages. The report now saves as `docs/index.html` to give a clean link.

### 19. What belongs in the repository
**Prompt:** "what should be in the github repo?"

**What came back:** A folder tree marking what to commit and what to leave out, an R snippet to check file sizes against GitHub's limits, and a pre-submission checklist.

### 20. Does the report need the data?
**Prompt:** "ok but if the data is not there, the html file is already rendered?"

**What came back:** Yes. The rendered report is self-contained: tables, images, animations and the interactive map are all stored inside the one HTML file, so it works without the data, R, or any other file.

### 21. Questioning the test data
**Prompt:** "is the fake data accurate to the yelp data?"

**What came back:** No. Only the structure (file and column names, formats) matches. Everything else is made up: 600 fake businesses, a grid of fake "neighborhoods", random ratings. It reminded me to ignore every number from the previews and listed which parts of the code the fake data never tested.

### 22. Re-prompt: auditing earlier answers
**Prompt:** "which of the previous answers given was also based on fake data"

**What came back:** An audit sorting everything in the conversation into four groups:
1. based on fake data;
2. based on my real data and screenshots;
3. from the AI's general knowledge but unverified (for example, the size of the Yelp review file);
4. not data-based.

It flagged a claim that "Vietnamese, Chinese and Japanese are the three largest East and Southeast Asian cuisines in the city", which had been written before any results existed, so I could check it against my real category counts.

**Why this mattered:** It showed me how easily placeholder numbers can end up in a final report, and made me check every number against my own output.

### 23. Markdown formatting
**Prompt:** "replace with '?"

**What came back:** No. Code formatting in Markdown uses the backtick `` ` `` (top-left key, under Esc), not the single quote `'`. A single quote shows up as a plain quote mark.

### 24. Re-prompt: checking that the results are repeatable
**Prompt:** "double check the code, does the tables run and compute the same thing each time?"

**What came back:** The assistant searched every script for randomness and found none in the calculations; the only random element is label placement on charts, which is locked with a fixed seed. It then ran the full pipeline twice from scratch and compared all 23 result tables. 22 were exactly identical. The only difference was the import timing in `import_log.csv`. It noted two things that could change results in the future (an update to the city's neighborhood file, or new R package versions) and recommended `renv::snapshot()` to record package versions.

---

## What I learned about working with AI
- **AI can't answer a data question without the data.** It wrote and tested the code, but every result in my report comes from my own run.
- **Testing on fake data catches bugs but proves nothing about the results.** Placeholder numbers can look real, so I checked every number in the report against my own output tables.
- **Screenshots are the fastest way to debug.** Most problems were solved in one step once I sent the actual error message.
- **Asking the AI to audit itself works.** Asking "which answers were based on fake data?" surfaced an unverified claim I would otherwise have submitted.
