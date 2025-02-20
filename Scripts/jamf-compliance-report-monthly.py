"""
================================================================================
Script: jamf-compliance-report-monthly.py
Author: Tony Young
Date: February 20th, 2025
Employer: Cloud Lake Technology, an Akima company

https://github.com/tonyyo11/MacAdministration
https://tonyyo11.github.io

Description:
    This script processes Jamf Pro generated macOS Security Compliance Project report CSV files from a specified input directory, extracts the date from the filename, and selects the four most recent reports. 
    The four most recent reports are combined into a monthly trends report for appropriate stakeholders. 
    This script should be run in the parent directory of the input_directory folder. 

Disclaimer:
    This script is provided "as is" without any warranty, express or implied.
    Use it at your own risk. Neither the author nor the employer shall be held 
    responsible for any errors or damages arising from its use.

Notes:
    - Change filenames, paths, and other configuration parameters as needed.
    

================================================================================
"""

import pandas as pd
import glob
import os
from datetime import datetime
import numpy as np
import re

def extract_date_from_filename(filename):
    """Extract date from filename in format YYYY-MM-DDThh_mm_ss"""
    match = re.search(r'(\d{4}-\d{2}-\d{2})T\d{2}_\d{2}_\d{2}', os.path.basename(filename))
    if match:
        return match.group(1)  # Returns just the date portion (YYYY-MM-DD)
    return None
    
# Change input_directory to the Folder Name where you will store reports. Change output_file based on your baseline and naming needs
def process_compliance_reports():
    input_directory = "STIG_Reports"
    output_file = f"STIG_Compliance_Report_{datetime.now().strftime('%Y%m%d')}.xlsx"
    
    # Get list of CSV files
    csv_files = glob.glob(f"{input_directory}/*.csv")
    if not csv_files:
        raise FileNotFoundError(f"No CSV files found in {input_directory}")
    
    # Create list of tuples with (filename, date) and sort by date
    dated_files = []
    for file in csv_files:
        file_date = extract_date_from_filename(file)
        if file_date:
            dated_files.append((file, file_date))
    
    # Sort files by extracted date
    dated_files.sort(key=lambda x: x[1])
    dated_files = dated_files[-4:]  # Keep only most recent 4
    
    if not dated_files:
        raise ValueError("No files with valid dates in filename found")
    
    # Initialize Excel writer
    writer = pd.ExcelWriter(output_file, engine='xlsxwriter')
    workbook = writer.book
    
    try:
        # Create formats once
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
        
        low_failures = workbook.add_format({
            'bg_color': '#FFEB9C',  # Light yellow
            'font_color': '#9C6500'
        })
        
        medium_failures = workbook.add_format({
            'bg_color': '#FFB266',  # Orange
            'font_color': '#974C00'
        })
        
        high_failures = workbook.add_format({
            'bg_color': '#FFC7CE',  # Red
            'font_color': '#9C0006'
        })
        
        # Create dictionaries to store both compliance history and computer names
        compliance_history = {}
        computer_names = {}  # Store computer names
        
        # Process files and build compliance history
        for csv_file, file_date in dated_files:
            print(f"Processing file for date: {file_date}")
            df = pd.read_csv(csv_file)
            
            # Update compliance history and computer names
            for _, row in df.iterrows():
                serial = row['Serial Number']
                computer = row['Computer Name']
                failed_count = row['Compliance - Failed mSCP Results Count']
                
                # Store the computer name (will use the most recent one found)
                computer_names[serial] = computer
                
                if serial not in compliance_history:
                    compliance_history[serial] = {}
                
                compliance_history[serial][file_date] = failed_count
        
        # Create trend analysis
        trend_data = []
        dates = sorted(list(set().union(*[h.keys() for h in compliance_history.values()])))
        
        for serial, history in compliance_history.items():
            row_data = {
                'Serial Number': serial,
                'Computer Name': computer_names.get(serial, 'N/A')  # Add Computer Name
            }
            for date in dates:
                row_data[date] = history.get(date, np.nan)
            trend_data.append(row_data)
        
        # Add averages row
        averages = {
            'Serial Number': 'Average Failed Checks',
            'Computer Name': ''  # Empty string for Computer Name in averages row
        }
        for date in dates:
            values = [h.get(date) for h in compliance_history.values()]
            values = [v for v in values if pd.notna(v)]
            averages[date] = np.mean(values) if values else np.nan
        trend_data.append(averages)
        
        # Create trend analysis sheet (first)
        trend_df = pd.DataFrame(trend_data)
        trend_df.to_excel(writer, sheet_name='Trend Analysis', index=False)
        trend_sheet = writer.sheets['Trend Analysis']
        
        # Format trend analysis
        for col_num, value in enumerate(trend_df.columns.values):
            trend_sheet.write(0, col_num, value, header_format)
        
        # Adjust column widths for trend analysis
        trend_sheet.set_column('A:A', 20)  # Serial Number
        trend_sheet.set_column('B:B', 30)  # Computer Name
        for col in range(2, len(trend_df.columns)):  # Start from col 2 after Serial and Computer Name
            trend_sheet.set_column(col, col, 15)
            
            # Apply conditional formatting to data columns
            trend_sheet.conditional_format(1, col, len(trend_df)-1, col, 
                                        {'type': 'cell',
                                         'criteria': 'between',
                                         'minimum': 1,
                                         'maximum': 25,
                                         'format': low_failures})
            
            trend_sheet.conditional_format(1, col, len(trend_df)-1, col,
                                        {'type': 'cell',
                                         'criteria': 'between',
                                         'minimum': 26,
                                         'maximum': 50,
                                         'format': medium_failures})
            
            trend_sheet.conditional_format(1, col, len(trend_df)-1, col,
                                        {'type': 'cell',
                                         'criteria': 'greater than',
                                         'value': 50,
                                         'format': high_failures})
        
        # Freeze both Serial Number and Computer Name columns
        trend_sheet.freeze_panes(1, 2)
        
        # Create dated sheets
        for csv_file, file_date in dated_files:
            df = pd.read_csv(csv_file)
            df.to_excel(writer, sheet_name=file_date, index=False)
            sheet = writer.sheets[file_date]
            
            # Format columns
            sheet.set_column('A:A', 20)  # Computer Name
            sheet.set_column('B:B', 15)  # Serial Number
            sheet.set_column('C:C', 40)  # mSCP Version
            sheet.set_column('D:D', 15)  # Failed Count
            sheet.set_column('E:E', 30)  # Full Name
            sheet.set_column('F:F', 20)  # Last Inventory
            sheet.set_column('G:G', 15)  # OS Version
            sheet.set_column('H:H', 50, wrap_format)  # Failed List
            sheet.set_column('I:I', 20)  # Asset Tag
            
            # Format headers
            for col_num, value in enumerate(df.columns.values):
                sheet.write(0, col_num, value, header_format)
            
            # Add conditional formatting for failed count
            failed_col = df.columns.get_loc('Compliance - Failed mSCP Results Count')
            sheet.conditional_format(1, failed_col, len(df) + 1, failed_col,
                                  {'type': 'cell',
                                   'criteria': 'between',
                                   'minimum': 1,
                                   'maximum': 25,
                                   'format': low_failures})
            
            sheet.conditional_format(1, failed_col, len(df) + 1, failed_col,
                                  {'type': 'cell',
                                   'criteria': 'between',
                                   'minimum': 26,
                                   'maximum': 50,
                                   'format': medium_failures})
            
            sheet.conditional_format(1, failed_col, len(df) + 1, failed_col,
                                  {'type': 'cell',
                                   'criteria': 'greater than',
                                   'value': 50,
                                   'format': high_failures})
            
            sheet.freeze_panes(1, 0)
            sheet.autofilter(0, 0, len(df), len(df.columns) - 1)
        
        writer.close()
        return output_file
        
    except Exception as e:
        writer.close()
        raise e

if __name__ == "__main__":
    try:
        output_file = process_compliance_reports()
        print(f"\nReport generated successfully: {output_file}")
        print("\nColor coding legend:")
        print("- Yellow: 1-25 failures")
        print("- Orange: 26-50 failures")
        print("- Red: >50 failures")
        print("\nSheet order:")
        print("1. Trend Analysis")
        print("2. Individual date sheets (most recent to oldest)")
    except Exception as e:
        print(f"Error generating report: {str(e)}")
