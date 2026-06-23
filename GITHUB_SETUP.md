# How to put this on GitHub

This folder (`github_repo`) is a clean, ready-to-publish copy of the LANDR project —
just the code, tests, docs, and license. The zips and business PDFs are deliberately
left out (they don't belong in a code repo). Pick whichever method is easier.

---

## Option A — Website upload (no command line, easiest)

1. Make a free account at [github.com](https://github.com).
2. Click the **+** (top right) → **New repository**.
3. Name it `landr` (or `LANDR`). Add a short description like
   *"Fatigue-aware ACL injury-risk screening from a single phone video."*
   Choose **Public** (or Private), and **don't** check "add README" (you already
   have one). Click **Create repository**.
4. On the new repo page, click **uploading an existing file**.
5. Open this `github_repo` folder on your computer, select **all** its contents,
   and drag them into the browser. Click **Commit changes**.

> Tip: the hidden files `.gitignore` and `.env.example` may not drag-and-drop on a
> Mac (Finder hides dotfiles). They're optional for a first upload — or press
> `Cmd+Shift+.` in Finder to show hidden files, then include them.

That's it — your project is on GitHub.

---

## Option B — Command line (cleaner, includes hidden files)

Install [git](https://git-scm.com) if you don't have it, then in Terminal:

```bash
cd ~/Downloads/LANDR_official/github_repo

git init
git add .
git commit -m "Initial commit: LANDR prototype"

# create an EMPTY repo on github.com first (no README), copy its URL, then:
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/landr.git
git push -u origin main
```

Replace `YOUR_USERNAME` with your GitHub username.

---

## What's in here (and why)

- `landr/` — the Python package (the actual code)
- `tests/` — automated tests (shows reviewers the code works)
- `examples/` — runnable example scripts
- `docs/` — architecture, accuracy plan, filming guide, prototype proposal
- `README.md` — the front page people see first
- `requirements.txt`, `pyproject.toml` — how to install it
- `LICENSE` — MIT (open-source); change the name/terms if you prefer
- `.gitignore` — tells git which files to skip
- `LANDR_Colab_demo.ipynb` — the browser demo notebook

## Before you go public, double-check

- **No secrets.** There are none here — API keys live only in a local `.env`
  (which `.gitignore` excludes). Never commit a real `.env`.
- **License.** MIT lets anyone use your code. If you plan to commercialize and want
  to keep it closed, make the repo **Private** instead.
- **Your name.** Update the copyright line in `LICENSE` if needed.
