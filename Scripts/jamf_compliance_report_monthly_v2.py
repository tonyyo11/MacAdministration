#!/usr/bin/env python3
"""
###################################################################################################
# Script Name:    jamf_compliance_report_monthly_v2.py
# By:            Tony Young
# Organization:   Cloud Lake Technology, an Akima company
# Date:          March 22nd, 2025
# 
# Purpose:       Process Jamf Pro compliance reports, generate a trends report with a pie chart,
#                and export the data to an Excel workbook.
#
###################################################################################################
#
# DESCRIPTION
#
#   This Python script gathers compliance report files from a specified folder, filters them by
#   their creation date, extracts relevant compliance data, generates a pie chart to display the
#   percentage of systems passing versus failing compliance, and embeds the chart along with the
#   data into an Excel file. The script also auto-installs any missing Python dependencies.
#
###################################################################################################
#
# CHANGELOG
#
#   2025-02-20 - Tony Young
#       v.1 - Initial script creation
#   2025-03-20 - Tony Young
#       v.2 - Removed specific filename dependencies. Searches based on file creation date, no need to use PowerAutomate to Adjust Files. 
#             Set Configurable Variables; Input Directory, Timeframe Days, Output File Prefix. Attempts to install python dependencies.
#             Attempt to create Pie-chart
#
###################################################################################################
#
# DISCLAIMER
#
#   This script is provided "AS IS" and without warranty of any kind. The author and organization 
#   make no warranties, express or implied, that this script is free of error, or is consistent 
#   with any particular standard of merchantability, or that it will meet your requirements for 
#   any particular application. It should not be relied on for solving a problem whose incorrect 
#   solution could result in injury to person or property. If you do use it in such a manner, 
#   it is at your own risk. The author and organization disclaim all liability for direct, indirect, 
#   or consequential damages resulting from your use of this script.
###################################################################################################
"""

import subprocess
import sys

# -----------------------------
# Automatic Dependency Installation
# -----------------------------
def install_and_import(package, import_name=None):
    """
    Attempts to import a module, and if not found, installs it using pip.

    :param package: Name of the package to install (as recognized by pip).
    :param import_name: Name of the module to import (if different from package name).
    """
    if import_name is None:
        import_name = package
    try:
        __import__(import_name)
    except ImportError:
        print(f"Package '{package}' not found. Installing...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", package])
    finally:
        # Make the imported module available globally
        globals()[import_name] = __import__(import_name)

# Dictionary of required dependencies:
# Key: pip package name, Value: module name used in code (if different)
dependencies = {
    "pandas": "pandas",
    "matplotlib": "matplotlib",
    "xlsxwriter": "xlsxwriter",  # This is used for image insertion in the Excel export.
}

# Check and install each dependency if necessary.
for pkg, mod in dependencies.items():
    install_and_import(pkg, mod)

# -----------------------------
# Standard Library and Dependency Imports
# -----------------------------
import os
from datetime import datetime, timedelta
import pandas as pd
import matplotlib.pyplot as plt

# -----------------------------
# Configurable Variables
# -----------------------------
# INPUT_DIR: Full path to the folder containing stored compliance report files.
INPUT_DIR = '/path/to/your/reports_folder'

# TIMEFRAME_DAYS: Number of days to look back from today for filtering files.
# Adjust this value to change the time window (can also be adjusted to use weeks).
TIMEFRAME_DAYS = 30

# OUTPUT_FILE_PREFIX: Configurable prefix for the generated Excel report file.
OUTPUT_FILE_PREFIX = 'mSCP_report'

# OUTPUT_FILE: Excel file name generated using the specified prefix and current date.
OUTPUT_FILE = f"{OUTPUT_FILE_PREFIX}_{datetime.now().strftime('%Y%m%d')}.xlsx"

# PIE_CHART_IMAGE: File name for the generated pie chart image.
# Includes both date and time to ensure uniqueness (format: YYYYMMDD_HHMMSS).
PIE_CHART_IMAGE = f"{OUTPUT_FILE_PREFIX}_piechart_{datetime.now().strftime('%Y%m%d_%H%M%S')}.png"

# -----------------------------
# Helper Functions
# -----------------------------
def get_file_creation_date(filepath):
    """
    Retrieves the file creation date (birthtime) on macOS.
    Falls back to the file change time if st_birthtime is not available.

    :param filepath: Full path to the file.
    :return: datetime object representing the file's creation date.
    """
    stat = os.stat(filepath)
    try:
        # On macOS, st_birthtime is typically available.
        return datetime.fromtimestamp(stat.st_birthtime)
    except AttributeError:
        # Fallback for systems where st_birthtime is not available.
        return datetime.fromtimestamp(stat.st_ctime)

def gather_report_files(directory, days_back):
    """
    Scans the specified directory for files created within the last 'days_back' days.

    :param directory: Full path to the folder containing report files.
    :param days_back: Number of days to look back from the current date.
    :return: List of file paths that meet the creation date criteria.
    """
    cutoff_date = datetime.now() - timedelta(days=days_back)
    report_files = []
    # Iterate over each entry in the directory
    for entry in os.scandir(directory):
        if entry.is_file():
            # Get the file creation date
            file_creation_date = get_file_creation_date(entry.path)
            # If the file was created after the cutoff date, add it to the list
            if file_creation_date >= cutoff_date:
                report_files.append(entry.path)
    return report_files

def process_reports(file_list):
    """
    Processes a list of report files to extract compliance data.

    The sample parsing logic assumes that each file is a text file where each line is formatted as:
    "computer_name, compliance_status"
    Adjust this logic based on your actual report file format.

    :param file_list: List of file paths to be processed.
    :return: A pandas DataFrame containing the extracted data.
    """
    records = []
    for filepath in file_list:
        with open(filepath, 'r') as f:
            # Read file content and split into individual lines
            data = f.read().splitlines()
            for line in data:
                try:
                    # Expecting a comma-separated format
                    computer, status = line.split(',')
                    records.append({
                        'computer_name': computer.strip(),
                        'compliance_status': status.strip().lower(),
                        'report_file': os.path.basename(filepath),
                        'file_date': get_file_creation_date(filepath)
                    })
                except ValueError:
                    # Skip lines that do not match the expected format
                    continue
    # Convert list of records into a pandas DataFrame for further processing
    return pd.DataFrame(records)

def generate_trends_report(df):
    """
    Generates a trends report by creating a pie chart that shows the percentage of systems passing and failing compliance.
    
    - 'Pass' systems are represented in green.
    - 'Fail' systems are represented in red.
    
    The generated pie chart is saved as an image file with a timestamp in its file name.
    
    :param df: pandas DataFrame containing compliance data.
    """
    # Calculate counts for each compliance status
    status_counts = df['compliance_status'].value_counts()
    passed = status_counts.get('pass', 0)
    failed = status_counts.get('fail', 0)
    
    labels = []
    sizes = []
    colors = []
    
    # Append pass data if available
    if passed > 0:
        labels.append('Pass')
        sizes.append(passed)
        colors.append('green')  # Green indicates systems passing compliance
    
    # Append fail data if available
    if failed > 0:
        labels.append('Fail')
        sizes.append(failed)
        colors.append('red')    # Red indicates systems failing compliance
    
    # Create and configure the pie chart
    plt.figure(figsize=(6, 6))
    plt.pie(sizes, labels=labels, autopct='%1.1f%%', startangle=90, colors=colors)
    plt.title('Compliance Status Trend')
    plt.axis('equal')  # Ensure the pie chart is circular
    plt.savefig(PIE_CHART_IMAGE)
    plt.close()

def export_to_excel(df):
    """
    Exports the compliance data and trends report (including the pie chart) into an Excel workbook.

    The workbook contains two sheets:
      1. 'Compliance Data' - contains the processed compliance data.
      2. 'Trends Report' - contains a summary and the inserted pie chart image.
    
    :param df: pandas DataFrame containing compliance data.
    """
    # Create an Excel writer object using XlsxWriter as the engine
    writer = pd.ExcelWriter(OUTPUT_FILE, engine='xlsxwriter')
    
    # Write the main compliance data to the "Compliance Data" worksheet
    df.to_excel(writer, sheet_name='Compliance Data', index=False)
    
    # Access the workbook and add a new worksheet for the trends report
    workbook  = writer.book
    trends_sheet = workbook.add_worksheet('Trends Report')
    
    # Write summary information into the Trends Report worksheet
    trends_sheet.write('A1', 'Compliance Summary')
    trends_sheet.write('A2', 'Pass')
    trends_sheet.write('B2', int(df['compliance_status'].str.count('pass').sum()))
    trends_sheet.write('A3', 'Fail')
    trends_sheet.write('B3', int(df['compliance_status'].str.count('fail').sum()))
    
    # Insert the pie chart image into the Trends Report worksheet at cell D2
    trends_sheet.insert_image('D2', PIE_CHART_IMAGE)
    
    # Save and close the Excel file
    writer.close()

# -----------------------------
# Main Execution Flow
# -----------------------------
def main():
    """
    Main function that orchestrates the file gathering, data processing,
    trends report generation, and Excel export.
    """
    # Gather report files based on the specified creation date range
    report_files = gather_report_files(INPUT_DIR, TIMEFRAME_DAYS)
    if not report_files:
        print("No report files found in the specified date range.")
        return

    # Process the gathered report files to extract compliance data
    df = process_reports(report_files)
    
    if df.empty:
        print("No valid data was extracted from the report files.")
        return

    # Generate the trends report with a pie chart image
    generate_trends_report(df)
    
    # Export the data and trends report to an Excel workbook
    export_to_excel(df)
    
    print(f"Excel report generated: {OUTPUT_FILE}")
    print(f"Pie chart saved as: {PIE_CHART_IMAGE}")

if __name__ == "__main__":
    main()
