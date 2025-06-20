
RINKHALS_ROOT=$(dirname $(realpath $0))
ETHERNET_ADAPTER_ID="0b95:772b"

watch_for_adapter()
{
  local last_value=-1
  while true; do
    lsusb | grep "$ETHERNET_ADAPTER_ID" > /dev/null
    local current_value=$?
    if [ "$current_value" -ne "$last_value" ]; then
      echo "Ethernet adapter status changed: $current_value"
      if [ "$current_value" -eq 0 ]; then
        echo "Bringing up ethernet on 169.254.5.1"
        ifconfig eth1 169.254.5.1 up
        if [ $? -ne 0 ]; then
          echo "Failed to start ethernet, retrying..."
          continue
        else
          echo "Ethernet started successfully."
        fi
      fi
      last_value=$current_value
      sleep 10
    fi
    sleep 5
  done
}

echo "Inserting ethernet adapter kernel modules..."
insmod $RINKHALS_ROOT/bin/usbnet.ko
insmod $RINKHALS_ROOT/bin/asix.ko

echo "Watching for ethernet adapter to set IP..."
watch_for_adapter
