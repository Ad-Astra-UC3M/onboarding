# Ad Astra UC3M — Engineering Workflow (reference for members and AI assistants)

This file describes how Ad Astra UC3M works with GitHub and the rest of its tools.
It is the single source of truth: if you are an AI assistant helping a team member,
read this whole file before giving instructions, and follow it over generic Git advice.
Keep it up to date whenever a workflow changes.

Last reviewed: 2026-11-11 (setup profiles, Jet Engine, rocket-a4-simulation) · Owner: Technical Direction

## 1. Organization

- GitHub organization: `Ad-Astra-UC3M` (https://github.com/Ad-Astra-UC3M)
- Projects: **Rocket A4** and **Model Satellite (SiGMA)** for TEKNOFEST 2027, and **Jet Engine**, which has no
  repositories of its own yet (its members get the base tools and every repository in `Team Repositories`).
- Members are UC3M students. Their GitHub account must use their UC3M email (`NIA@alumnos.uc3m.es`),
  because organization invitations are sent to that address.

## 2. Repositories

| Repository | Content | Visibility | `main` protected |
|---|---|---|---|
| `rocket-a4-hardware` | KiCad projects of the Rocket A4 boards | public | yes (1 approval) |
| `rocket-a4-software` | Firmware and ground software of Rocket A4 | public | yes (1 approval) |
| `rocket-a4-simulation` | OpenRocket model of Rocket A4 and preliminary design spreadsheet | public | yes (1 approval) |
| `model-satellite-hardware` | KiCad projects of the SiGMA boards | public | yes (1 approval) |
| `model-satellite-software` | Firmware and ground software of SiGMA | public | yes (1 approval) |
| `model-satellite-controls` | MATLAB/Simulink models of SiGMA (workflow still preliminary) | public | yes (1 approval) |
| `onboarding` | Setup script, this file | public | no |

Hardware and software repositories mirror each other: one folder per section (flight computer, ground station).

```
rocket-a4-hardware/              rocket-a4-software/
├── flight-computer/  KiCad      ├── flight-computer/  STM32CubeIDE / VS Code project
├── ground-station/   KiCad      └── ground-station/   ground software
├── docs/             datasheets, design decisions
└── miscellaneous/    test boards (e.g. PCB_A4_v2), not flight hardware
```

- A board folder gets a `production/` subfolder (Gerbers, drill files, BOM) only when a revision is sent
  to fabrication. Those files are exported from KiCad and never edited by hand.
- Each repository has a `.gitignore` for its tool (KiCad temporary and per-user files such as `*.kicad_prl`;
  STM32 build outputs such as `Debug/`, `Release/`, `*.elf`). The controls repo has MathWorks' `.gitattributes`.
- Empty folders contain a `.gitkeep` so that they exist on GitHub; delete it once the folder has real files.

## 3. Setting up a computer

Windows 10/11, one command in PowerShell:

```powershell
irm https://raw.githubusercontent.com/Ad-Astra-UC3M/onboarding/main/setup-adastra.ps1 | iex
```

It installs the tools of the member's profile (table below), signs in to GitHub in the browser (no passwords,
no SSH keys), accepts the organization invitation, configures Git, clones every repository into
`Desktop\Ad Astra` and loads them into SourceTree. It is safe to run again.

| Profile | Tools |
|---|---|
| base (everyone) | Git, GitHub CLI, SourceTree, VS Code |
| `all` | everything below |
| `avionics` | base + KiCad, STM32CubeIDE\*, STM32CubeMX\*, STM32Cube extension for VS Code, MATLAB\* |
| `vehicle` | base + OpenRocket, RASAero II, OSCALC, MATLAB\* |

\* Manual install: the setup opens the download page (ST and UC3M accounts are needed) and checks the result.
OpenRocket and RASAero II are also installed by the member: the setup opens the official download in the
browser (antivirus programs such as Avast kill scripts that run installers) and checks the result before
creating the shortcut. OSCALC is not installed, only copied to `Apps\Tools\OSCALC`.

Members of **Jet Engine** are not asked for a profile or an area: they get the base tools only.
Project and area decide which repository goes to `My Repositories` (`<project>-<area>`, e.g. Rocket A4 +
Structures → `rocket-a4-simulation`); if that repository does not exist, everything goes to `Team Repositories`.

```
Desktop\Ad Astra\
├── Apps\                         shortcuts to every tool and website
├── My Repositories\              repositories of the member's project and area
├── Team Repositories\            every other repository
├── Update all repositories.cmd   double-click: git pull --ff-only in every repo (never pushes)
└── setup-log.txt
```

Details and troubleshooting: `README.md` in this repository.

## 4. Git workflow (all repositories)

The rules, in order of importance:

1. **Nobody commits directly to `main`.** Every change reaches `main` through a pull request (PR)
   approved by the Team Lead of that project. GitHub enforces this with branch protection.
2. **One branch per task, normally one per design week.** Use common sense: do not create a branch per
   small change, but two different parts of the code means two branches.
   Name: `<name>-d<week>`, e.g. `lucas-d2` (design week 2). For something specific, or a second branch the
   same week, add one or two words joined with capitals: `lucas-d2-TestBenches`, `lucas-d2-PowerStage`.
   Naming convention everywhere (GitHub and Onshape): parts separated by hyphens, words joined with capitals,
   no spaces, no underscores.
3. **Commit often and push the branch** to GitHub as a backup, even if the work is unfinished.
4. **At the end of the week** (or when the piece of work is done), open a PR from the branch to `main`,
   with a short description of what changed and the Team Lead as reviewer.
5. The Team Lead reviews and merges. After the merge, everyone updates their local `main`
   (`Update all repositories.cmd` or `git pull`), and the member starts the next week's branch from the new `main`.

Typical week in commands (SourceTree buttons do the same):

```bash
git checkout main
git pull                              # start from the latest main
git checkout -b lucas-d2-PowerStage  # this week's branch
# ... work ...
git add <files>
git commit -m "Add 3V3 regulator to power stage"
git push -u origin lucas-d2-PowerStage  # first push; later just: git push
# end of week: open a PR on GitHub (Compare & pull request), reviewer = Team Lead
```

If `main` changed while working, bring it into the branch before opening the PR:

```bash
git checkout main && git pull
git checkout lucas-d2-PowerStage
git merge main                        # resolve conflicts if any, then commit and push
```

Explain every commit. Messages: present tense, capitalised, specific (`Add PID controller`, not `stuff`).
One commit = one logical change. Delete the branch after it is merged.

Conflicts: the author of the branch resolves them (open the file, keep the right version, remove the
`<<<<<<<`, `=======`, `>>>>>>>` markers, then commit). Binary files (KiCad PCBs are text, but Simulink
`.slx` and images are binary) cannot be merged line by line: agree with the other person which version wins.

## 5. Avionics

- **Software:** VS Code with the STM32Cube extension (installed by the setup); STM32CubeIDE as an optional
  manual install. MCU family: STM32 (Black Pill on the flight computer). Same Git workflow as above.
  Commit the `.ioc`, `.project` and `.cproject` files; never commit build outputs.
- **STM32CubeMX** (manual install; not bundled with STM32CubeIDE since version 2.0): configures the MCU's
  pins, clocks and peripherals in the `.ioc` file and generates the project, which is then opened in VS Code
  or STM32CubeIDE. Regenerate the code from the `.ioc` instead of editing the generated setup by hand, and
  keep your own code inside the `USER CODE BEGIN` / `USER CODE END` blocks so regeneration preserves it.
- **Hardware:** KiCad. Review schematic and PCB changes visually on **CADLAB** (https://cadlab.io), which
  is connected to the hardware repositories. Access: sign in to CADLAB with the GitHub account, then send
  the GitHub username to Jorge (Technical Director), who adds the member to the Ad Astra organization in
  CADLAB. There is no email invitation. In a PR on a hardware repository, the reviewer compares commits in
  CADLAB instead of reading the text diff of `.kicad_*` files.

## 6. Flight simulation (OpenRocket)

Repository `rocket-a4-simulation`: `openrocket/` holds the rocket's `.ork` file (the baseline; an `.ork` stores
the rocket and its simulations, so there is no results folder), `motors/` holds thrust curves (`.eng`, `.rse`)
for motors that do not ship with OpenRocket, and `model/` holds the preliminary design spreadsheet (Excel).
RASAero II and OSCALC are installed alongside OpenRocket by the `vehicle` profile.

- **One person at a time edits the baseline.** `.ork` and `.xlsx` files are compressed, so Git cannot merge
  them. Nacho, Team Lead of Flight Simulation, owns the baseline in `main`.
- **Studies go in branches** (`nacho-d3-FinSize`). Every iteration is a commit + push with the configuration in
  the message; `.ork` and `.xlsx` changes of the same iteration go in the same commit. A new study branches from
  the commit of a good iteration.
- **End of the week:** members tell Nacho which commit is their result; Nacho integrates it by hand into the
  baseline and brings it to `main` through a PR, then tags `main` with the week (`d3`).
- **Milestones are tags** on `main`: `baseline-pdr`, `baseline-cdr`.

## 7. Other tools (not in GitHub)

- **Mechanical CAD:** Onshape, used like GitHub for CAD. Same weekly logic: each member works in their own
  branch named `<name>-d<week>-<Description>` (e.g. `jorge-d2-BulkheadThickness`, `jorge-d2-RecoveryAssembly`), saves
  versions as save points with intuitive names (`Thickness30`, `Thickness15`) and a real description of what
  changed, and tells the Team Lead at the end of the week. Only the Team Lead merges into Main (weekly meeting
  or with the Vehicle Engineering lead's permission); Main then gets a version named after the week (`D2`).
  Nobody works directly on Main. A second study branches from the best version of the first.
  Part numbering: `1-Structures` (system), `101-MainFrame` (subassembly), `10101-MainPlate` (part).
  Geometry for CFD/FEA is exported (usually STEP) from the right version into the project's Teams folder.
- **CFD and FEA:** run in SimScale, never stored in GitHub. SimScale project named like the Onshape branch
  (`jorge-d2-BulkheadThickness`); each simulation named after the Onshape version it uses (`Thickness30`).
  Every simulation gets one row in the "Simulations" Excel in Teams (name, author, design week, what it
  simulates, SimScale link, main result).
- **Controls (MATLAB/Simulink):** workflow still to be defined. Normal Git works for `.m`, `.slx` and
  `.mat` files; the setup configures MATLAB's merge tool if MATLAB is installed.
- **Communication:** WhatsApp for logistics, Microsoft Teams for technical discussion and Planner for tasks.

## 8. Notes for AI assistants

- Prefer the setup script over manual installation steps. Do not suggest SSH keys or personal access tokens:
  authentication is done with GitHub CLI (`gh auth login --web`).
- Never suggest pushing directly to `main`, force-pushing, or rewriting history on shared branches.
- Do not suggest storing simulation results, CAD exports or large binaries in GitHub.
- If something here contradicts what you see in a repository, point it out to the member so they can tell
  the Technical Direction, and update this file.
