#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

PDF_URL="https://www.examinations.ie/docs/viewer.php?q=e5c7ee46cecf19bc20023e32f0664b6b6a152c15" 


# 2b. PREPARE EXAM RESOURCES
echo ">>> Downloading Exam Resources..."
echo "The URL is: $PDF_URL"
mkdir -p /opt/sec_exam_resources
wget -q -O /opt/sec_exam_resources/Python_Reference.pdf "$PDF_URL" || echo "Warning: PDF Download failed. Check URL."
chmod 644 /opt/sec_exam_resources/Python_Reference.pdf

  # D. SELF DESTRUCT (Security)
echo ">>> CONFIGURATION COMPLETE."
echo ">>> Deleting this script file..."
rm -- "$0"
echo ">>> Script deleted. Please Reboot."
