На ноуте (один раз) — создать ключ, если ещё не:

ssh-keygen -t ed25519 -C "rpi5"
ssh-copy-id -i ~/.ssh/id_ed25519.pub pi5@<IP_RPI>   # или другой юзер


Скопировать скрипт на Raspberry Pi:

scp secure-rpi-setup.sh pi5@<IP_RPI>:/home/pi5/


На Raspberry Pi:

ssh pi5@<IP_RPI>
sudo chmod +x /home/pi5/secure-rpi-setup.sh
sudo /home/pi5/secure-rpi-setup.sh
