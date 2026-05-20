Key creation

ssh-keygen -t ed25519 -C "rpi5"
ssh-copy-id -i ~/.ssh/id_ed25519.pub pi5@<IP_RPI>   


copy key Raspberry Pi:

scp secure-rpi-setup.sh pi5@<IP_RPI>:/home/pi5/

Raspberry Pi:

ssh pi5@<IP_RPI>
sudo chmod +x /home/pi5/secure-rpi-setup.sh
sudo /home/pi5/secure-rpi-setup.sh
