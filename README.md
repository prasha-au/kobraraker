
> [!WARNING]
> **This code is very experimental and has not been tested on different products or configurations. I'm not responsible for you bricking your printer.**


## KobraRaker

Hack work to get Moonraker running on a secondary device linking to a KobraOS printer. If you stumble upon this I suggest you check out [Rinkhals](https://github.com/jbatonnet/Rinkhals) for a much more mature, tested and supported solution. This relies on a lot of Rinkhals so you will need it anyway.


This forwards out the KlipperGo unix socket and parts of the file system over SSH to a secondary device. This can be done over the existing Wifi connection or maybe even ethernet/usb from the Pi directly.
The main motivation for this is to avoid overloading the print harder causing MCU timeout issues. Additionally it makes it easier to install various services since it's a common Linux distribution.




## Setup

Raspberry pi image with user setup as printerpi and password printerpi (or you'll have to search/replace). A lot of the code here is hard coded for now and you'll have to search through files and change the printer IP address.


```bash
scp kobra.py printerpi:/home/printerpi/
scp lighttpd.conf printerpi:/home/printerpi/
scp moonraker.conf printerpi:/home/printerpi/
scp klipper-fsmount.service printerpi:/home/printerpi/
scp klipper-socket-local.service printerpi:/home/printerpi/
scp klipper-socket-forward.service printerpi:/home/printerpi/
scp moonraker.service printerpi:/home/printerpi/

```


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



# Moonraker setup
git clone https://github.com/Arksine/moonraker moonraker
cd moonraker
echo -n $(git describe --tags) > moonraker/.version

cd ..
python -m venv venv
venv/bin/pip install -r moonraker/scripts/moonraker-requirements.txt

mkdir -p /home/printerpi/printer_data

# Copy and link the lighttpd config file
sudo ln -s /home/printerpi/lighttpd.conf /etc/lighttpd/lighttpd.conf
sudo systemctl restart lighttpd


# Klipper tunnel service
sudo ln -s /home/printerpi/klipper-socket-local.service /etc/systemd/system/klipper-socket-local.service
sudo systemctl daemon-reload
sudo systemctl enable klipper-socket-local.service
sudo systemctl start klipper-socket-local.service

sudo ln -s /home/printerpi/klipper-socket-forward.service /etc/systemd/system/klipper-socket-forward.service
sudo systemctl daemon-reload
sudo systemctl enable klipper-socket-forward.service
sudo systemctl start klipper-socket-forward.service



sudo ln -s /home/printerpi/klipper-fsmount.service /etc/systemd/system/klipper-fsmount.service
sudo systemctl daemon-reload
sudo systemctl enable klipper-fsmount.service
sudo systemctl start klipper-fsmount.service


# moonraker setup
ln -s /home/printerpi/kobra.py /home/printerpi/moonraker/moonraker/components/kobra.py

mkdir -p /home/printerpi/printer_data/config
mv /home/printerpi/moonraker.conf /home/printerpi/printer_data/moonraker.conf
ln -s /home/printerpi/mounted_printer_data/config/printer_mutable.cfg /home/printerpi/printer_data/config/
ln -s /home/printerpi/mounted_printer_data/config/printer.custom.cfg /home/printerpi/printer_data/config/
ln -s /home/printerpi/mounted_printer_data/config/printer.generated.cfg /home/printerpi/printer_data/config/


sudo ln -s /home/printerpi/moonraker.service /etc/systemd/system/moonraker.service
sudo systemctl daemon-reload
sudo systemctl enable moonraker.service
sudo systemctl start moonraker.service

```



## References
- https://github.com/mkuf/prind/tree/main/docker/moonraker
- https://github.com/jbatonnet/Rinkhals/blob/master/files/4-apps/home/rinkhals/apps/40-moonraker/kobra.py
- https://github.com/jbatonnet/Rinkhals/blob/master/files/4-apps/home/rinkhals/apps/25-mainsail/lighttpd.conf

