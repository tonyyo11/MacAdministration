# Documentation Repository

Welcome to the **Docs** folder of the [MacAdministration](https://github.com/tonyyo11/MacAdministration) repository. This directory contains various resources and templates to assist with macOS administration tasks.

## Contents

- **mSCP Demo Data**: Sample data files for use with the macOS Security Compliance Project (mSCP) scripts.
- **Self_Career_Audit_Template.md**: A template designed to help individuals assess and plan their career development.

## Important Notice for mSCP Demo Data Users

If you're utilizing the mSCP Demo Data files from this repository, please be aware of the following:

**Adjusting File Creation Dates**:

When you download files from GitHub, the creation dates are set to the date and time of the download. For the mSCP scripts to function correctly, it's essential that these files retain their original creation dates. Incorrect dates can lead to inaccurate script results.

**Steps to Adjust Creation Dates**:

1. **Install Xcode Command Line Tools**:

   The `SetFile` command is required to modify file creation dates. This command is part of the Xcode Command Line Tools. To install them:

   ```bash
   xcode-select --install
   ```

   *Note*: If you encounter issues with the above command, you can download the tools directly from Apple's developer website.

2. **Use the `SetFile` Command**:

   After installation, you can adjust the creation date of each file using the following syntax:

   ```bash
   SetFile -d "MM/DD/YYYY HH:MM:SS" /path/to/your/file
   ```

   *Example*:

   ```bash
   SetFile -d "02/24/2025 08:21:00" ~/Downloads/mSCP_Demo_Data/Compliance_Report_2025-02-24.csv
   ```

   Repeat this process for each file in the mSCP Demo Data set. The filenames include dates to assist you in setting the correct creation date.

For a detailed walkthrough and additional context, refer to the related [blog post](https://tonyyo11.github.io/posts/mSCP-Trend-Report-Part2/).

## Additional Resources

- **Self_Career_Audit_Template.md**: This template is designed to help professionals evaluate their current career trajectory and plan future development steps.

---

*For further assistance or to report issues, please open an issue in this repository or contact the maintainer directly.*

