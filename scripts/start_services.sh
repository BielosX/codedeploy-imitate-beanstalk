#!/bin/bash

systemctl enable app.service
systemctl enable nginx.service
systemctl enable fluent-bit.service

systemctl start app.service
systemctl start nginx.service
systemctl start fluent-bit.service
