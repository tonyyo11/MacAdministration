#!/usr/bin/env python3
"""
###################################################################################################
# Script Name:   jamf_compliance_report_monthly_v2.1.py
# By:            Tony Young
# Organization:  Cloud Lake Technology, an Akima company
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
#   It filters files by creation date (only including those from the last TIMEFRAME_DAYS).
#   Then it uses file metadata (rather than embedded dates in filenames) to sort and select the
#   most recent reports.
#
#   The script builds a compliance history per system (using Serial Number as the unique key), 
#   computes trend analysis (including an averages row), and creates an Excel workbook that contains:
#     1. A "Trend Analysis" sheet (with conditional formatting).
#     2. Individual sheets for each report date.
#     3. A "Compliance Chart" sheet that embeds a donut chart of overall compliance based on configurable
#        thresholds and colors.
#
###################################################################################################
#
# CHANGELOG
#
#   2025-02-20 - Tony Young
#       v.1 - Initial script creation
#   2025-03-20 - Tony Young
#       v.2 - Removed specific filename dependencies; searches based on file creation date.
#             Configurable variables added; Input Directory, Timeframe Days, Output File Prefix.
#             Initial attempt at creating a pie chart.
#   2025-03-22 - Tony Young
#       v2.1 - Merged auto dependency installation, configurable variables, CSV parsing, trend analysis,
#              and enhanced donut chart generation with dynamic color thresholds and a new color palette.
#
###################################################################################################
#
# DISCLAIMER
#
#   This script is provided "AS IS" and without warranty of any kind. The author and organization 
#   make no warranties, express or implied, that this script is free of error, or is consistent 
#   with any particular standard of merchantability, or that it will meet your requirements for 
#   any particular application. Use it at your own risk.
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
    "matplotlib": "matplotlib",   # For generating the chart.
    "glob2": "glob",              # Standard glob module features.
    "re": "re",
    "textwrap": "textwrap"
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
import matplotlib.gridspec as gridspec
import textwrap

# -----------------------------
# Configurable Variables
# -----------------------------
INPUT_DIR = "/path/to/directory"  # Path to folder containing CSV reports.
TIMEFRAME_DAYS = 30                           # Only process files created within the last 30 days.
OUTPUT_FILE_PREFIX = "mSCP_Compliance_Report" # Prefix for the output Excel file and chart image.
OUTPUT_FILE = f"{OUTPUT_FILE_PREFIX}_{datetime.now().strftime('%Y%m%d')}.xlsx"

# Configurable compliance thresholds.
# Format: category : (min_value, max_value). For "pass", both min and max are 0.
COMPLIANCE_THRESHOLDS = {
    "pass": (0, 0),            # 0 failures => Pass
    "low": (1, 25),            # 1-25 failures => Low
    "medium": (26, 50),        # 26-50 failures => Medium
    "high": (51, float("inf")) # >50 failures => High
}

# New color-blind friendly palette for donut chart.
PIE_CHART_COLORS = {
    "pass": "#0072B2",    # Blue-ish
    "low": "#009E73",     # Green-ish
    "medium": "#FFB347",  # Yellow/Orange-ish
    "high": "#D55E00"     # Red-ish
}

# New Excel conditional formatting based on the updated palette.
EXCEL_FORMATS = {
    "pass": {'bg_color': '#B3D9FF', 'font_color': '#003366'},   # Light blue background, dark blue text.
    "low": {'bg_color': '#BFF0D0', 'font_color': '#006B4F'},      # Light green background, dark green text.
    "medium": {'bg_color': '#FFE5B4', 'font_color': '#B35900'},     # Light orange background, dark orange text.
    "high": {'bg_color': '#FFD6C5', 'font_color': '#A63300'}        # Light red background, dark red text.
}

# -----------------------------
# Updated Helper Functions
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

def get_date_string_from_file(filepath):
    """
    Converts the file's creation date to a standardized string (YYYY-MM-DD).
    
    :param filepath: Full path to the file.
    :return: A date string in the format "YYYY-MM-DD".
    """
    creation_date = get_file_creation_date(filepath)
    return creation_date.strftime("%Y-%m-%d")

def generate_donut_chart(df_latest):
    """
    Generates a donut chart at the top, with two columns below:
      - Left column: Legend
      - Right column: Title (with wrapping)

    The donut chart uses a rectangular layout (via GridSpec). Slices with zero counts are omitted.
    Numeric labels (percent + count) are placed outside each slice.
    """
    # Calculate counts for each category.
    pass_count = len(df_latest[df_latest['Compliance - Failed mSCP Results Count'] == 0])
    low_count = len(df_latest[
        (df_latest['Compliance - Failed mSCP Results Count'] >= COMPLIANCE_THRESHOLDS["low"][0]) &
        (df_latest['Compliance - Failed mSCP Results Count'] <= COMPLIANCE_THRESHOLDS["low"][1])
    ])
    medium_count = len(df_latest[
        (df_latest['Compliance - Failed mSCP Results Count'] >= COMPLIANCE_THRESHOLDS["medium"][0]) &
        (df_latest['Compliance - Failed mSCP Results Count'] <= COMPLIANCE_THRESHOLDS["medium"][1])
    ])
    high_count = len(df_latest[
        df_latest['Compliance - Failed mSCP Results Count'] >= COMPLIANCE_THRESHOLDS["high"][0]
    ])

    all_labels = ["Pass (0 Failures)", "Low (1-25 Failures)",
                  "Medium (26-50 Failures)", "High (>50 Failures)"]
    all_counts = [pass_count, low_count, medium_count, high_count]
    all_colors = [
        PIE_CHART_COLORS["pass"],
        PIE_CHART_COLORS["low"],
        PIE_CHART_COLORS["medium"],
        PIE_CHART_COLORS["high"]
    ]

    # Filter out categories with zero counts.
    labels = []
    sizes = []
    colors = []
    for label, count, color in zip(all_labels, all_counts, all_colors):
        if count > 0:
            labels.append(label)
            sizes.append(count)
            colors.append(color)

    if not sizes:
        print("No data to display in chart.")
        return None

    def autopct_format(values):
        def my_format(pct):
            total = sum(values)
            count = int(round(pct * total / 100.0))
            return "{:.1f}%\n({} Systems)".format(pct, count)
        return my_format

    # Create a figure with GridSpec:
    fig = plt.figure(figsize=(12, 8))
    gs = gridspec.GridSpec(2, 2, height_ratios=[0.7, 0.3])
    ax_chart = fig.add_subplot(gs[0, :])
    ax_legend = fig.add_subplot(gs[1, 0])
    ax_title = fig.add_subplot(gs[1, 1])

    # Create the donut chart
    wedges, _, autotexts = ax_chart.pie(
        sizes,
        labels=None,          # Hide slice labels (legend instead)
        autopct=autopct_format(sizes),
        startangle=90,
        pctdistance=1.35,
        radius=0.7,
        colors=colors
    )
    for t in autotexts:
        t.set_fontsize(14)

    # Donut hole
    centre_circle = plt.Circle((0, 0), 0.45, fc='white')
    ax_chart.add_artist(centre_circle)
    ax_chart.axis('equal')

    # Create an axis for the legend (bottom-left)
    ax_legend.axis('off')
    legend = ax_legend.legend(
        wedges, labels,
        title="Compliance Categories",
        loc="center",
        fontsize=14,
        title_fontsize=16
    )

    # Create an axis for the title (bottom-right)
    ax_title.axis('off')
    chart_title = f"{OUTPUT_FILE_PREFIX} Compliance Chart"
    wrapped_title = textwrap.fill(chart_title, width=30)
    ax_title.text(
        0.5, 0.5, wrapped_title,
        ha='center', va='center',
        fontsize=18
    )

    # Adjust spacing around the figure
    fig.subplots_adjust(
        left=0.05,
        right=0.95,
        top=0.95,
        bottom=0.05,
        hspace=0.2,
        wspace=0.2
    )

    # Save the figure
    donut_chart_file = f"{OUTPUT_FILE_PREFIX}_donut_{datetime.now().strftime('%Y%m%d_%H%M%S')}.png"
    plt.savefig(donut_chart_file, bbox_inches="tight")
    plt.close()

    return donut_chart_file

def process_compliance_reports():
    """
    Processes CSV compliance reports from INPUT_DIR.
    
    - Scans for CSV files in INPUT_DIR.
    - Filters files to only include those with a creation date within TIMEFRAME_DAYS.
    - Uses each file's creation date (via metadata) as the report date.
    - Sorts files by creation date and selects the most recent reports.
    - Reads each CSV to build a compliance history per system (keyed by Serial Number).
    - Generates a trend analysis DataFrame (including an averages row).
    - Exports the data into an Excel workbook containing:
        1. A "Trend Analysis" sheet (with conditional formatting).
        2. Individual sheets for each report date.
        3. A "Compliance Chart" sheet that embeds a donut chart (generated from the most recent report).
    """
    all_csv_files = glob.glob(f"{INPUT_DIR}/*.csv")
    if not all_csv_files:
        raise FileNotFoundError(f"No CSV files found in {INPUT_DIR}")
    
    cutoff_date = datetime.now() - timedelta(days=TIMEFRAME_DAYS)
    filtered_csv_files = [f for f in all_csv_files if get_file_creation_date(f) >= cutoff_date]
    
    if not filtered_csv_files:
        raise FileNotFoundError(f"No CSV files in {INPUT_DIR} were created in the last {TIMEFRAME_DAYS} days.")
    
    dated_files = []
    for file in filtered_csv_files:
        file_date_str = get_date_string_from_file(file)
        dated_files.append((file, file_date_str))
    
    dated_files.sort(key=lambda x: x[1])
    dated_files = dated_files[-4:]
    
    if not dated_files:
        raise ValueError("No files with valid creation dates found after filtering.")
    
    writer = pd.ExcelWriter(OUTPUT_FILE, engine='xlsxwriter')
    workbook = writer.book

    try:
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
        pass_format = workbook.add_format(EXCEL_FORMATS["pass"])
        low_failures = workbook.add_format(EXCEL_FORMATS["low"])
        medium_failures = workbook.add_format(EXCEL_FORMATS["medium"])
        high_failures = workbook.add_format(EXCEL_FORMATS["high"])
        
        compliance_history = {}
        computer_names = {}
        
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
        
        trend_sheet.set_column('A:A', 20)
        trend_sheet.set_column('B:B', 30)
        for col in range(2, len(trend_df.columns)):
            trend_sheet.set_column(col, col, 15)
            # Apply conditional formatting for Pass (0 failures)
            trend_sheet.conditional_format(1, col, len(trend_df)-1, col, {
                'type': 'cell',
                'criteria': 'equal to',
                'value': 0,
                'format': pass_format
            })
            # Apply conditional formatting for Low (1-25 failures)
            trend_sheet.conditional_format(1, col, len(trend_df)-1, col, {
                'type': 'cell',
                'criteria': 'between',
                'minimum': COMPLIANCE_THRESHOLDS["low"][0],
                'maximum': COMPLIANCE_THRESHOLDS["low"][1],
                'format': low_failures
            })
            # Apply conditional formatting for Medium (26-50 failures)
            trend_sheet.conditional_format(1, col, len(trend_df)-1, col, {
                'type': 'cell',
                'criteria': 'between',
                'minimum': COMPLIANCE_THRESHOLDS["medium"][0],
                'maximum': COMPLIANCE_THRESHOLDS["medium"][1],
                'format': medium_failures
            })
            # Apply conditional formatting for High (>50 failures)
            trend_sheet.conditional_format(1, col, len(trend_df)-1, col, {
                'type': 'cell',
                'criteria': 'greater than',
                'value': COMPLIANCE_THRESHOLDS["high"][0] - 1,
                'format': high_failures
            })
        
        trend_sheet.freeze_panes(1, 2)
        
        for csv_file, file_date in dated_files:
            df = pd.read_csv(csv_file)
            df.to_excel(writer, sheet_name=file_date, index=False)
            sheet = writer.sheets[file_date]
            
            sheet.set_column('A:A', 20)
            sheet.set_column('B:B', 15)
            sheet.set_column('C:C', 40)
            sheet.set_column('D:D', 15)
            sheet.set_column('E:E', 30)
            sheet.set_column('F:F', 20)
            sheet.set_column('G:G', 15)
            sheet.set_column('H:H', 50, wrap_format)
            sheet.set_column('I:I', 20)
            
            for col_num, value in enumerate(df.columns.values):
                sheet.write(0, col_num, value, header_format)
            
            failed_col = df.columns.get_loc('Compliance - Failed mSCP Results Count')
            # Apply conditional formatting for "Pass" (0 failures)
            sheet.conditional_format(1, failed_col, len(df) + 1, failed_col, {
                'type': 'cell',
                'criteria': 'equal to',
                'value': 0,
                'format': pass_format
            })
            # Apply conditional formatting for Low (1-25 failures)
            sheet.conditional_format(1, failed_col, len(df) + 1, failed_col, {
                'type': 'cell',
                'criteria': 'between',
                'minimum': COMPLIANCE_THRESHOLDS["low"][0],
                'maximum': COMPLIANCE_THRESHOLDS["low"][1],
                'format': low_failures
            })
            # Apply conditional formatting for Medium (26-50 failures)
            sheet.conditional_format(1, failed_col, len(df) + 1, failed_col, {
                'type': 'cell',
                'criteria': 'between',
                'minimum': COMPLIANCE_THRESHOLDS["medium"][0],
                'maximum': COMPLIANCE_THRESHOLDS["medium"][1],
                'format': medium_failures
            })
            # Apply conditional formatting for High (>50 failures)
            sheet.conditional_format(1, failed_col, len(df) + 1, failed_col, {
                'type': 'cell',
                'criteria': 'greater than',
                'value': COMPLIANCE_THRESHOLDS["high"][0] - 1,
                'format': high_failures
            })
            
            sheet.freeze_panes(1, 0)
            sheet.autofilter(0, 0, len(df), len(df.columns) - 1)
        
        latest_csv_file, latest_date = dated_files[-1]
        df_latest = pd.read_csv(latest_csv_file)
        donut_chart_file = generate_donut_chart(df_latest)
        
        chart_sheet = workbook.add_worksheet('Compliance Chart')
        chart_sheet.insert_image('B2', donut_chart_file)
        
        writer.close()
        return OUTPUT_FILE
        
    except Exception as e:
        writer.close()
        raise e

if __name__ == "__main__":
    try:
        output_file = process_compliance_reports()
        print(f"\nReport generated successfully: {output_file}")
        print("\nColor coding legend (Excel & Donut Chart):")
        print(f"Pass (0 failures): {EXCEL_FORMATS['pass']['bg_color']}")
        print(f"Low (1-25 failures): {EXCEL_FORMATS['low']['bg_color']}")
        print(f"Medium (26-50 failures): {EXCEL_FORMATS['medium']['bg_color']}")
        print(f"High (>50 failures): {EXCEL_FORMATS['high']['bg_color']}")
        print("\nSheet order:")
        print("1. Trend Analysis")
        print("2. Individual date sheets (most recent to oldest)")
        print("3. Compliance Chart (donut chart)")
    except Exception as e:
        print(f"Error generating report: {str(e)}")
