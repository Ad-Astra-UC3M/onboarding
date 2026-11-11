# Ad Astra UC3M — Onboarding

> **Cómo trabajamos (Git, ramas, PRs, CADLAB):** ver [`WORKFLOW.md`](WORKFLOW.md). Si usas una IA para que te ayude, pásale ese archivo.

Setup automático para miembros del equipo (Windows 10/11). Instala las herramientas, conecta tu cuenta de GitHub y te deja todos los repositorios en `Escritorio\Ad Astra`.

## Cómo usarlo

1. Abre **PowerShell** (menú Inicio → escribe `powershell`).
2. Pega esta línea y pulsa Enter:

```powershell
irm https://raw.githubusercontent.com/Ad-Astra-UC3M/onboarding/main/setup-adastra.ps1 | iex
```

3. Sigue las preguntas. Tarda entre 15 y 30 minutos.

El script **nunca pide contraseñas ni tokens**: todos los inicios de sesión se hacen en tu navegador. Puedes ejecutarlo las veces que quieras; lo que ya está hecho se salta.

## Qué hace

| Paso | Qué ocurre |
|---|---|
| Aplicaciones | Instala Git, GitHub CLI, SourceTree, VS Code (con la extensión STM32Cube) y KiCad. Te lleva a la descarga de STM32CubeIDE y MATLAB y comprueba que quedan instalados. |
| GitHub | Te ayuda a crear la cuenta (con tu correo de la UC3M) e inicia sesión. |
| Organización | Comprueba que eres miembro de Ad-Astra-UC3M y acepta tu invitación. |
| Git | Configura tu nombre, tu correo y el merge de Simulink si tienes MATLAB. |
| Repositorios | Clona todos los repos: los de tu proyecto y área en `My Repositories`, el resto en `Team Repositories`. |
| Accesos directos | Crea la carpeta `Apps` con accesos a cada programa, a GitHub, CADLAB, Onshape, SimScale y Teams. |

## Tu carpeta

```
Escritorio\Ad Astra\
├── Apps\                  accesos directos
├── My Repositories\       los repos de tu proyecto y área
├── Team Repositories\     el resto de repos del equipo
├── Update all repositories.cmd   doble clic: actualiza todos los repos
└── setup-log.txt
```

**`Update all repositories.cmd`** (doble clic) descarga los últimos cambios de GitHub en todos tus repos (también desde `Apps\Update all repos`). Solo hace `git pull`: no sube nada y no toca los repos donde tengas cambios sin commit.

## Opciones

```powershell
# Ver qué haría, sin cambiar nada
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Ad-Astra-UC3M/onboarding/main/setup-adastra.ps1))) -DryRun

# Usar otra carpeta del escritorio
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Ad-Astra-UC3M/onboarding/main/setup-adastra.ps1))) -Folder "AdAstra-test"
```

Otros parámetros: `-SkipInstall` (no instala apps), `-InstallProfile all|avionics|vehicle`, `-Project rocket|satellite`, `-Area hardware|software|controls|structures`.

## Problemas frecuentes

- **"No encuentro winget"**: actualiza *Instalador de aplicación* en Microsoft Store y repite el comando.
- **"Falta Git o GitHub CLI" justo después de instalar**: cierra PowerShell, ábrelo de nuevo y repite el comando.
- **"Todavía no eres miembro"**: tu cuenta de GitHub tiene que usar el mismo correo de la UC3M al que se envió la invitación. Si no te ha llegado, pídesela a tu lead.
- **"No puedo escribir en setup-log.txt" o "No pude mover" un repo**: algunos antivirus (Avast, AVG) protegen el Escritorio y bloquean a PowerShell. No es grave: el setup sigue. Si quieres evitarlo, permite PowerShell en el escudo de ransomware del antivirus.
- **SourceTree pide iniciar sesión al abrirlo**: sáltate el de Bitbucket; tus repos ya aparecen en la barra lateral y GitHub ya está conectado.
- **CADLAB**: no hay invitación por correo. Entra en cadlab.io con tu cuenta de GitHub y después escribe a Jorge (Technical Director) con tu usuario de GitHub para que te añada al equipo.
- **Un repo "no se pudo actualizar"**: tienes cambios locales o estás en una rama sin remoto. Ábrelo en SourceTree.

## Para leads

- Las apps, extensiones de VS Code (`vscodeExtensions`), perfiles, proyectos y enlaces se cambian en `config.json`, sin tocar el script.
- `invite-members.ps1 -Csv miembros.csv` invita en bloque a la organización desde un CSV con columna `email` (añade `-DryRun` para probar). Requiere ser owner. **No subas el CSV al repo.**
