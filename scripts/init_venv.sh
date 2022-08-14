#!/bin/bash

cd /home/app || exit
rm -rf env
virtualenv env
source env/bin/activate
pip install -r requirements.txt
chown -R app:app env