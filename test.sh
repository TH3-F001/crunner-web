#!/bin/bash

stime=0.2
sleep 5
active
while true; do

    # Go to buy
    xdotool key z
    sleep $stime
    xdotool key Down
    sleep $stime
    
    #Buy flakes
    for i in $(seq 0 16); do
        xdotool key z
        sleep $stime
    done

    #Back to menu
    xdotool key x
    sleep $stime

    # Go to Sell
    xdotool key Down
    sleep $stime
    xdotool key z
    sleep $stime
    xdotool key Down
    sleep $stime

    # Sell Flakes
    for i in $(seq 1 14); do
        xdotool key z
        sleep $stime
    done

    #Back to Menu
    xdotool key x
    sleep $stime
done