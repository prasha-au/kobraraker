export RINKHALS_ROOT=$(realpath /useremain/rinkhals/.current)
export RINKHALS_VERSION=$(cat $RINKHALS_ROOT/.version)
export RINKHALS_HOME=/useremain/home/rinkhals

export KOBRA_MODEL_ID=$(cat /userdata/app/gk/config/api.cfg | sed -nr 's/.*"modelId"\s*:\s*"([0-9]+)".*/\1/p')

if [ "$KOBRA_MODEL_ID" == "20021" ]; then
    export KOBRA_MODEL="Anycubic Kobra 2 Pro"
    export KOBRA_MODEL_CODE=K2P
elif [ "$KOBRA_MODEL_ID" == "20024" ]; then
    export KOBRA_MODEL="Anycubic Kobra 3"
    export KOBRA_MODEL_CODE=K3
elif [ "$KOBRA_MODEL_ID" == "20025" ]; then
    export KOBRA_MODEL="Anycubic Kobra S1"
    export KOBRA_MODEL_CODE=KS1
elif [ "$KOBRA_MODEL_ID" == "20026" ]; then
    export KOBRA_MODEL="Anycubic Kobra 3 Max"
    export KOBRA_MODEL_CODE=K3M
fi

export KOBRA_VERSION=$(cat /useremain/dev/version)
export KOBRA_DEVICE_ID=$(cat /useremain/dev/device_id 2> /dev/null)

export ORIGINAL_ROOT=/tmp/rinkhals/original

msleep() {
    usleep $(($1 * 1000))
}
beep() {
    echo 1 > /sys/class/pwm/pwmchip0/pwm0/enable
    usleep $(($1 * 1000))
    echo 0 > /sys/class/pwm/pwmchip0/pwm0/enable
}
log() {
    echo "${*}"

    mkdir -p $RINKHALS_ROOT/logs
    echo "$(date): ${*}" >> $RINKHALS_ROOT/logs/rinkhals.log
}
quit() {
    exit 1
}

check_compatibility() {
    if [ "$KOBRA_MODEL_CODE" != "K2P" ] && [ "$KOBRA_MODEL_CODE" == "K3" ] && [ "$KOBRA_MODEL_CODE" == "KS1" ] && [ "$KOBRA_MODEL_CODE" == "K3M" ]; then
        log "Your printer's model is not recognized, exiting"
        quit
    fi
}
is_verified_firmware() {
    if [ "$KOBRA_MODEL_CODE" = "K2P" ]; then
        if [ "$KOBRA_VERSION" = "3.1.2.3" ]; then
            echo 1
            return
        fi
    elif [ "$KOBRA_MODEL_CODE" = "K3" ]; then
        if [ "$KOBRA_VERSION" = "2.3.9.3" ] || [ "$KOBRA_VERSION" = "2.4.0" ]; then
            echo 1
            return
        fi
    elif [ "$KOBRA_MODEL_CODE" = "KS1" ]; then
        if [ "$KOBRA_VERSION" = "2.5.1.6" ] || [ "$KOBRA_VERSION" = "2.5.2.3" ]; then
            echo 1
            return
        fi
    elif [ "$KOBRA_MODEL_CODE" = "K3M" ]; then
        if [ "$KOBRA_VERSION" = "2.4.6" ]; then
            echo 1
            return
        fi
    fi

    echo 0
}

install_swu() {
    SWU_FILE=$1
    shift

    echo "> Extracting $SWU_FILE ..."

    mkdir -p /useremain/update_swu
    rm -rf /useremain/update_swu/*

    cd /useremain/update_swu

    unzip -P U2FsdGVkX19deTfqpXHZnB5GeyQ/dtlbHjkUnwgCi+w= $SWU_FILE -d /useremain
    if [ -f /useremain/update_swu/setup.tar.gz ]; then
        tar -xzf /useremain/update_swu/setup.tar.gz -C /useremain/update_swu
    elif [ -f /useremain/update_swu/setup.tar ]; then
        tar -xf /useremain/update_swu/setup.tar -C /useremain/update_swu
    fi

    echo "> Running update.sh ..."

    chmod +x update.sh
    ./update.sh $@
}

get_command_line() {
    PID=$1

    CMDLINE=$(cat /proc/$PID/cmdline 2> /dev/null)
    CMDLINE=$(echo $CMDLINE | head -c 80)

    echo $CMDLINE
}
kill_by_id() {
    PID=$1
    SIGNAL=${2:-9}

    if [ "$PID" == "" ]; then
        return
    fi
    if [ ! -e /proc/$PID/cmdline ]; then
        return
    fi

    CMDLINE=$(get_command_line $PID)

    log "Killing $PID ($CMDLINE)"
    kill -$SIGNAL $PID
}

get_by_name() {
    ps | grep "$1" | grep -v grep | awk '{print $1}'
}
wait_for_name() {
    DELAY=250
    TOTAL=${2:-30000}

    while [ 1 ]; do
        PIDS=$(get_by_name $1)
        if [ "$PIDS" != "" ]; then
            return
        fi

        if [ "$TOTAL" -gt 30000 ]; then
            if [ "$3" != "" ]; then
                log "$3"
            else
                log "/!\ Timeout waiting for $1 to start"
            fi

            quit
        fi

        msleep $DELAY
        TOTAL=$(( $TOTAL - $DELAY ))
    done
}
assert_by_name() {
    PIDS=$(get_by_name $1)

    if [ "$PIDS" == "" ]; then
        log "/!\ $1 should be running but it's not"
        quit
    fi
}
kill_by_name() {
    PIDS=$(get_by_name $1)
    SIGNAL=${2:-9}

    for PID in $(echo "$PIDS"); do
        kill_by_id $PID $SIGNAL
    done
}

get_by_port() {
    XPORT=$(printf "%04X" ${*})
    INODE=$(cat /proc/net/tcp | grep 00000000:$XPORT | awk '/.*:.*:.*/{print $10;}')

    if [[ "$INODE" != "" ]]; then
        PID=$(ls -l /proc/*/fd/* 2> /dev/null | grep "socket:\[$INODE\]" | awk -F'/' '{print $3}')
        echo $PID
    fi
}
wait_for_port() {
    DELAY=250
    TOTAL=${2:-30000}

    while [ 1 ]; do
        PID=$(get_by_port $1)
        if [ "$PID" != "" ]; then
            return
        fi

        if [ "$TOTAL" -lt 0 ]; then
            if [ "$3" != "" ]; then
                log "$3"
            else
                log "/!\ Timeout waiting for port $1 to open"
            fi

            quit
        fi

        msleep $DELAY
        TOTAL=$(( $TOTAL - $DELAY ))
    done
}
assert_by_port() {
    PID=$(get_by_port $1)

    if [ "$PID" == "" ]; then
        log "/!\ $1 should be open but it's not"
        quit
    fi
}
kill_by_port() {
    PID=$(get_by_port $1)
    SIGNAL=${2:-9}

    kill_by_id $PID $SIGNAL
}

wait_for_socket() {
    DELAY=250
    TOTAL=${2:-30000}

    while [ 1 ]; do
        timeout -t 1 $RINKHALS_ROOT/bin/socat $1 $1 2> /dev/null
        if [ "$?" -gt 127 ]; then
            return
        fi

        if [ "$TOTAL" -lt 0 ]; then
            if [ "$3" != "" ]; then
                log "$3"
            else
                log "/!\ Timeout waiting for socket $1 to listen"
            fi

            quit
        fi

        msleep $DELAY
        TOTAL=$(( $TOTAL - $DELAY ))
    done
}

