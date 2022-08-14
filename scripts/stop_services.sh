#!/bin/bash

systemctl stop nginx.service
systemctl stop app.service
systemctl stop fluent-bit.service
