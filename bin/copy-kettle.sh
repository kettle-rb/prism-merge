#!/usr/bin/env bash

for item in vendor/*-merge; do
  if [ -d "$item" ]; then
    cp bin/kettle-soup-cover "$item/bin/"
  fi
done