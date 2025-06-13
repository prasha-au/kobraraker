. $(dirname $(realpath $0))/tools.sh

cd $RINKHALS_ROOT
mkdir -p ./logs

if [ ! -d /useremain/rinkhals/.current ]; then
    echo Rinkhals has not started
    exit 1
fi


################
log "> Restarting Anycubic apps..."

touch /useremain/rinkhals/.disable-rinkhals

cd /userdata/app/gk
./start.sh &> /dev/null

echo
log "Rinkhals stopped"
