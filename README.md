# PiRTOIIDuo
New PiRTO multicart for Intellivision with JLP support, based on Raspberry Pico2 

PiRTO II DUO is the new version of my PiRTO multicart DIY yourself based now on a Raspberry Pi Pico2 for using double RAM.

This version support Intellivision bin+cfg games, including the JLP acceleration and savegames features.
It works with all games i testes since now, except for "Onion" (it's a big rom and i think it will need next pico3 ;) )

![ScreenShot](https://raw.githubusercontent.com/aotta/PiRTOIIDuo/main/Pictures/Pirto2Duo.jpeg)
![ScreenShot](https://raw.githubusercontent.com/aotta/PiRTOIIDuo/main/Pictures/shell2.jpeg)

![ScreenShot](https://raw.githubusercontent.com/aotta/PiRTOIIDuo/main/Pictures/boot2.jpeg)

![ScreenShot](https://raw.githubusercontent.com/aotta/PiRTOIIDuo/main/Pictures/bd.jpeg)
![ScreenShot](https://raw.githubusercontent.com/aotta/PiRTOIIDuo/main/Pictures/BadApple.jpg)

![ScreenShot](https://raw.githubusercontent.com/aotta/PiRTOIIDuo/main/Pictures/DOTC.jpg)
![ScreenShot](https://raw.githubusercontent.com/aotta/PiRTOIIDuo/main/Pictures/CatAttack.jpg)


Kicad project and gerbers files for the pcb are in the PCB folder, you need only a diode, a push buttons for resetting the cart if needed or want restart, and the micro SDCard holder. 
Add you pico2, and flash the firmware ".uf2" in the Pico by connecting it while pressing button on Pico and drop it in the opened windows on PC.
Use the SDCard to store "BIN" and "CFG“ files  into.

3D files for shell coming soon!

More info on AtariAge forum: [https://forums.atariage.com/](https://forums.atariage.com/topic/386798-pirto-ii-duo-powered-by-pico2-with-jlp-support/)


Even if the diode should protect your console, **DO NOT CONNECT PICO WHILE INSERTED IN A POWERED ON CONSOLE!**
You can use any schottky diode, i usually put 1n4148

## Credits
This upgrade is dedicated to Mariella, with love and gratitude for trusting me and encouraging me to never give up

