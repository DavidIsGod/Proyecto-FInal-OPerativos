<#
===============================================================================
 datacenter.ps1 - Herramienta de administración de Data Center (PowerShell)
-------------------------------------------------------------------------------
 Universidad ICESI - Sistemas Operacionales - Proyecto Final

 Despliega un menú con 5 utilidades para el administrador de un data center:
   1. Usuarios del sistema y su último ingreso (login).
   2. Filesystems / discos conectados, con tamaño y espacio libre (en bytes).
   3. Los 10 archivos más grandes de un disco/filesystem indicado (ruta completa).
   4. Memoria libre y swap (archivo de paginación) en uso (bytes y porcentaje).
   5. Backup de un directorio a una memoria USB, con catálogo de archivos.

 Uso:   powershell -ExecutionPolicy Bypass -File .\datacenter.ps1
        (o en PowerShell 7+:  pwsh -File .\datacenter.ps1)

 Nota: pensado para Windows (usa cmdlets/WMI de Windows: Get-LocalUser,
       Win32_LogicalDisk, Win32_OperatingSystem, Win32_PageFileUsage).
===============================================================================
#>

# Forzamos parada ante errores no controlados dentro de cada función.
$ErrorActionPreference = 'Stop'

#------------------------------------------------------------------------------
# Utilidades comunes
#------------------------------------------------------------------------------

# Imprime un encabezado de sección.
function Print-Header {
    param([string]$Texto)
    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "  $Texto" -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan
}

# Pausa hasta que el usuario presione ENTER.
function Pause-Menu {
    Write-Host ""
    [void](Read-Host "Presione ENTER para volver al menú")
}

# Convierte bytes a una forma legible (KiB, MiB, GiB...).
function Format-Bytes {
    param([double]$Bytes)
    $u = @('B','KiB','MiB','GiB','TiB','PiB')
    $i = 0
    while ($Bytes -ge 1024 -and $i -lt 5) { $Bytes /= 1024; $i++ }
    if ($i -eq 0) { return ('{0:N0} {1}' -f $Bytes, $u[$i]) }
    return ('{0:N2} {1}' -f $Bytes, $u[$i])
}

#==============================================================================
# OPCIÓN 1: Usuarios del sistema y su último ingreso (login)
#==============================================================================
# Get-LocalUser enumera las cuentas locales. La propiedad LastLogon contiene la
# fecha del último inicio de sesión local (puede estar vacía si nunca ingresó).
function Opcion-Usuarios {
    Print-Header "1. Usuarios del sistema y último ingreso (login)"
    try {
        $usuarios = Get-LocalUser
        $tabla = foreach ($u in $usuarios) {
            $ultimo = if ($u.LastLogon) { $u.LastLogon.ToString('yyyy-MM-dd HH:mm:ss') }
                      else { '**Nunca ha ingresado**' }
            [PSCustomObject]@{
                Usuario        = $u.Name
                Habilitado     = $u.Enabled
                'Último ingreso' = $ultimo
            }
        }
        $tabla | Format-Table -AutoSize | Out-Host
    }
    catch {
        # Si Get-LocalUser no está disponible, usamos WMI como alternativa.
        Write-Host "Get-LocalUser no disponible; usando Win32_UserAccount..." -ForegroundColor Yellow
        Get-CimInstance Win32_UserAccount -Filter "LocalAccount=True" |
            Select-Object Name, Disabled | Format-Table -AutoSize | Out-Host
    }
    Pause-Menu
}

#==============================================================================
# OPCIÓN 2: Filesystems / discos conectados (tamaño y libre en bytes)
#==============================================================================
# Win32_LogicalDisk expone Size y FreeSpace directamente EN BYTES.
function Opcion-Filesystems {
    Print-Header "2. Filesystems / discos conectados (tamaño y libre en bytes)"

    $discos = Get-CimInstance Win32_LogicalDisk |
              Where-Object { $_.Size -gt 0 }

    $tabla = foreach ($d in $discos) {
        [PSCustomObject]@{
            Unidad           = $d.DeviceID
            Etiqueta         = $d.VolumeName
            Sistema          = $d.FileSystem
            'Tamaño (bytes)' = $d.Size
            'Libre (bytes)'  = $d.FreeSpace
            'Tamaño'         = (Format-Bytes $d.Size)
            'Libre'          = (Format-Bytes $d.FreeSpace)
        }
    }
    $tabla | Format-Table -AutoSize | Out-Host
    Pause-Menu
}

#==============================================================================
# OPCIÓN 3: Los 10 archivos más grandes de un disco/filesystem indicado
#==============================================================================
function Opcion-ArchivosGrandes {
    Print-Header "3. Los 10 archivos más grandes de un filesystem"

    $ruta = Read-Host "Indique la ruta del disco/filesystem (ej. C:\ o C:\Users)"
    if ([string]::IsNullOrWhiteSpace($ruta)) { $ruta = 'C:\' }

    if (-not (Test-Path -LiteralPath $ruta -PathType Container)) {
        Write-Host "Error: '$ruta' no existe o no es un directorio." -ForegroundColor Red
        Pause-Menu; return
    }

    Write-Host "Buscando en '$ruta' (puede tardar)..."
    # -File: solo archivos. -ErrorAction SilentlyContinue: ignora carpetas sin permiso.
    $archivos = Get-ChildItem -LiteralPath $ruta -Recurse -File -ErrorAction SilentlyContinue |
                Sort-Object Length -Descending |
                Select-Object -First 10

    $tabla = foreach ($a in $archivos) {
        [PSCustomObject]@{
            'Tamaño (bytes)' = $a.Length
            'Tamaño'         = (Format-Bytes $a.Length)
            'Ruta completa'  = $a.FullName
        }
    }
    $tabla | Format-Table -AutoSize | Out-Host
    Pause-Menu
}

#==============================================================================
# OPCIÓN 4: Memoria libre y swap (paginación) en uso (bytes y porcentaje)
#==============================================================================
# Win32_OperatingSystem da memoria física total/libre EN KB.
# Win32_PageFileUsage da el uso del archivo de paginación (swap) EN MB.
function Opcion-Memoria {
    Print-Header "4. Memoria libre y espacio de swap en uso"

    $os = Get-CimInstance Win32_OperatingSystem
    # Valores en KB -> bytes.
    $memTotalB = [int64]$os.TotalVisibleMemorySize * 1024
    $memFreeB  = [int64]$os.FreePhysicalMemory     * 1024
    $memFreePct = if ($memTotalB -gt 0) { ($memFreeB * 100.0 / $memTotalB) } else { 0 }

    Write-Host "MEMORIA RAM"
    Write-Host ("  Total : {0,18:N0} bytes  ({1})" -f $memTotalB, (Format-Bytes $memTotalB))
    Write-Host ("  Libre : {0,18:N0} bytes  ({1})  -> {2:N2}% libre" -f `
        $memFreeB, (Format-Bytes $memFreeB), $memFreePct) -ForegroundColor Green

    Write-Host ""
    Write-Host "SWAP (archivo de paginación)"
    $pf = Get-CimInstance Win32_PageFileUsage
    if (-not $pf) {
        Write-Host "  No hay archivo de paginación configurado." -ForegroundColor Yellow
    }
    else {
        # AllocatedBaseSize y CurrentUsage están EN MB -> bytes.
        $swapTotalB = ($pf | Measure-Object -Property AllocatedBaseSize -Sum).Sum * 1MB
        $swapUsedB  = ($pf | Measure-Object -Property CurrentUsage      -Sum).Sum * 1MB
        $swapUsedPct = if ($swapTotalB -gt 0) { ($swapUsedB * 100.0 / $swapTotalB) } else { 0 }

        Write-Host ("  Total  : {0,18:N0} bytes  ({1})" -f $swapTotalB, (Format-Bytes $swapTotalB))
        Write-Host ("  En uso : {0,18:N0} bytes  ({1})  -> {2:N2}% en uso" -f `
            $swapUsedB, (Format-Bytes $swapUsedB), $swapUsedPct) -ForegroundColor Yellow
    }
    Pause-Menu
}

#==============================================================================
# OPCIÓN 5: Backup de un directorio a una memoria USB (con catálogo)
#==============================================================================
function Opcion-Backup {
    Print-Header "5. Backup de un directorio a una memoria USB"

    # --- 5.1 Directorio de origen ---
    $origen = Read-Host "Directorio de ORIGEN a respaldar"
    if ([string]::IsNullOrWhiteSpace($origen) -or
        -not (Test-Path -LiteralPath $origen -PathType Container)) {
        Write-Host "Error: el directorio de origen no existe." -ForegroundColor Red
        Pause-Menu; return
    }

    # --- 5.2 Detectar unidades USB (extraíbles, DriveType=2) ---
    Write-Host ""
    Write-Host "Unidades USB / extraíbles detectadas:"
    # La detección es auxiliar: si CIM no está disponible, el backup continúa
    # igualmente porque el destino se indica manualmente más abajo.
    try {
        $usb = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2" -ErrorAction Stop
        if ($usb) {
            $usb | Select-Object DeviceID, VolumeName,
                @{N='Libre';E={ Format-Bytes $_.FreeSpace }} |
                Format-Table -AutoSize | Out-Host
        }
        else {
            Write-Host "  No se detectaron unidades USB extraíbles." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  (No se pudo enumerar unidades USB en este sistema.)" -ForegroundColor Yellow
    }

    # --- 5.3 Destino ---
    $destino = Read-Host "Ruta de DESTINO (unidad/punto de montaje de la USB, ej. E:\)"
    if ([string]::IsNullOrWhiteSpace($destino) -or
        -not (Test-Path -LiteralPath $destino -PathType Container)) {
        Write-Host "Error: el destino '$destino' no existe." -ForegroundColor Red
        Pause-Menu; return
    }

    # --- 5.4 Carpeta de backup con fecha/hora ---
    $stamp     = Get-Date -Format 'yyyyMMdd_HHmmss'
    $baseName  = Split-Path -Path $origen.TrimEnd('\') -Leaf
    $backupDir = Join-Path $destino ("backup_{0}_{1}" -f $baseName, $stamp)
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

    Write-Host ""
    Write-Host "Copiando '$origen' -> '$backupDir' ..."
    try {
        # Copiamos todo el contenido del origen al directorio de backup.
        Copy-Item -Path (Join-Path $origen '*') -Destination $backupDir -Recurse -Force
        Write-Host "Copia de archivos completada." -ForegroundColor Green
    }
    catch {
        Write-Host "Ocurrió un error durante la copia: $_" -ForegroundColor Red
        Pause-Menu; return
    }

    # --- 5.5 Catálogo: nombre de archivo + fecha de última modificación ---
    $catalogo = Join-Path $backupDir 'catalogo.txt'
    $lineas = @()
    $lineas += "CATÁLOGO DE BACKUP"
    $lineas += "Origen      : $origen"
    $lineas += "Destino     : $backupDir"
    $lineas += "Generado el : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $lineas += "----------------------------------------------------------------"
    $lineas += ("{0,-19}  {1}" -f 'ÚLTIMA MODIFICACIÓN', 'ARCHIVO')
    $lineas += "----------------------------------------------------------------"

    $todos = Get-ChildItem -LiteralPath $origen -Recurse -File -ErrorAction SilentlyContinue
    foreach ($f in $todos) {
        $lineas += ("{0,-19}  {1}" -f $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'), $f.FullName)
    }
    $lineas | Out-File -FilePath $catalogo -Encoding UTF8

    Write-Host "Catálogo generado: $catalogo  ($($todos.Count) archivos)" -ForegroundColor Green
    Write-Host "Backup finalizado correctamente." -ForegroundColor Green
    Pause-Menu
}

#==============================================================================
# MENÚ PRINCIPAL
#==============================================================================
function Mostrar-Menu {
    Clear-Host
    Write-Host ""
    Write-Host "  +==========================================================+" -ForegroundColor Green
    Write-Host "  |      HERRAMIENTA DE ADMINISTRACION DE DATA CENTER         |" -ForegroundColor Green
    Write-Host "  |                  (PowerShell) - ICESI                     |" -ForegroundColor Green
    Write-Host "  +==========================================================+" -ForegroundColor Green
    Write-Host ""
    Write-Host "  1) Usuarios del sistema y su último ingreso (login)"
    Write-Host "  2) Filesystems / discos conectados (tamaño y libre en bytes)"
    Write-Host "  3) Los 10 archivos más grandes de un filesystem"
    Write-Host "  4) Memoria libre y swap en uso (bytes y porcentaje)"
    Write-Host "  5) Backup de un directorio a una memoria USB"
    Write-Host "  0) Salir"
    Write-Host ""
}

function Main {
    while ($true) {
        Mostrar-Menu
        $opcion = Read-Host "  Seleccione una opción [0-5]"
        switch ($opcion) {
            '1' { Opcion-Usuarios }
            '2' { Opcion-Filesystems }
            '3' { Opcion-ArchivosGrandes }
            '4' { Opcion-Memoria }
            '5' { Opcion-Backup }
            '0' { Write-Host ""; Write-Host "Saliendo. ¡Hasta pronto!" -ForegroundColor Green; return }
            default { Write-Host "Opción inválida. Intente de nuevo." -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

Main
