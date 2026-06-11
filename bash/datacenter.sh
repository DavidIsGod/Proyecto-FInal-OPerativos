#!/usr/bin/env bash
#===============================================================================
# datacenter.sh - Herramienta de administración de Data Center (BASH)
#-------------------------------------------------------------------------------
# Universidad ICESI - Sistemas Operacionales - Proyecto Final
#
# Despliega un menú con 5 utilidades para el administrador de un data center:
#   1. Usuarios del sistema y su último ingreso (login).
#   2. Filesystems / discos conectados, con tamaño y espacio libre (en bytes).
#   3. Los 10 archivos más grandes de un filesystem indicado (ruta completa).
#   4. Memoria libre y swap en uso (en bytes y porcentaje).
#   5. Backup de un directorio a una memoria USB, con catálogo de archivos.
#
# Uso:   bash datacenter.sh        (o ./datacenter.sh tras chmod +x)
#===============================================================================

# ---- Configuración de robustez -----------------------------------------------
set -o pipefail                 # un fallo en una tubería se propaga
export LC_ALL=C                 # salida de comandos y números en formato estable

# ---- Colores (solo si la salida es una terminal) -----------------------------
if [[ -t 1 ]]; then
    BOLD=$'\e[1m'; GREEN=$'\e[32m'; CYAN=$'\e[36m'; YELLOW=$'\e[33m'
    RED=$'\e[31m'; RESET=$'\e[0m'
else
    BOLD=""; GREEN=""; CYAN=""; YELLOW=""; RED=""; RESET=""
fi

# ---- Utilidades comunes ------------------------------------------------------

# Imprime un encabezado de sección.
print_header() {
    echo
    echo "${BOLD}${CYAN}========================================================${RESET}"
    echo "${BOLD}${CYAN}  $1${RESET}"
    echo "${BOLD}${CYAN}========================================================${RESET}"
}

# Pausa hasta que el usuario presione ENTER (para volver al menú).
pause() {
    echo
    read -rp "${YELLOW}Presione ENTER para volver al menú...${RESET} " _
}

# Convierte un número de bytes a una forma legible (KiB, MiB, GiB...).
# Uso: human_bytes 1536  ->  1.50 KiB
human_bytes() {
    local bytes=${1:-0}
    awk -v b="$bytes" 'BEGIN{
        split("B KiB MiB GiB TiB PiB", u, " ");
        i=1;
        while (b>=1024 && i<6){ b=b/1024; i++ }
        if (i==1) printf "%d %s", b, u[i];
        else      printf "%.2f %s", b, u[i];
    }'
}

#===============================================================================
# OPCIÓN 1: Usuarios del sistema y su último ingreso (login)
#===============================================================================
# "Usuarios creados en el sistema": se consideran las cuentas humanas, es decir
# root (UID 0) y las cuentas regulares (UID >= 1000), excluyendo la cuenta
# especial "nobody" (UID 65534). La fecha del último login se obtiene de
# 'lastlog', que lee /var/log/lastlog.
opcion_usuarios() {
    print_header "1. Usuarios del sistema y último ingreso (login)"
    printf "${BOLD}%-18s %-8s %s${RESET}\n" "USUARIO" "UID" "ÚLTIMO INGRESO (LOGIN)"
    echo "--------------------------------------------------------------------"

    # Recorremos /etc/passwd: campo1=usuario, campo3=UID.
    while IFS=: read -r usuario _ uid _ _ _ _; do
        # Filtramos a cuentas humanas: root (0) o regulares (>=1000), sin nobody.
        if [[ "$uid" -eq 0 || ( "$uid" -ge 1000 && "$uid" -ne 65534 ) ]]; then
            # 'lastlog -u' devuelve cabecera + línea del usuario. Tomamos la 2a
            # y extraemos la fecha desde el día de la semana (robusto frente a
            # columnas Port/From vacías). Si nunca ingresó, lo indicamos.
            local ultimo
            ultimo=$(lastlog -u "$usuario" 2>/dev/null | awk 'NR==2{
                if ($0 ~ /Never logged in/) { print "**Nunca ha ingresado**"; }
                else {
                    match($0, /(Mon|Tue|Wed|Thu|Fri|Sat|Sun) .*/);
                    if (RSTART>0) print substr($0, RSTART);
                    else print "(sin datos)";
                }
            }')
            [[ -z "$ultimo" ]] && ultimo="(sin datos)"
            printf "%-18s %-8s %s\n" "$usuario" "$uid" "$ultimo"
        fi
    done < /etc/passwd

    echo
    echo "${GREEN}Sugerencia:${RESET} 'last' muestra el historial completo de sesiones."
    pause
}

#===============================================================================
# OPCIÓN 2: Filesystems / discos conectados (tamaño y espacio libre en bytes)
#===============================================================================
# Usamos 'df -B1' para forzar la salida en bytes (-B1 = bloques de 1 byte).
# Excluimos pseudo-filesystems (tmpfs, devtmpfs, squashfs, overlay) para
# mostrar discos/particiones reales.
opcion_filesystems() {
    print_header "2. Filesystems / discos conectados (tamaño y libre en bytes)"

    printf "${BOLD}%-22s %-10s %18s %18s %18s   %s${RESET}\n" \
        "FILESYSTEM" "TIPO" "TAMAÑO(bytes)" "USADO(bytes)" "LIBRE(bytes)" "MONTADO EN"
    echo "------------------------------------------------------------------------------------------------------------"

    # --output da columnas concretas; -B1 las pone en bytes.
    df -B1 --output=source,fstype,size,used,avail,target \
       -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs 2>/dev/null \
    | tail -n +2 \
    | while read -r source fstype size used avail target; do
        printf "%-22s %-10s %18s %18s %18s   %s\n" \
            "$source" "$fstype" "$size" "$used" "$avail" "$target"
        printf "%-22s %-10s %18s %18s %18s\n" \
            "" "" "($(human_bytes "$size"))" "($(human_bytes "$used"))" "($(human_bytes "$avail"))"
    done

    echo
    echo "${GREEN}Discos físicos detectados (lsblk):${RESET}"
    lsblk -d -o NAME,SIZE,TYPE,MODEL 2>/dev/null | grep -E 'disk|NAME'
    pause
}

#===============================================================================
# OPCIÓN 3: Los 10 archivos más grandes de un filesystem indicado
#===============================================================================
# El usuario indica la ruta del disco/filesystem. Con 'find -xdev' nos quedamos
# en ese mismo filesystem (no cruzamos puntos de montaje), listamos archivos
# regulares con su tamaño (%s) y ruta completa (%p), ordenamos y tomamos 10.
opcion_archivos_grandes() {
    print_header "3. Los 10 archivos más grandes de un filesystem"

    local ruta
    read -rp "Indique la ruta del disco/filesystem (ej. / o /home): " ruta
    ruta=${ruta:-/}                       # por defecto la raíz

    if [[ ! -d "$ruta" ]]; then
        echo "${RED}Error:${RESET} '$ruta' no existe o no es un directorio."
        pause; return
    fi

    echo
    echo "Buscando en '${BOLD}$ruta${RESET}' (puede tardar)..."
    echo "${BOLD}$(printf '%18s   %s' 'TAMAÑO(bytes)' 'RUTA COMPLETA')${RESET}"
    echo "------------------------------------------------------------------------"

    # -xdev: permanecer en el mismo filesystem que 'ruta'.
    # -printf '%s\t%p\n': tamaño en bytes + TAB + ruta completa.
    # Ordenamos numéricamente descendente y tomamos las 10 primeras.
    find "$ruta" -xdev -type f -printf '%s\t%p\n' 2>/dev/null \
        | sort -rn | head -10 \
        | while IFS=$'\t' read -r size path; do
            printf '%18s   %s\n' "$size" "$path"
            printf '%18s   %s\n' "($(human_bytes "$size"))" ""
        done

    pause
}

#===============================================================================
# OPCIÓN 4: Memoria libre y swap en uso (bytes y porcentaje)
#===============================================================================
# Leemos /proc/meminfo (valores en kB). Calculamos:
#   - Memoria libre  = MemFree
#   - Swap en uso    = SwapTotal - SwapFree
# Mostramos cada uno en bytes y como porcentaje de su total.
opcion_memoria() {
    print_header "4. Memoria libre y espacio de swap en uso"

    # Extraemos valores (en kB) de /proc/meminfo.
    local mem_total mem_free swap_total swap_free
    mem_total=$(awk '/^MemTotal:/  {print $2}' /proc/meminfo)
    mem_free=$( awk '/^MemFree:/   {print $2}' /proc/meminfo)
    swap_total=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
    swap_free=$( awk '/^SwapFree:/  {print $2}' /proc/meminfo)

    # Pasamos a bytes (1 kB de /proc/meminfo = 1024 bytes).
    local mem_total_b=$(( mem_total * 1024 ))
    local mem_free_b=$((  mem_free  * 1024 ))
    local swap_total_b=$(( swap_total * 1024 ))
    local swap_free_b=$((  swap_free  * 1024 ))
    local swap_used_b=$(( swap_total_b - swap_free_b ))

    # Porcentajes (con awk para usar decimales y evitar división por cero).
    local mem_free_pct swap_used_pct
    mem_free_pct=$(awk -v f="$mem_free_b" -v t="$mem_total_b" \
        'BEGIN{ if(t>0) printf "%.2f", f*100/t; else print "0.00" }')
    swap_used_pct=$(awk -v u="$swap_used_b" -v t="$swap_total_b" \
        'BEGIN{ if(t>0) printf "%.2f", u*100/t; else print "0.00" }')

    echo "${BOLD}MEMORIA RAM${RESET}"
    printf "  Total       : %18s bytes  (%s)\n" "$mem_total_b" "$(human_bytes "$mem_total_b")"
    printf "  ${GREEN}Libre${RESET}       : %18s bytes  (%s)  -> ${GREEN}%s%%${RESET} libre\n" \
        "$mem_free_b" "$(human_bytes "$mem_free_b")" "$mem_free_pct"

    echo
    echo "${BOLD}SWAP${RESET}"
    if [[ "$swap_total_b" -eq 0 ]]; then
        echo "  ${YELLOW}No hay swap configurado en este sistema.${RESET}"
    else
        printf "  Total       : %18s bytes  (%s)\n" "$swap_total_b" "$(human_bytes "$swap_total_b")"
        printf "  ${YELLOW}En uso${RESET}      : %18s bytes  (%s)  -> ${YELLOW}%s%%${RESET} en uso\n" \
            "$swap_used_b" "$(human_bytes "$swap_used_b")" "$swap_used_pct"
    fi
    pause
}

#===============================================================================
# OPCIÓN 5: Backup de un directorio a una memoria USB (con catálogo)
#===============================================================================
# Detecta unidades USB (extraíbles) montadas, deja elegir destino, copia el
# directorio indicado y genera un catálogo (nombre de archivo + fecha de última
# modificación).
opcion_backup() {
    print_header "5. Backup de un directorio a una memoria USB"

    # --- 5.1 Directorio de origen ---
    local origen
    read -rp "Directorio de ORIGEN a respaldar: " origen
    if [[ -z "$origen" || ! -d "$origen" ]]; then
        echo "${RED}Error:${RESET} el directorio de origen no existe."
        pause; return
    fi

    # --- 5.2 Detectar unidades USB (extraíbles) montadas ---
    echo
    echo "${BOLD}Unidades USB / extraíbles montadas detectadas:${RESET}"
    # RM=1 indica dispositivo extraíble; pedimos solo las particiones montadas.
    local usb_mounts
    usb_mounts=$(lsblk -nr -o NAME,RM,TYPE,MOUNTPOINT 2>/dev/null \
        | awk '$2=="1" && $3=="part" && $4!="" {print $4}')

    if [[ -n "$usb_mounts" ]]; then
        nl -w2 -s') ' <<< "$usb_mounts"
    else
        echo "  ${YELLOW}No se detectaron unidades USB montadas automáticamente.${RESET}"
    fi

    # Permitimos elegir un destino de la lista o escribir una ruta manual
    # (útil para pruebas o si la USB se monta en otra ubicación).
    local destino
    echo
    read -rp "Ruta de DESTINO (punto de montaje de la USB): " destino
    if [[ -z "$destino" || ! -d "$destino" ]]; then
        echo "${RED}Error:${RESET} el destino '$destino' no existe o no es un directorio."
        pause; return
    fi
    if [[ ! -w "$destino" ]]; then
        echo "${RED}Error:${RESET} no hay permisos de escritura en '$destino'."
        pause; return
    fi

    # --- 5.3 Carpeta de backup con fecha/hora ---
    local stamp base_name backup_dir catalogo
    stamp=$(date +%Y%m%d_%H%M%S)
    base_name=$(basename "$origen")
    backup_dir="$destino/backup_${base_name}_${stamp}"
    mkdir -p "$backup_dir" || { echo "${RED}No se pudo crear $backup_dir${RESET}"; pause; return; }

    echo
    echo "Copiando '${BOLD}$origen${RESET}' -> '${BOLD}$backup_dir${RESET}' ..."
    # cp -a preserva permisos, fechas y enlaces (archivado fiel).
    if cp -a "$origen/." "$backup_dir/"; then
        echo "${GREEN}Copia de archivos completada.${RESET}"
    else
        echo "${RED}Ocurrió un error durante la copia.${RESET}"
        pause; return
    fi

    # --- 5.4 Catálogo: nombre de archivo + fecha de última modificación ---
    catalogo="$backup_dir/catalogo.txt"
    {
        echo "CATÁLOGO DE BACKUP"
        echo "Origen        : $origen"
        echo "Destino       : $backup_dir"
        echo "Generado el   : $(date '+%Y-%m-%d %H:%M:%S')"
        echo "----------------------------------------------------------------"
        printf "%-19s  %s\n" "ÚLTIMA MODIFICACIÓN" "ARCHIVO"
        echo "----------------------------------------------------------------"
        # Recorremos el origen listando ruta + fecha de modificación.
        # (se recortan las fracciones de segundo que añade find).
        find "$origen" -type f -printf '%TY-%Tm-%Td %TH:%TM:%TS  %p\n' \
            | sed -E 's/^([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})\.[0-9]+/\1/' \
            | sort
    } > "$catalogo"

    local total
    total=$(find "$origen" -type f | wc -l)
    echo "${GREEN}Catálogo generado:${RESET} $catalogo  (${total} archivos)"
    echo "${GREEN}Backup finalizado correctamente.${RESET}"
    pause
}

#===============================================================================
# MENÚ PRINCIPAL
#===============================================================================
mostrar_menu() {
    clear
    echo "${BOLD}${GREEN}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║      HERRAMIENTA DE ADMINISTRACIÓN DE DATA CENTER         ║"
    echo "  ║                     (BASH) - ICESI                        ║"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo "${RESET}"
    echo "  ${BOLD}1)${RESET} Usuarios del sistema y su último ingreso (login)"
    echo "  ${BOLD}2)${RESET} Filesystems / discos conectados (tamaño y libre en bytes)"
    echo "  ${BOLD}3)${RESET} Los 10 archivos más grandes de un filesystem"
    echo "  ${BOLD}4)${RESET} Memoria libre y swap en uso (bytes y porcentaje)"
    echo "  ${BOLD}5)${RESET} Backup de un directorio a una memoria USB"
    echo "  ${BOLD}0)${RESET} Salir"
    echo
}

main() {
    while true; do
        mostrar_menu
        read -rp "  Seleccione una opción [0-5]: " opcion
        case "$opcion" in
            1) opcion_usuarios ;;
            2) opcion_filesystems ;;
            3) opcion_archivos_grandes ;;
            4) opcion_memoria ;;
            5) opcion_backup ;;
            0) echo; echo "${GREEN}Saliendo. ¡Hasta pronto!${RESET}"; exit 0 ;;
            *) echo "${RED}Opción inválida. Intente de nuevo.${RESET}"; sleep 1 ;;
        esac
    done
}

main "$@"
