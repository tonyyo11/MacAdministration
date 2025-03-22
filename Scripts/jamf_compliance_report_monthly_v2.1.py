#!/usr/bin/env python3
"""
###################################################################################################
# Script Name:    jamf_compliance_report_monthly_v2.py
# By:            Tony Young
# Organization:   Cloud Lake Technology, an Akima company
# Date:          March 22nd, 2025
# 
# Purpose:       Process Jamf Pro generated macOS Security Compliance Project report CSV files from
#                a specified input directory, filtering by file creation date (using the last
#                TIMEFRAME_DAYS) and by dates embedded in filenames, then combining the four most
#                recent reports into a monthly trends report.
#
###################################################################################################
#
# DESCRIPTION
#
#   This Python script scans a designated folder for CSV files containing compliance reports.
#   It first filters the files by checking their creation date (only including those from the last
#   TIMEFRAME_DAYS). Then, for each CSV, it extracts a date from the filename (expected in the 
#   format YYYY-MM-DDThh_mm_ss). The files are sorted by this embedded date, and the four most recent
#   reports are selected for further processing.
#
#   The script builds a compliance history per system (using Serial Number as the unique key), 
#   computes trend analysis (including an averages row), and creates an Excel workbook that contains:
#     1. A "Trend Analysis" sheet (with conditional formatting).
#     2. Individual sheets for each report date.
#     3. A "Compliance Chart" sheet showing a pie chart of overall compliance based on configurable
#        thresholds and colors.
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
#   2025-02-20 - Tony Young
#       v2.1 - Merged auto dependency installation, configurable variables, CSV parsing, trend analysis,
#         and enhanced pie chart generation with dynamic color thresholds.
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
    Attempts to import a module; if not found, installs it via pip.
    
    :param package: Name of the package to install.
    :param import_name: Name to import (if different from package name).
    """
    if import_name is None:
        import_name = package
    try:
        __import__(import_name)
    except ImportError:
        print(f"Package '{package}' not found. Installing...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", package])
    finally:
        globals()[import_name] = __import__(import_name)

# Dictionary of required dependencies.
dependencies = {
    "pandas": "pandas",
    "xlsxwriter": "xlsxwriter",   # For Excel formatting and image insertion.
    "numpy": "numpy",
    "matplotlib": "matplotlib",   # For generating the pie chart.
    "glob2": "glob",              # Standard glob module features.
    "re": "re"
}

for pkg, mod in dependencies.items():
    install_and_import(pkg, mod)

# -----------------------------
# Standard Library and Dependency Imports
# -----------------------------
import os
import glob
import re
from datetime import datetime, timedelta
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

# -----------------------------
# Configurable Variables
# -----------------------------
INPUT_DIR = "STIG_Reports"          # Folder containing CSV reports.
TIMEFRAME_DAYS = 30                 # Process only files created within the last 30 days.
OUTPUT_FILE_PREFIX = "STIG_Compliance_Report"  # Prefix for output Excel file and pie chart image.
OUTPUT_FILE = f"{OUTPUT_FILE_PREFIX}_{datetime.now().strftime('%Y%m%d')}.xlsx"

# Compliance thresholds for both pie chart and Excel formatting.
COMPLIANCE_THRESHOLDS = {
    "pass": (0, 0),            # 0 failures -> Pass
    "low": (1, 25),            # 1-25 failures -> Low
    "medium": (26, 50),        # 26-50 failures -> Medium
    "high": (51, float("inf")) # >50 failures -> High
}

# Colors for the pie chart.
PIE_CHART_COLORS = {
    "pass": "green",
    "low": "yellow",
    "medium": "orange",
    "high": "red"
}

# Excel conditional formatting color schemes.
EXCEL_FORMATS = {
    "pass": {'bg_color': '#C6EFCE', 'font_color': '#006100'},    # Light green for Pass
    "low": {'bg_color': '#FFEB9C', 'font_color': '#9C6500'},       # Light yellow for low failures
    "medium": {'bg_color': '#FFB266', 'font_color': '#974C00'},      # Orange for medium failures
    "high": {'bg_color': '#FFC7CE', 'font_color': '#9C0006'}         # Red for high failures
}

# -----------------------------
# Helper Functions
# -----------------------------
def get_file_creation_date(filepath):
    """
    Returns the creation date (birthtime) of the file.
    Falls back to the change time if st_birthtime is unavailable.
    
    :param filepath: Full path to the file.
    :return: datetime object representing the file creation date.
    """
    stat = os.stat(filepath)
    try:
        return datetime.fromtimestamp(stat.st_birthtime)
    except AttributeError:
        return datetime.fromtimestamp(stat.st_ctime)

def extract_date_from_filename(filename):
    """
    Extracts date from a filename in the expected format YYYY-MM-DDThh_mm_ss.
    
    :param filename: The file's name or path.
    :return: The date portion (YYYY-MM-DD) as a string, or None if not found.
    """
    match = re.search(r'(\d{4}-\d{2}-\d{2})T\d{2}_\d{2}_\d{2}', os.path.basename(filename))
    if match:
        return match.group(1)
    return None

def generate_pie_chart(df_latest):
    """
    Generates a pie chart displaying compliance status based on configurable thresholds.
    Categories are:
      - Pass: 0 failures (green)
      - Low: 1-25 failures (yellow)
      - Medium: 26-50 failures (orange)
      - High: >50 failures (red)
    
    :param df_latest: DataFrame of the most recent report.
    :return: The filename of the saved pie chart image.
    """
    # Calculate counts for each category.
    pass_count = len(df_latest[df_latest['Compliance - Failed mSCP Results Count'] == 0])
    low_count = len(df_latest[(df_latest['Compliance - Failed mSCP Results Count'] >= COMPLIANCE_THRESHOLDS["low"][0]) &
                              (df_latest['Compliance - Failed mSCP Results Count'] <= COMPLIANCE_THRESHOLDS["low"][1])])
    medium_count = len(df_latest[(df_latest['Compliance - Failed mSCP Results Count'] >= COMPLIANCE_THRESHOLDS["medium"][0]) &
                                 (df_latest['Compliance - Failed mSCP Results Count'] <= COMPLIANCE_THRESHOLDS["medium"][1])])
    high_count = len(df_latest[df_latest['Compliance - Failed mSCP Results Count'] >= COMPLIANCE_THRESHOLDS["high"][0]])
    
    labels = ['Pass (0)', 'Low (1-25)', 'Medium (26-50)', 'High (>50)']
    sizes = [pass_count, low_count, medium_count, high_count]
    colors = [PIE_CHART_COLORS["pass"], PIE_CHART_COLORS["low"],
              PIE_CHART_COLORS["medium"], PIE_CHART_COLORS["high"]]
    
    plt.figure(figsize=(6, 6))
    plt.pie(sizes, labels=labels, autopct='%1.1f%%', startangle=90, colors=colors)
    plt.title('Compliance Pass vs Fail')
    plt.axis('equal')
    
    pie_chart_file = f"{OUTPUT_FILE_PREFIX}_piechart_{datetime.now().strftime('%Y%m%d_%H%M%S')}.png"
    plt.savefig(pie_chart_file)
    plt.close()
    
    return pie_chart_file

def process_compliance_reports():
    """
    Processes CSV compliance reports from INPUT_DIR.
    
    - Scans for CSV files in INPUT_DIR.
    - Filters files to only include those with a creation date within TIMEFRAME_DAYS.
    - Extracts dates from filenames (format: YYYY-MM-DDThh_mm_ss).
    - Sorts files by the extracted date and selects the four most recent reports.
    - Reads each CSV to build a compliance history per system (keyed by Serial Number).
    - Generates a trend analysis DataFrame (including an averages row).
    - Exports the data into an Excel workbook containing:
        1. A "Trend Analysis" sheet (with conditional formatting).
        2. Individual sheets for each report date.
        3. A "Compliance Chart" sheet that embeds a pie chart (generated from the most recent report).
    
    :return: The name of the generated Excel file.
    """
    # Retrieve all CSV files from the input directory.
    all_csv_files = glob.glob(f"{INPUT_DIR}/*.csv")
    if not all_csv_files:
        raise FileNotFoundError(f"No CSV files found in {INPUT_DIR}")
    
    # Filter files based on creation date.
    cutoff_date = datetime.now() - timedelta(days=TIMEFRAME_DAYS)
    filtered_csv_files = [f for f in all_csv_files if get_file_creation_date(f) >= cutoff_date]
    
    if not filtered_csv_files:
        raise FileNotFoundError(f"No CSV files in {INPUT_DIR} were created in the last {TIMEFRAME_DAYS} days.")
    
    # Build a list of tuples: (filename, extracted_date) from filtered files.
    dated_files = []
    for file in filtered_csv_files:
        file_date = extract_date_from_filename(file)
        if file_date:
            dated_files.append((file, file_date))
    
    # Sort files by extracted date and select the four most recent.
    dated_files.sort(key=lambda x: x[1])
    dated_files = dated_files[-4:]
    
    if not dated_files:
        raise ValueError("No files with valid dates in the filename found after filtering.")
    
    # -----------------------------
    # Initialize Excel writer and workbook formatting.
    # -----------------------------
    writer = pd.ExcelWriter(OUTPUT_FILE, engine='xlsxwriter')
    workbook = writer.book

    try:
        # Define header and cell formats.
        header_format = workbook.add_format({
            'bold': True,
            'bg_color': '#366092',
            'font_color': 'white',
            'text_wrap': True,
            'valign': 'top',
            'border': 1
        })
        
        wrap_format = workbook.add_format({
            'text_wrap': True,
            'valign': 'top'
        })
        
        # Define Excel conditional formats using our configurable EXCEL_FORMATS.
        pass_format = workbook.add_format(EXCEL_FORMATS["pass"])
        low_failures = workbook.add_format(EXCEL_FORMATS["low"])
        medium_failures = workbook.add_format(EXCEL_FORMATS["medium"])
        high_failures = workbook.add_format(EXCEL_FORMATS["high"])
        
        # -----------------------------
        # Process reports and build compliance history.
        # -----------------------------
        compliance_history = {}   # History per Serial Number.
        computer_names = {}       # Computer Names keyed by Serial Number.
        
        for csv_file, file_date in dated_files:
            print(f"Processing file for date: {file_date}")
            df = pd.read_csv(csv_file)
            for _, row in df.iterrows():
                serial = row['Serial Number']
                computer = row['Computer Name']
                failed_count = row['Compliance - Failed mSCP Results Count']
                
                computer_names[serial] = computer
                if serial not in compliance_history:
                    compliance_history[serial] = {}
                compliance_history[serial][file_date] = failed_count
        
        # -----------------------------
        # Build trend analysis data.
        # -----------------------------
        trend_data = []
        dates = sorted(list(set().union(*[h.keys() for h in compliance_history.values()])))
        
        for serial, history in compliance_history.items():
            row_data = {'Serial Number': serial, 'Computer Name': computer_names.get(serial, 'N/A')}
            for date in dates:
                row_data[date] = history.get(date, np.nan)
            trend_data.append(row_data)
        
        averages = {'Serial Number': 'Average Failed Checks', 'Computer Name': ''}
        for date in dates:
            values = [h.get(date) for h in compliance_history.values() if h.get(date) is not None]
            averages[date] = np.mean(values) if values else np.nan
        trend_data.append(averages)
        
        trend_df = pd.DataFrame(trend_data)
        trend_df.to_excel(writer, sheet_name='Trend Analysis', index=False)
        trend_sheet = writer.sheets['Trend Analysis']
        
        for col_num, value in enumerate(trend_df.columns.values):
            trend_sheet.write(0, col_num, value, header_format)
        
        trend_sheet.set_column('A:A', 20)  # Serial Number
        trend_sheet.set_column('B:B', 30)  # Computer Name
        for col in range(2, len(trend_df.columns)):
            trend_sheet.set_column(col, col, 15)
            trend_sheet.conditional_format(1, col, len(trend_df)-1, col, {
                'type': 'cell',
                'criteria': 'between',
                'minimum': COMPLIANCE_THRESHOLDS["low"][0],
                'maximum': COMPLIANCE_THRESHOLDS["low"][1],
                'format': low_failures
            })
            trend_sheet.conditional_format(1, col, len(trend_df)-1, col, {
                'type': 'cell',
                'criteria': 'between',
                'minimum': COMPLIANCE_THRESHOLDS["medium"][0],
                'maximum': COMPLIANCE_THRESHOLDS["medium"][1],
                'format': medium_failures
            })
            trend_sheet.conditional_format(1, col, len(trend_df)-1, col, {
                'type': 'cell',
                'criteria': 'greater than',
                'value': COMPLIANCE_THRESHOLDS["high"][0] - 1,
                'format': high_failures
            })
        
        trend_sheet.freeze_panes(1, 2)
        
        # -----------------------------
        # Create individual sheets for each report date.
        # -----------------------------
        for csv_file, file_date in dated_files:
            df = pd.read_csv(csv_file)
            df.to_excel(writer, sheet_name=file_date, index=False)
            sheet = writer.sheets[file_date]
            
            sheet.set_column('A:A', 20)  # Computer Name
            sheet.set_column('B:B', 15)  # Serial Number
            sheet.set_column('C:C', 40)  # mSCP Version (if applicable)
            sheet.set_column('D:D', 15)  # Failed Count
            sheet.set_column('E:E', 30)  # Full Name
            sheet.set_column('F:F', 20)  # Last Inventory
            sheet.set_column('G:G', 15)  # OS Version
            sheet.set_column('H:H', 50, wrap_format)  # Failed List
            sheet.set_column('I:I', 20)  # Asset Tag
            
            for col_num, value in enumerate(df.columns.values):
                sheet.write(0, col_num, value, header_format)
            
            failed_col = df.columns.get_loc('Compliance - Failed mSCP Results Count')
            sheet.conditional_format(1, failed_col, len(df) + 1, failed_col, {
                'type': 'cell',
                'criteria': 'between',
                'minimum': COMPLIANCE_THRESHOLDS["low"][0],
                'maximum': COMPLIANCE_THRESHOLDS["low"][1],
                'format': low_failures
            })
            sheet.conditional_format(1, failed_col, len(df) + 1, failed_col, {
                'type': 'cell',
                'criteria': 'between',
                'minimum': COMPLIANCE_THRESHOLDS["medium"][0],
                'maximum': COMPLIANCE_THRESHOLDS["medium"][1],
                'format': medium_failures
            })
            sheet.conditional_format(1, failed_col, len(df) + 1, failed_col, {
                'type': 'cell',
                'criteria': 'greater than',
                'value': COMPLIANCE_THRESHOLDS["high"][0] - 1,
                'format': high_failures
            })
            
            sheet.freeze_panes(1, 0)
            sheet.autofilter(0, 0, len(df), len(df.columns) - 1)
        
        # -----------------------------
        # Generate a pie chart from the most recent report.
        # -----------------------------
        latest_csv_file, latest_date = dated_files[-1]
        df_latest = pd.read_csv(latest_csv_file)
        pie_chart_file = generate_pie_chart(df_latest)
        
        chart_sheet = workbook.add_worksheet('Compliance Chart')
        chart_sheet.insert_image('B2', pie_chart_file)
        
        writer.close()
        return OUTPUT_FILE
        
    except Exception as e:
        writer.close()
        raise e

# -----------------------------
# Main Execution Flow
# -----------------------------
if __name__ == "__main__":
    try:
        output_file = process_compliance_reports()
        print(f"\nReport generated successfully: {output_file}")
        print("\nColor coding legend (Excel & Pie Chart):")
        print(f"Pass (0 failures): {EXCEL_FORMATS['pass']['bg_color']}")
        print(f"Low (1-25 failures): {EXCEL_FORMATS['low']['bg_color']}")
        print(f"Medium (26-50 failures): {EXCEL_FORMATS['medium']['bg_color']}")
        print(f"High (>50 failures): {EXCEL_FORMATS['high']['bg_color']}")
        print("\nSheet order:")
        print("1. Trend Analysis")
        print("2. Individual date sheets (most recent to oldest)")
        print("3. Compliance Chart (pie chart)")
    except Exception as e:
        print(f"Error generating report: {str(e)}")
