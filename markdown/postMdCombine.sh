#!/bin/bash

read -p "Output filename root: " filename 
read -p "Output format: " format

pandoc -i output.md -o $filename.$format
