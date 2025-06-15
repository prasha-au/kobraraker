
> [!WARNING]
> **This code is very experimental and has not been tested on different products or configurations. I'm not responsible for you bricking your printer.**


## KobraRaker

Hack work to get Moonraker running on a secondary device linking to a KobraOS printer. If you stumble upon this I suggest you check out [Rinkhals](https://github.com/jbatonnet/Rinkhals) for a much more mature, tested and supported solution. This relies on a lot of Rinkhals so you will need it anyway.


This forwards out the KlipperGo unix socket and parts of the file system over SSH to a secondary device. This can be done over the existing Wifi connection or maybe even ethernet/usb from the Pi directly.
The main motivation for this is to avoid overloading the printer hardware causing MCU timeout issues. Additionally it makes it easier to install various services since it's a common Linux distribution.




## Setup

A lot of the code here is hard coded for now so you'll have to go change the default user and home path.

## General setup

```bash

sudo apt-get update

# these were just copied from the Dockerfile - unsure why some are necessary
sudo apt-get install -y \
      git \
      python3 \
      lighttpd \
      sshfs \
      sshpass


# Clone this project into $HOME
git clone https://github.com/prasha-au/kobraraker.git

# Copy config files - they won't be versioned from here on out
mkdir -p $HOME/printer_data/config $HOME/printer_data/run
cp $HOME/kobraraker/configs/* $HOME/printer_data/config/

# Link some config files out
ln -s $HOME/printer_data/config/sshconfig $HOME/.ssh/config
sudo rm /etc/lighttpd/lighttpd.conf
sudo ln -s $HOME/printer_data/config/lighttpd.conf /etc/lighttpd/lighttpd.conf


# Moonraker setup
git clone https://github.com/Arksine/moonraker moonraker
cd moonraker
echo -n $(git describe --tags) > moonraker/.version
./scripts/install-moonraker.sh

# Moonraker overrides
cp $HOME/kobraraker/moonraker/file_manager.py $HOME/moonraker/moonraker/components/file_manager/file_manager.py
cp $HOME/kobraraker/moonraker/kobra.py $HOME/moonraker/moonraker/components/kobra.py

rm /etc/systemd/system/moonraker.service;

# Link and enable services
sudo systemctl enable --now $HOME/kobraraker/services/klipper-sshcontrol.service
sudo systemctl enable --now $HOME/kobraraker/services/klipper-socket-local.service
sudo systemctl enable --now $HOME/kobraraker/services/klipper-fsmount.service
sudo systemctl enable --now $HOME/kobraraker/services/moonraker.service


# Link in printer config files and logs
ln -s $HOME/mounted_printer_data/config/printer_mutable.cfg $HOME/printer_data/config/
ln -s $HOME/mounted_printer_data/config/printer.custom.cfg $HOME/printer_data/config/
ln -s $HOME/mounted_printer_data/config/printer.generated.cfg $HOME/printer_data/config/
ln -s $HOME/mounted_logs $HOME/printer_data/logs/mounted_logs

# Either reboot or start the services manually
sudo reboot
```



## Printer Setup
The `./rinkhals` directory can be copied to the printer under `/useremain/rinkhals/somefoldername` and run as a version by changing `.version`.
This should still offer some of the startup protections of Rinkhals but does away with most of the binary overlays. Configurations are in an overlay so you can `.disable-rinkhals` to go back to a default printer setup.

The default SSH binaries from the Rinkhals project's ssh tools are used and copied to the `/tmp/ssh` folder due to hard coded paths in the binary.

The above should get you:
- An SSH server on port 22 with SFTP support
- The Klipper unix socket forwarded to `localhost:7126`


## Direct ethernet setup
This requires setting up ethernet drivers on the printer.
```
sudo nmcli con add con-name 'printerconnect' ifname eth0 type ethernet ip4 169.254.5.2/16 ipv4.method 'manual' connection.autoconnect yes
```




## References
- https://github.com/mkuf/prind/tree/main/docker/moonraker
- https://github.com/jbatonnet/Rinkhals/blob/master/files/4-apps/home/rinkhals/apps/40-moonraker/kobra.py
- https://github.com/jbatonnet/Rinkhals/blob/master/files/4-apps/home/rinkhals/apps/25-mainsail/lighttpd.conf

