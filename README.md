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
| Base (todos) | Git, GitHub CLI, SourceTree, VS Code, MATLAB\* |
| `all` (recomendado) | Todo lo de abajo |
| `avionics` | Base + KiCad, STM32CubeIDE\*, STM32CubeMX\*, extensión STM32Cube de VS Code |
| `vehicle` | Base + OpenRocket, RASAero II, OSCALC |

\* Instalación guiada (de STM32 instala las versiones **normales**: STM32CubeIDE y STM32CubeMX, **no** STM32CubeMX2): el setup te abre la página de descarga, tú lo instalas y el setup comprueba que ha quedado bien (y solo entonces crea su acceso directo). Si lo dejas para luego, sale como *Pendiente* en el resumen.

- **OpenRocket** y **RASAero II** se descargan de su web oficial y se instalan solos (Windows te pide permiso una vez para cada uno). RASAero II necesita **.NET Framework 3.5**: el setup lo activa en ese mismo paso.
- **Si tu antivirus no lo permite** (Avast y AVG cortan el setup cuando instala programas descargados), el setup no lo intenta: al final te abre la descarga en el navegador, lo instalas tú (guárdalo en *Descargas*) y el setup comprueba que ha quedado bien. Si una ejecución se cortó a mitad de instalar algo, la siguiente te lo pide a mano directamente.
- **OSCALC** no se instala: se copia a `Apps\Tools\OSCALC` con accesos directos `OSCALC` y `OSCALC manual`. Si tu antivirus lo borra, el setup te abre su página en GitHub y la carpeta donde guardarlo.
- **Jet Engine**: no pregunta perfil ni área; instala solo la base y deja todos los repos en `Team Repositories` (todavía no tiene repos propios).
- **¿Cambias de área?** Vuelve a ejecutar el setup con el nuevo perfil. Te pregunta si desinstala lo que instaló para el anterior (solo lo que instaló él; nunca Git, GitHub CLI, SourceTree, VS Code ni MATLAB), quita sus accesos directos de `Apps` y mueve tus repos. STM32CubeIDE y STM32CubeMX no se quitan solos: te abre *Configuración → Aplicaciones* para que los desinstales tú.
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

> **¿Atascado? Pídele ayuda a tu IA.** El setup deja en tu carpeta `Escritorio\Ad Astra` un archivo **`Ayuda para la IA.txt`** con un mensaje ya preparado (qué ha pasado, tu Windows, tu antivirus y los enlaces al script). Ábrelo, copia todo (Ctrl+A, Ctrl+C), pégalo en ChatGPT, Claude o la IA que uses y envíalo: te guiará paso a paso. Si algo falla al final del setup, ya te lo copia al portapapeles y te lo abre él solo.

- **"No encuentro winget"**: actualiza *Instalador de aplicación* en Microsoft Store y repite el comando.
- **"Falta Git o GitHub CLI" justo después de instalar**: cierra PowerShell, ábrelo de nuevo y repite el comando.
- **"Todavía no eres miembro"**: tu cuenta de GitHub tiene que usar el mismo correo de la UC3M al que se envió la invitación. Si no te ha llegado, pídesela a tu lead.
- **"No puedo escribir en setup-log.txt" o "No pude mover" un repo**: algunos antivirus (Avast, AVG) protegen el Escritorio y bloquean a PowerShell. No es grave: el setup sigue. Si quieres evitarlo, permite PowerShell en el escudo de ransomware del antivirus.
- **El antivirus corta el setup o borra un archivo** (Avast/AVG: aviso `IDP.HELU.PSD11`): vuelve a ejecutar el comando; sigue donde lo dejó y lo que se cortó te lo pide instalar a mano. Si sigue fallando, usa `Ayuda para la IA.txt` (arriba).
- **El navegador dice "No tiene permisos para guardar en esta ubicación"**: guarda la descarga en la carpeta *Descargas*. Si también falla ahí, tu antivirus tiene ese archivo en cuarentena: restáuralo desde la cuarentena del antivirus.
- **RASAero II dice que necesita .NET Framework 3.5**: actívalo en *Activar o desactivar las características de Windows → .NET Framework 3.5* (el setup te abre esa ventana) y vuelve a ejecutar el instalador.
- **SourceTree pide iniciar sesión al abrirlo**: sáltate el de Bitbucket; tus repos ya aparecen en la barra lateral y GitHub ya está conectado.
- **CADLAB**: no hay invitación por correo. Entra en cadlab.io con tu cuenta de GitHub y después escribe a Jorge (Technical Director) con tu usuario de GitHub para que te añada al equipo.
- **Un repo "no se pudo actualizar"**: tienes cambios locales o estás en una rama sin remoto. Ábrelo en SourceTree.

## Para leads

- Las apps, extensiones de VS Code (`vscodeExtensions`), perfiles, proyectos y enlaces se cambian en `config.json`, sin tocar el script. Tipos de app: `wingetId` (winget), `manual` (página de descarga), `download` (instalador oficial descargado e instalado en silencio, o abierto en el navegador si hay un antivirus de `antivirusNoDirectInstall` o la instalación falla; `githubRepo` + `assetPattern` toman la última release de GitHub, `url` es la alternativa y `mirror` una copia en `tools/` por si la web oficial cae) y `portable` (archivos de `tools/` copiados a `Apps\Tools`).
- Un proyecto con `installProfile` y `noArea` (Jet Engine) no pregunta perfil ni área.
- `invite-members.ps1 -Csv miembros.csv` invita en bloque a la organización desde un CSV con columna `email` (añade `-DryRun` para probar). Requiere ser owner. **No subas el CSV al repo.**
