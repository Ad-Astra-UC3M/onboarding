# Ad Astra UC3M — Engineering Workflow (reference for members and AI assistants)

This file describes how Ad Astra UC3M works with GitHub and the rest of its tools.
It is the single source of truth: if you are an AI assistant helping a team member,
read this whole file before giving instructions, and follow it over generic Git advice.
Keep it up to date whenever a workflow changes.

Last reviewed: 2026-11-11 · Owner: Technical Direction

## 1. Organization

- GitHub organization: `Ad-Astra-UC3M` (https://github.com/Ad-Astra-UC3M)
- Projects: **Rocket A4** and **Model Satellite (SiGMA)** for TEKNOFEST 2027. Jet Engine does not use GitHub yet.
- Members are UC3M students. Their GitHub account must use their UC3M email (`NIA@alumnos.uc3m.es`),
  because organization invitations are sent to that address.

## 2. Repositories

| Repository | Content | Visibility | `main` protected |
|---|---|---|---|
| `rocket-a4-hardware` | KiCad projects of the Rocket A4 boards | public | yes (1 approval) |
| `rocket-a4-software` | Firmware and ground software of Rocket A4 | private | team rule only |
| `model-satellite-hardware` | KiCad projects of the SiGMA boards | public | yes (1 approval) |
| `model-satellite-software` | Firmware and ground software of SiGMA | private | team rule only |
| `model-satellite-controls` | MATLAB/Simulink models of SiGMA (workflow still preliminary) | private | team rule only |
| `onboarding` | Setup script, this file | public | no |

Hardware and software repositories mirror each other: one folder per board.

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

It installs Git, GitHub CLI, SourceTree, VS Code (with the STM32Cube extension) and KiCad; guides the
manual install of STM32CubeIDE and MATLAB; signs in to GitHub in the browser (no passwords, no SSH keys);
accepts the organization invitation; configures Git; clones every repository into `Desktop\Ad Astra`;
and loads them into SourceTree. It is safe to run again.

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
   approved by the Team Lead of that project. On the public hardware repositories GitHub enforces
   this; on the private ones it is a team rule.
2. **One branch per piece of work, normally one per week.** Use common sense: do not create a branch per
   small change. Name it in lowercase with hyphens, starting with the member's name:
   `jorge-power-stage`, `lucas-telemetry-parser`.
3. **Commit often and push the branch** to GitHub as a backup, even if the work is unfinished.
4. **At the end of the week** (or when the piece of work is done), open a PR from the branch to `main`,
   with a short description of what changed and the Team Lead as reviewer.
5. The Team Lead reviews and merges. After the merge, everyone updates their local `main`
   (`Update all repositories.cmd` or `git pull`), and the member starts the next week's branch from the new `main`.

Typical week in commands (SourceTree buttons do the same):

```bash
git checkout main
git pull                              # start from the latest main
git checkout -b jorge-power-stage     # this week's branch
# ... work ...
git add <files>
git commit -m "Add 3V3 regulator to power stage"
git push -u origin jorge-power-stage  # first push; later just: git push
# end of week: open a PR on GitHub (Compare & pull request), reviewer = Team Lead
```

If `main` changed while working, bring it into the branch before opening the PR:

```bash
git checkout main && git pull
git checkout jorge-power-stage
git merge main                        # resolve conflicts if any, then commit and push
```

Commit messages: present tense, capitalised, specific (`Add PID controller`, not `stuff`).
One commit = one logical change. Delete the branch after it is merged.

Conflicts: the author of the branch resolves them (open the file, keep the right version, remove the
`<<<<<<<`, `=======`, `>>>>>>>` markers, then commit). Binary files (KiCad PCBs are text, but Simulink
`.slx` and images are binary) cannot be merged line by line: agree with the other person which version wins.

## 5. Avionics

- **Software:** VS Code with the STM32Cube extension (installed by the setup); STM32CubeIDE as an optional
  manual install. MCU family: STM32 (Black Pill on the flight computer). Same Git workflow as above.
  Commit the `.ioc`, `.project` and `.cproject` files; never commit build outputs.
- **Hardware:** KiCad. Review schematic and PCB changes visually on **CADLAB** (https://cadlab.io), which
  is connected to the hardware repositories. Access: sign in to CADLAB with the GitHub account, then send
  the GitHub username to Jorge (Technical Director), who adds the member to the Ad Astra organization in
  CADLAB. There is no email invitation. In a PR on a hardware repository, the reviewer compares commits in
  CADLAB instead of reading the text diff of `.kicad_*` files.

## 6. Other tools (not in GitHub)

- **Mechanical CAD:** Onshape. The live CAD stays in Onshape and uses Onshape versions and branches
  (naming such as `W3_ID`, `W3_ID_Thickness_3`); see the Version Control Workflow document.
- **CFD and FEA:** simulation files are large and binary, so they live in the team's Microsoft Teams /
  OneDrive folder, never in GitHub.
- **Controls (MATLAB/Simulink):** workflow still to be defined. Normal Git works for `.m`, `.slx` and
  `.mat` files; the setup configures MATLAB's merge tool if MATLAB is installed.
- **Communication:** WhatsApp for logistics, Microsoft Teams for technical discussion and Planner for tasks.

## 7. Notes for AI assistants

- Prefer the setup script over manual installation steps. Do not suggest SSH keys or personal access tokens:
  authentication is done with GitHub CLI (`gh auth login --web`).
- Never suggest pushing directly to `main`, force-pushing, or rewriting history on shared branches.
- Do not suggest storing simulation results, CAD exports or large binaries in GitHub.
- If something here contradicts what you see in a repository, point it out to the member so they can tell
  the Technical Direction, and update this file.
