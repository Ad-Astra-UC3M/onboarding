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
| Aplicaciones | Instala las herramientas de tu perfil (tabla de abajo). Las que necesitan cuenta (STM32CubeIDE, STM32CubeMX, MATLAB) te lleva a su descarga y comprueba que quedan instaladas. |
| GitHub | Te ayuda a crear la cuenta (con tu correo de la UC3M) e inicia sesión. |
| Organización | Comprueba que eres miembro de Ad-Astra-UC3M y acepta tu invitación. |
| Git | Configura tu nombre, tu correo y el merge de Simulink si tienes MATLAB. |
| Repositorios | Clona todos los repos: los de tu proyecto y área en `My Repositories`, el resto en `Team Repositories`. |
| Accesos directos | Crea la carpeta `Apps` con accesos a cada programa, a GitHub, CADLAB, Onshape, SimScale y Teams. |

## Perfiles

| Perfil | Qué instala |
|---|---|
| Base (todos) | Git, GitHub CLI, SourceTree, VS Code |
| `all` (recomendado) | Todo lo de abajo |
| `avionics` | Base + KiCad, STM32CubeIDE\*, STM32CubeMX\*, extensión STM32Cube de VS Code, MATLAB\* |
| `vehicle` | Base + OpenRocket\*, RASAero II\*, OSCALC, MATLAB\* |

\* Instalación guiada: en el último paso el setup te abre la descarga en el navegador, tú lo instalas con las opciones por defecto y el setup comprueba que ha quedado bien (y solo entonces crea su acceso directo). Si lo dejas para luego, sale como *Pendiente* en el resumen.

- **OpenRocket** y **RASAero II** se descargan de su web oficial *en el navegador*: si el setup ejecutara él mismo los instaladores, antivirus como Avast o AVG lo cortarían a mitad. RASAero II necesita **.NET Framework 3.5**; si no lo tienes, el setup te abre *Características de Windows* para activarlo antes.
- **OSCALC** no se instala: se copia a `Apps\Tools\OSCALC` con accesos directos `OSCALC` y `OSCALC manual`. Si tu antivirus lo borra, el setup te abre su página en GitHub y la carpeta donde guardarlo.
- **Jet Engine**: no pregunta perfil ni área; instala solo la base y deja todos los repos en `Team Repositories`.
- **Proyecto + área** deciden qué repo va a `My Repositories` (Rocket A4 + Estructuras → `rocket-a4-simulation`). Si ese repo no existe, todo va a `Team Repositories`.

## Tu carpeta

```
Escritorio\Ad Astra\
├── Apps\                  accesos directos (y Tools\ con programas portables como OSCALC)
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

Otros parámetros: `-SkipInstall` (no instala apps), `-InstallProfile all|avionics|vehicle`, `-Project rocket|satellite|jet`, `-Area hardware|software|controls|structures`.

## Problemas frecuentes

- **"No encuentro winget"**: actualiza *Instalador de aplicación* en Microsoft Store y repite el comando.
- **"Falta Git o GitHub CLI" justo después de instalar**: cierra PowerShell, ábrelo de nuevo y repite el comando.
- **"Todavía no eres miembro"**: tu cuenta de GitHub tiene que usar el mismo correo de la UC3M al que se envió la invitación. Si no te ha llegado, pídesela a tu lead.
- **"No puedo escribir en setup-log.txt" o "No pude mover" un repo**: algunos antivirus (Avast, AVG) protegen el Escritorio y bloquean a PowerShell. No es grave: el setup sigue. Si quieres evitarlo, permite PowerShell en el escudo de ransomware del antivirus.
- **El antivirus corta el setup o borra un archivo** (Avast/AVG: aviso `IDP.HELU.PSD11`): vuelve a ejecutar el comando; sigue donde lo dejó. Lo que el antivirus no deje copiar te lo pide descargar a mano al final.
- **RASAero II dice que necesita .NET Framework 3.5**: actívalo en *Activar o desactivar las características de Windows → .NET Framework 3.5* (el setup te abre esa ventana) y vuelve a ejecutar el instalador.
- **SourceTree pide iniciar sesión al abrirlo**: sáltate el de Bitbucket; tus repos ya aparecen en la barra lateral y GitHub ya está conectado.
- **CADLAB**: no hay invitación por correo. Entra en cadlab.io con tu cuenta de GitHub y después escribe a Jorge (Technical Director) con tu usuario de GitHub para que te añada al equipo.
- **Un repo "no se pudo actualizar"**: tienes cambios locales o estás en una rama sin remoto. Ábrelo en SourceTree.

## Para leads

- Las apps, extensiones de VS Code (`vscodeExtensions`), perfiles, proyectos y enlaces se cambian en `config.json`, sin tocar el script. Tipos de app: `wingetId` (winget), `manual` (página de descarga), `download` (instalador oficial que se abre en el navegador; `githubRepo` + `assetPattern` toman la última release de GitHub, `url` es la alternativa y `mirror` una copia en `tools/` por si la web oficial cae) y `portable` (archivos de `tools/` copiados a `Apps\Tools`).
- Un proyecto con `installProfile` y `noArea` (Jet Engine) no pregunta perfil ni área.
- `invite-members.ps1 -Csv miembros.csv` invita en bloque a la organización desde un CSV con columna `email` (añade `-DryRun` para probar). Requiere ser owner. **No subas el CSV al repo.**
