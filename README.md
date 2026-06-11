# Proyecto Final — Herramientas de Administración de Data Center

**Universidad ICESI — Facultad de Ingeniería, Diseño y Ciencias Aplicadas**
**Sistemas Operacionales**

Este proyecto contiene **dos herramientas** que facilitan las labores del
administrador de un data center. Ambas ofrecen el **mismo menú con 5 opciones**,
implementadas en dos tecnologías:

| Herramienta | Archivo | Plataforma |
|-------------|---------|------------|
| **BASH** | [`bash/datacenter.sh`](bash/datacenter.sh) | Linux / Unix |
| **PowerShell** | [`powershell/datacenter.ps1`](powershell/datacenter.ps1) | Windows |

---

## Menú (idéntico en ambas herramientas)

1. **Usuarios del sistema y último ingreso (login).**
2. **Filesystems / discos conectados**, con su tamaño y espacio libre **en bytes**.
3. **Los 10 archivos más grandes** de un disco/filesystem que indique el usuario, con su **ruta completa**.
4. **Memoria libre** y **espacio de swap en uso**, expresados **en bytes y en porcentaje**.
5. **Backup** de un directorio a una **memoria USB**, generando además un **catálogo** con los nombres de los archivos y su fecha de última modificación.
0. Salir.

---

## Cómo ejecutar

### BASH (Linux)
```bash
cd bash
chmod +x datacenter.sh      # solo la primera vez
./datacenter.sh             # o:  bash datacenter.sh
```
> La opción 1 (lectura de `/var/log/lastlog`) y la opción 5 (escritura en la USB)
> pueden requerir permisos; si es necesario ejecútelo con `sudo ./datacenter.sh`.

### PowerShell (Windows)
```powershell
cd powershell
powershell -ExecutionPolicy Bypass -File .\datacenter.ps1
# o en PowerShell 7+:
pwsh -File .\datacenter.ps1
```
> Algunas consultas (usuarios, discos) se ven mejor ejecutando PowerShell **como
> Administrador**.

---

## Cómo funciona cada opción (detalle técnico)

A continuación se explica **qué comando del sistema operativo** resuelve cada
requisito. Esto es lo que conviene saber para la sustentación.

### Opción 1 — Usuarios y último login

| | BASH | PowerShell |
|---|---|---|
| Fuente de usuarios | `/etc/passwd` (cuentas humanas: UID 0 y UID ≥ 1000) | `Get-LocalUser` |
| Último login | `lastlog` (lee `/var/log/lastlog`) | propiedad `LastLogon` |

- En **BASH** se recorre `/etc/passwd` filtrando las cuentas reales (root y las de
  usuario, UID ≥ 1000; se omite `nobody`). Para cada una, `lastlog -u` entrega la
  fecha del último ingreso; si nunca ha ingresado se indica explícitamente.
- En **Windows**, `Get-LocalUser` ya trae la propiedad `LastLogon`.

### Opción 2 — Filesystems / discos (tamaño y libre en bytes)

| BASH | PowerShell |
|---|---|
| `df -B1` (bloques de **1 byte** ⇒ salida directamente en bytes) | `Win32_LogicalDisk` (propiedades `Size` y `FreeSpace`, **ya en bytes**) |

- En **BASH** se usa `df -B1 --output=source,fstype,size,used,avail,target` y se
  excluyen pseudo-filesystems (`tmpfs`, `devtmpfs`, `squashfs`, `overlay`). Además
  se listan los discos físicos con `lsblk`.
- En **Windows** se consulta `Get-CimInstance Win32_LogicalDisk`, cuyas
  propiedades `Size`/`FreeSpace` ya están expresadas en bytes.

### Opción 3 — Los 10 archivos más grandes

| BASH | PowerShell |
|---|---|
| `find <ruta> -xdev -type f -printf '%s\t%p\n' \| sort -rn \| head -10` | `Get-ChildItem -Recurse -File \| Sort-Object Length -Descending \| Select -First 10` |

- `-xdev` (BASH) mantiene la búsqueda **dentro del mismo filesystem** indicado.
- Se muestra el **tamaño en bytes** y la **ruta completa** de cada archivo.

### Opción 4 — Memoria libre y swap en uso (bytes y %)

| | BASH | PowerShell |
|---|---|---|
| Memoria | `/proc/meminfo` → `MemTotal`, `MemFree` (kB → bytes) | `Win32_OperatingSystem` → `TotalVisibleMemorySize`, `FreePhysicalMemory` (KB → bytes) |
| Swap | `/proc/meminfo` → `SwapTotal − SwapFree` | `Win32_PageFileUsage` → `AllocatedBaseSize`, `CurrentUsage` (MB → bytes) |

- **Swap en uso** = `Total − Libre`. El **porcentaje** = `enUso / total × 100`.
- Se contempla el caso de que **no exista swap / archivo de paginación**.

### Opción 5 — Backup a USB + catálogo

1. Se piden el **directorio de origen** y el **destino** (punto de montaje de la USB).
2. Se detectan automáticamente las unidades extraíbles:
   - BASH: `lsblk` filtrando dispositivos con bandera removible `RM=1`.
   - PowerShell: `Win32_LogicalDisk` con `DriveType=2` (extraíble).
3. Se crea en la USB una carpeta `backup_<origen>_<fecha_hora>`.
4. Se copian los archivos preservando metadatos (`cp -a` / `Copy-Item -Recurse`).
5. Se genera **`catalogo.txt`** con la **fecha de última modificación** y la
   **ruta de cada archivo** (`find -printf` / `Get-ChildItem … LastWriteTime`).

---

## Auditoría / pruebas realizadas

> Las herramientas fueron probadas antes de la entrega. Resumen de la verificación:

### BASH (probado en Ubuntu 24.04, GNU bash 5.2)
- ✅ `bash -n` (verificación de sintaxis) sin errores.
- ✅ **Opción 1**: lista `root` y usuarios reales con su estado de último login.
- ✅ **Opción 2**: muestra `/dev/sda4`, `/dev/sda3`, etc. con tamaño/usado/libre en
  bytes y su equivalente legible; lista discos físicos con `lsblk`.
- ✅ **Opción 3**: probada sobre `/usr/lib`; devuelve los 10 mayores con ruta completa.
- ✅ **Opción 4**: RAM total/libre y swap en uso, en bytes y porcentaje; maneja swap = 0.
- ✅ **Opción 5**: backup de un directorio de prueba con subcarpetas; archivos
  copiados correctamente y `catalogo.txt` con fechas correctas (se preservan con `cp -a`).
- ✅ **Manejo de errores**: opción de menú inválida, rutas inexistentes y destino sin
  permisos de escritura se reportan sin que el programa se caiga.

### PowerShell (verificado con PowerShell 7.4)
- ✅ Análisis sintáctico (`[Parser]::ParseFile`) sin errores.
- ✅ **Opción 3** y **Opción 5** ejecutadas y verificadas (cmdlets multiplataforma):
  ordenamiento por tamaño y backup + catálogo correctos.
- ℹ️ **Opciones 1, 2 y 4** usan WMI/cmdlets propios de **Windows**
  (`Get-LocalUser`, `Win32_LogicalDisk`, `Win32_OperatingSystem`,
  `Win32_PageFileUsage`); se validaron sintácticamente y deben ejecutarse en Windows.

---

## Estructura del repositorio
```
.
├── README.md                 # Esta documentación
├── Proyecto final.pdf        # Enunciado del proyecto
├── bash/
│   └── datacenter.sh         # Herramienta en BASH (Linux)
└── powershell/
    └── datacenter.ps1        # Herramienta en PowerShell (Windows)
```

---

## Equipo
- _(Completar con los nombres del equipo — máximo 3 personas)_
