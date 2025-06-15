. $(dirname $(realpath $0))/tools.sh

export TZ=UTC
export RINKHALS_ROOT=$(dirname $(realpath $0))
export RINKHALS_VERSION=$(cat $RINKHALS_ROOT/.version)

# Check Kobra model and firmware version
check_compatibility

quit() {
    echo
    log "/!\\ Startup failed, stopping Rinkhals..."

    beep 500
    msleep 500
    beep 500

    ./stop.sh
    touch /useremain/rinkhals/.disable-rinkhals

    exit 1
}

cd $RINKHALS_ROOT
rm -rf /useremain/rinkhals/.current 2> /dev/null
ln -s $RINKHALS_ROOT /useremain/rinkhals/.current

mkdir -p ./logs

if [ ! -f /tmp/rinkhals-bootid ]; then
    echo $RANDOM > /tmp/rinkhals-bootid
fi
BOOT_ID=$(cat /tmp/rinkhals-bootid)

log
log "[$BOOT_ID] Starting Rinkhals..."

log " --------------------------------------------------"
log "| Kobra model: $KOBRA_MODEL ($KOBRA_MODEL_CODE)"
log "| Kobra firmware: $KOBRA_VERSION"
log "| Rinkhals version: $RINKHALS_VERSION"
log "| Rinkhals root: $RINKHALS_ROOT"
log "| Rinkhals home: $RINKHALS_HOME"
log " --------------------------------------------------"
echo

touch /useremain/rinkhals/.disable-rinkhals


VERIFIED_FIRMWARE=$(is_verified_firmware)
if [ "$VERIFIED_FIRMWARE" != "1" ] && [ ! -f /mnt/udisk/.enable-rinkhals ] && [ ! -f /useremain/rinkhals/.enable-rinkhals ]; then
    log "Unsupported firmware version, use .enable-rinkhals file to force startup"
    exit 1
fi


################
log "> Stopping Anycubic apps..."

kill_by_name K3SysUi
kill_by_name gkcam
kill_by_name gkapi
kill_by_name gklib 15 # SIGTERM to be softer ok gklib


#################
log "> Fixing permissions..."
chmod +x $RINKHALS_ROOT/bin/dropbear 2> /dev/null
chmod +x $RINKHALS_ROOT/bin/ld-uClibc 2> /dev/null
chmod +x $RINKHALS_ROOT/bin/sftp-server 2> /dev/null
chmod +x $RINKHALS_ROOT/ntpclient.sh 2> /dev/null


################
log "> Trimming old logs..."

for LOG_FILE in $RINKHALS_ROOT/logs/*.log ; do
    tail -c 1048576 $LOG_FILE > $LOG_FILE.tmp
    cat $LOG_FILE.tmp > $LOG_FILE
    rm $LOG_FILE.tmp
done



################
log "> Preparing mounts..."

mkdir -p $RINKHALS_HOME/printer_data
mkdir -p /userdata/app/gk/printer_data
umount -l /userdata/app/gk/printer_data 2> /dev/null
mount --bind $RINKHALS_HOME/printer_data /userdata/app/gk/printer_data

mkdir -p /userdata/app/gk/printer_data/gcodes
umount -l /userdata/app/gk/printer_data/gcodes 2> /dev/null
mount --bind /useremain/app/gk/gcodes /userdata/app/gk/printer_data/gcodes

if [ -f /mnt/udisk/printer.generated.cfg ]; then
    cp /userdata/app/gk/printer_data/config/printer.generated.cfg /userdata/app/gk/printer_data/config/printer.generated.cfg.bak
    rm /userdata/app/gk/printer_data/config/printer.generated.cfg
    cp /mnt/udisk/printer.generated.cfg /userdata/app/gk/printer_data/config/printer.generated.cfg
fi


################
log "> Restarting Anycubic apps..."

cd /userdata/app/gk/

export USE_MUTABLE_CONFIG=1
export LD_LIBRARY_PATH=/userdata/app/gk:$LD_LIBRARY_PATH

./gklib -a /tmp/unix_uds1 /userdata/app/gk/printer_data/config/printer.generated.cfg &> $RINKHALS_ROOT/logs/gklib.log &
./gkapi &> $RINKHALS_ROOT/logs/gkapi.log &
./K3SysUi &> $RINKHALS_ROOT/logs/gkui.log &

wait_for_socket /tmp/unix_uds1 30000 "/!\ Timeout waiting for gklib to start"



cd $RINKHALS_ROOT/bin

################
log "> Forwarding Klipper socket..."
$RINKHALS_ROOT/bin/socat TCP-LISTEN:7126,fork,reuseaddr UNIX-CONNECT:/tmp/unix_uds1 2>&1 &


################
log "> Starting SSH..."

if [ "$(get_by_port 22)" != "" ]; then
    log "/!\ SSH is already running"
else
    # Note this is require because the binaries have been built with /tmp/ssh as the path prefix since we just copied the ssh tools.
    # See build\swu-tools\ssh\build-swu.sh in the Rinkhals repository.
    SSH_TOOL_PATH="/tmp/ssh"

    log "Hacking SSH bins to $SSH_TOOL_PATH"
    mkdir -p $SSH_TOOL_PATH
    cp $RINKHALS_ROOT/bin/* /tmp/ssh/

    LD_LIBRARY_PATH=$SSH_TOOL_PATH $SSH_TOOL_PATH/dropbear -F -E -a -p 22 -P $RINKHALS_ROOT/dropbear.pid -r $SSH_TOOL_PATH/dropbear_rsa_host_key >> $RINKHALS_ROOT/logs/dropbear.log 2>&1 &

    wait_for_port 22 5000 "/!\ SSH did not start properly"
fi


###############
# log "> Starting ethernet..."
# insmod $RINKHALS_ROOT/bin/usbnet.ko
# insmod $RINKHALS_ROOT/bin/asix.ko
# ifconfig eth1 169.254.5.1 up


cd $RINKHALS_ROOT


################
log "> Cleaning up..."

rm /useremain/rinkhals/.disable-rinkhals
rm /useremain/rinkhals/.reboot-marker 2> /dev/null

echo
log "Rinkhals started"
