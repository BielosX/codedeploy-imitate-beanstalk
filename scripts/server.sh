#!/bin/bash

PID_FILE=/home/app/app.pid
cd /home/app || exit
source env/bin/activate
gunicorn --bind :5000 --workers 3 --threads 2 app:app & echo $! > $PID_FILE