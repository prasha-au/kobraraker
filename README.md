
> [!WARNING]
> **This code is very experimental and has not been tested on different products or configurations. I'm not responsible for you bricking your printer.**


## KobraRaker

Hack work to get Moonraker running on a secondary device linking to a KobraOS printer. If you stumble upon this I suggest you check out [Rinkhals](https://github.com/jbatonnet/Rinkhals) for a much more mature, tested and supported solution. This relies on a lot of Rinkhals so you will need it anyway.


This forwards out the KlipperGo unix socket and parts of the file system over SSH to a secondary device. This can be done over the existing Wifi connection or maybe even ethernet/usb from the Pi directly.
The main motivation for this is to avoid overloading the print harder causing MCU timeout issues. Additionally it makes it easier to install various services since it's a common Linux distribution.




## Setup

Create a Raspberry Pi image with user setup as printerpi and password printerpi. A lot of the code here is hard coded for now and you'll have to search through files and change things if not.

```bash

sudo apt-get update

# these were just copied from the Dockerfile - unsure why some are necessary
sudo apt-get install -y \
      git \
      python3 \
      python3-pip \
      libopenjp2-7 \
      python3-libgpiod \
      curl \
      libcurl4 \
      libssl3 \
      liblmdb0 \
      libsodium23 \
      libjpeg62-turbo \
      libtiff6 \
      libxcb1 \
      zlib1g \
      iproute2 \
      systemd \
      sudo \
      git \
      jq \
      socat \
      wget \
      unzip \
      lighttpd \
      sshfs \
      sshpass


# Clone this project into $HOME
git clone https://github.com/prasha-au/kobraraker.git

# Copy config files - they won't be versioned from here on out
mkdir -p $HOME/printer_data/config $HOME/printer_data/run
cp $HOME/kobraraker/configs/* $HOME/printer_data/config/

# Link some config files out
ln -s $HOME/kobraraker/printer_data/config/sshconfig $HOME/.ssh/config
ln -s $HOME/kobraraker/printer_data/config/lighttpd.conf /etc/lighttpd/lighttpd.conf


# Moonraker setup
git clone https://github.com/Arksine/moonraker moonraker
cd moonraker
echo -n $(git describe --tags) > moonraker/.version

cd ..
python -m venv venv
venv/bin/pip install -r moonraker/scripts/moonraker-requirements.txt

# Moonraker overrides
cp $HOME/kobraraker/moonraker/file_manager.py $HOME/moonraker/moonraker/components/file_manager/file_manager.py
cp $HOME/kobraraker/moonraker/kobra.py $HOME/moonraker/moonraker/components/kobra.py


# Link and enable services
sudo systemctl enable $HOME/kobraraker/services/printer-sshcontrol.service
sudo systemctl enable $HOME/kobraraker/services/klipper-socket-local.service
sudo systemctl enable $HOME/kobraraker/services/klipper-socket-forward.service
sudo systemctl enable $HOME/kobraraker/services/klipper-fsmount.service
sudo systemctl enable $HOME/kobraraker/services/moonraker.service


# Link in printer config files
ln -s /home/printerpi/mounted_printer_data/config/printer_mutable.cfg /home/printerpi/printer_data/config/
ln -s /home/printerpi/mounted_printer_data/config/printer.custom.cfg /home/printerpi/printer_data/config/
ln -s /home/printerpi/mounted_printer_data/config/printer.generated.cfg /home/printerpi/printer_data/config/

# Either reboot or start the services manually
sudo reboot
```


## References
- https://github.com/mkuf/prind/tree/main/docker/moonraker
- https://github.com/jbatonnet/Rinkhals/blob/master/files/4-apps/home/rinkhals/apps/40-moonraker/kobra.py
- https://github.com/jbatonnet/Rinkhals/blob/master/files/4-apps/home/rinkhals/apps/25-mainsail/lighttpd.conf

