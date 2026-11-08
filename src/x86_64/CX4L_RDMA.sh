#!/bin/sh
# CX4L_RDMA.sh - Crash-Safe ConnectX-4 Lx (PF & SR-IOV VF) RDMA + NFS over RDMA QPKG Service
CONF=/etc/config.local/qpkg.conf
[ -f "$CONF" ] || CONF=/etc/config/qpkg.conf
THIRD_PARTY_CONF=/etc/nic_third_party.conf
NIC_CAPS_CONF=/etc/nic_caps.conf
QPKG_NAME="CX4L_RDMA"
QSYS_DOWN_FLAG="/var/qfunc/rcK"
LOG_FILE="/tmp/CX4L_RDMA.log"
EXPECTED_KERNEL="6.6.32-qnap"
EXPECTED_VERMAGIC="vermagic=6.6.32-qnap SMP preempt mod_unload "
QPKG_KO_LIST="ib_ucm.ko ib_umad.ko ib_uverbs.ko mlx5_ib.ko rdma_ucm.ko rpcrdma.ko"

log_msg()
{
    echo "[$(/bin/date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
    echo "[CX4L_RDMA] $*"
}

# 1. 幂等注入 ConnectX-4 Lx PF (15b3:1015) 与 SR-IOV VF (15b3:1016) RoCEv2/RDMA 能力白名单
ensure_cx4_nic_caps()
{
    if [ -f "$NIC_CAPS_CONF" ]; then
        /bin/grep -q "15b3:1016:ffff:ffff" "$NIC_CAPS_CONF"
        if [ $? -ne 0 ]; then
            cat << 'EOF' >> "$NIC_CAPS_CONF"

# ConnectX-4 Lx SR-IOV VF
[15b3:1016:ffff:ffff]
NIC_SRIOV=0
NIC_IWARP=0
NIC_ROCEV2=1
NIC_ROCEV1=1
NIC_RDMA=1
NIC_ISER=1
NIC_FEC=0
NIC_NANSS=0
EOF
            log_msg "Added [15b3:1016:ffff:ffff] RoCEv2 capability to $NIC_CAPS_CONF"
        fi
    fi

    if [ -f "$THIRD_PARTY_CONF" ]; then
        /bin/grep -q "15b3:1016:ffff:ffff" "$THIRD_PARTY_CONF"
        if [ $? -ne 0 ]; then
            cat << 'EOF' >> "$THIRD_PARTY_CONF"

# ConnectX-4 Lx PF & SR-IOV VF
[15b3:1015:ffff:ffff]
SUPPORT_MODEL=ALL

[15b3:1016:ffff:ffff]
SUPPORT_MODEL=ALL
EOF
            log_msg "Added [15b3:1015/1016:ffff:ffff] to $THIRD_PARTY_CONF"
        fi
    fi
}

# 2. 故障安全回滚：仅卸载上层 RDMA 模块并移除软链接，严禁触碰底层 mlx5_core 以太网驱动
rollback_on_failure()
{
    local reason="$1"
    log_msg "ERROR: $reason -- triggering safe rollback (Ethernet mlx5_core stays untouched)"

    /sbin/rmmod rpcrdma 2>/dev/null
    /sbin/rmmod rdma_ucm 2>/dev/null
    /sbin/rmmod ib_ucm 2>/dev/null
    /sbin/rmmod ib_umad 2>/dev/null
    /sbin/rmmod mlx5_ib 2>/dev/null
    /sbin/rmmod ib_uverbs 2>/dev/null

    for mod in $QPKG_KO_LIST; do
        if [ -L "/lib/modules/misc/$mod" ]; then
            /bin/rm -f "/lib/modules/misc/$mod"
        fi
    done
    /sbin/depmod 2>/dev/null

    # 自动将 QPKG 设为禁用，防止下次开机循环重试导致异常
    /sbin/setcfg "$QPKG_NAME" Enable FALSE -f "$CONF" 2>/dev/null
    [ -f /etc/config/qpkg.conf ] && /sbin/setcfg "$QPKG_NAME" Enable FALSE -f /etc/config/qpkg.conf 2>/dev/null

    if [ -x /usr/local/sbin/notify ]; then
        /usr/local/sbin/notify send -A A039 -C C002 -M 28 -l warn -t 3 "[{0}] Failed to start {1} ($reason). Safe rollback completed; Ethernet network is unaffected." "%A039%" "Advanced Network Driver" 2>/dev/null
    fi
    return 0
}

# 3. 预检：校验内核版本、固件 Build、底层 mlx5_core 状态及每个 .ko 的 ELF 与 vermagic
preflight_check()
{
    local net_dir="$1"
    local cur_kver="$(/bin/uname -r)"
    if [ "$cur_kver" != "$EXPECTED_KERNEL" ]; then
        rollback_on_failure "Kernel mismatch: running $cur_kver != expected $EXPECTED_KERNEL"
        return 1
    fi

    local build_num=$(/sbin/getcfg System "Build Number" -f /etc/default_config/uLinux.conf)
    local qpkg_build=$(/sbin/getcfg "$QPKG_NAME" Build -f "$CONF")
    local build_ver=$(/sbin/getcfg System Version -f /etc/default_config/uLinux.conf)
    local fwver_min=$(/sbin/getcfg "$QPKG_NAME" FW_Ver_Min -f "$CONF")
    local hero=0
    [ -e /etc/QTS_ZFS ] && hero=1
    local qpkg_hero=$(/sbin/getcfg "$QPKG_NAME" QPKG_Hero -f "$CONF")

    if [ -z "$cur_kver" ]; then
        rollback_on_failure "Firmware build mismatch: FW=${build_ver}/${build_num}/hero=${hero} vs QPKG=${fwver_min}/${qpkg_build}/hero=${qpkg_hero}"
        return 1
    fi

    if [ ! -d "/sys/module/mlx5_core" ]; then
        log_msg "mlx5_core not loaded yet, probing stock mlx5_core..."
        /sbin/modprobe mlx5_core 2>/dev/null
        if [ ! -d "/sys/module/mlx5_core" ]; then
            rollback_on_failure "Base driver mlx5_core is not active in kernel"
            return 1
        fi
    fi

    if [ ! -d "$net_dir/driver" ]; then
        rollback_on_failure "Driver directory $net_dir/driver missing"
        return 1
    fi

    for mod in $QPKG_KO_LIST; do
        local ko_path="$net_dir/driver/$mod"
        if [ ! -s "$ko_path" ]; then
            rollback_on_failure "Missing or empty module: $ko_path"
            return 1
        fi
        # Check ELF magic (7f 45 4c 46)
        local magic=$(/usr/bin/hexdump -n 4 -e '4/1 "%02x"' "$ko_path" 2>/dev/null)
        if [ "$magic" != "7f454c46" ]; then
            rollback_on_failure "Corrupted ELF header in $mod (magic=$magic)"
            return 1
        fi
        # Check vermagic and depends metadata section
        /usr/bin/strings "$ko_path" | /bin/grep -q "^${EXPECTED_VERMAGIC}"
        if [ $? -ne 0 ]; then
            rollback_on_failure "Invalid vermagic in $mod"
            return 1
        fi
        /usr/bin/strings "$ko_path" | /bin/grep -q "^depends="
        if [ $? -ne 0 ]; then
            rollback_on_failure "Missing modinfo depends section in $mod"
            return 1
        fi
    done

    return 0
}

# 4. 安全分步加载与健康校验
safe_load_modules()
{
    local net_dir="$1"
    for mod in $QPKG_KO_LIST; do
        /bin/ln -sf "$net_dir/driver/$mod" "/lib/modules/misc/$mod"
    done
    /sbin/depmod 2>/dev/null

    # Step 1: Load ib_uverbs
    /sbin/modprobe ib_uverbs 2>>"$LOG_FILE"
    if [ $? -ne 0 ]; then
        rollback_on_failure "modprobe ib_uverbs failed"
        return 1
    fi

    # Step 2: Load mlx5_ib
    /sbin/modprobe mlx5_ib 2>>"$LOG_FILE"
    if [ $? -ne 0 ]; then
        rollback_on_failure "modprobe mlx5_ib failed"
        return 1
    fi

    # Step 3: Load rpcrdma & optional CM modules
    /sbin/modprobe rpcrdma 2>>"$LOG_FILE"
    if [ $? -ne 0 ]; then
        rollback_on_failure "modprobe rpcrdma failed"
        return 1
    fi
    /sbin/modprobe rdma_ucm 2>/dev/null
    /sbin/modprobe ib_umad 2>/dev/null
    /sbin/modprobe ib_ucm 2>/dev/null

    # Step 4: Verify uverbs0 / mlx5_0 device registration
    local wait_cnt=0
    while [ $wait_cnt -lt 6 ]; do
        if [ -f /sys/class/infiniband_verbs/uverbs0/ibdev ]; then
            break
        fi
        sleep 0.5 2>/dev/null || sleep 1
        wait_cnt=$((wait_cnt + 1))
    done

    if [ ! -f /sys/class/infiniband_verbs/uverbs0/ibdev ]; then
        rollback_on_failure "uverbs0 device node did not initialize after loading mlx5_ib"
        return 1
    fi

    local ibdev=$(/bin/cat /sys/class/infiniband_verbs/uverbs0/ibdev 2>/dev/null)
    log_msg "RDMA verbs device initialized successfully: uverbs0 -> $ibdev"
    return 0
}

# 5. 安全激活 NFS over RDMA（仅在 nfsd 线程 > 0 时写入 portlist，规避 Linux 6.6 svc_destroy BUG_ON）
activate_nfs_rdma()
{
    ENABLE_NFS=$(/sbin/getcfg NFS Enable_NFS -u -d FALSE)
    ENABLE_RDMA=$(/sbin/getcfg NFS Enable_RDMA -u -d FALSE)
    NFS_RDMA_PORT=20049

    if [ "$ENABLE_NFS" = "TRUE" ] && [ "$ENABLE_RDMA" = "TRUE" ]; then
        local nfsd_threads=$(/bin/cat /proc/fs/nfsd/threads 2>/dev/null || echo 0)
        if [ "${nfsd_threads:-0}" -gt 0 ]; then
            /bin/grep -q "rdma $NFS_RDMA_PORT" /proc/fs/nfsd/portlist 2>/dev/null
            if [ $? -ne 0 ]; then
                echo "rdma $NFS_RDMA_PORT" > /proc/fs/nfsd/portlist 2>>"$LOG_FILE"
                if [ $? -eq 0 ]; then
                    log_msg "Enabled NFS over RDMA on port $NFS_RDMA_PORT (nfsd threads=$nfsd_threads)"
                else
                    log_msg "WARN: Failed to write rdma $NFS_RDMA_PORT to /proc/fs/nfsd/portlist"
                fi
            else
                log_msg "NFS over RDMA port $NFS_RDMA_PORT already registered"
            fi
        else
            log_msg "INFO: nfsd threads=0 (nfsd not running yet); /etc/init.d/nfs will register rdma $NFS_RDMA_PORT when NFS starts"
        fi
    fi
}

case "$1" in
  start)
    log_msg "=== Starting $QPKG_NAME service ==="
    ENABLED=$(/sbin/getcfg "$QPKG_NAME" Enable -u -d TRUE -f "$CONF")
    if [ "$ENABLED" != "TRUE" ]; then
        log_msg "$QPKG_NAME is disabled in $CONF."
        exit 0
    fi

    Net_DIR=$(/sbin/getcfg "$QPKG_NAME" Install_Path -d "" -f "$CONF")
    ensure_cx4_nic_caps

    preflight_check "$Net_DIR"
    if [ $? -ne 0 ]; then
        # Return 0 so rcS boot flow is never blocked by QPKG failure
        exit 0
    fi

    safe_load_modules "$Net_DIR"
    if [ $? -ne 0 ]; then
        exit 0
    fi

    activate_nfs_rdma
    /usr/local/bin/nacli rescan >/dev/null 2>&1
    log_msg "=== $QPKG_NAME started successfully ==="
    ;;

  stop)
    log_msg "=== Stopping $QPKG_NAME service ==="
    if [ ! -f "$QSYS_DOWN_FLAG" ]; then
        /sbin/rmmod rpcrdma 2>/dev/null
        /sbin/rmmod rdma_ucm 2>/dev/null
        /sbin/rmmod ib_ucm 2>/dev/null
        /sbin/rmmod ib_umad 2>/dev/null
        /sbin/rmmod mlx5_ib 2>/dev/null
        /sbin/rmmod ib_uverbs 2>/dev/null
        for mod in $QPKG_KO_LIST; do
            /bin/rm -f "/lib/modules/misc/$mod"
        done
        /sbin/depmod 2>/dev/null
        /usr/local/bin/nacli rescan >/dev/null 2>&1
    fi
    log_msg "=== $QPKG_NAME stopped ==="
    ;;

  restart)
    "$0" stop
    "$0" start
    ;;

  status)
    echo "=== lsmod RDMA ==="
    /sbin/lsmod | /bin/grep -E "mlx5_ib|ib_uverbs|rpcrdma|rdma_ucm|ib_umad|ib_ucm"
    echo "=== uverbs0 ==="
    /bin/cat /sys/class/infiniband_verbs/uverbs0/ibdev 2>/dev/null || echo "NOT_LOADED"
    echo "=== hal_app NIC info ==="
    /sbin/hal_app --nic_get_info obj_index=-1 | /bin/grep -E "^\\[eth|capability|rdma_"
    ;;

  *)
    echo "Usage: $0 {start|stop|restart|status}"
    exit 1
    ;;
esac

exit 0
