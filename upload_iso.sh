#!/usr/bin/expect -f
spawn scp work/Amax-Live-Tool-0.0.1.iso root@192.168.124.16:/home/os 
expect "assword:"
send "linux123\r"
interact
