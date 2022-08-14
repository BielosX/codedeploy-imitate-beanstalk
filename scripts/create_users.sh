#!/bin/bash

if ! id "app"; then
  adduser app --user-group
fi

if ! id "proxy"; then
  adduser proxy --user-group
  mkdir -p /home/proxy/logs
fi