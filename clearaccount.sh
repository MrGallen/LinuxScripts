#!/bin/bash
USER=$1
deluser --remove-home --remove-all-files "$USER"