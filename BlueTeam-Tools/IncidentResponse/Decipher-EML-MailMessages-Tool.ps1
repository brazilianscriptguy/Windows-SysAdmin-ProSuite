<#
.SYNOPSIS
    PowerShell Script for Decoding Suspicious Characters in Email Messages.

.DESCRIPTION
    This script applies various decoding methods, such as offset subtraction, encoding 
    conversions, ROT13, and Caesar cipher brute force, to analyze suspicious characters 
    in email messages. It helps identify hidden threats and analyze potentially harmful 
    content within emails.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: October 22, 2024
#>

# Hide the PowerShell console window for a cleaner UI unless requested to show the console
$ShowConsole = $false  # Set this to $true if you want to see the console window
if (-not $ShowConsole) {
    Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    public class Window {
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        public static void Hide() {
            var handle = GetConsoleWindow();
            ShowWindow(handle, 0); // 0 = SW_HIDE
        }
        public static void Show() {
            var handle = GetConsoleWindow();
            ShowWindow(handle, 5); // 5 = SW_SHOW
        }
    }
"@
    [Window]::Hide()
}

# Function to initialize script name and file paths, refactored for reuse in other scripts
function Initialize-ScriptPaths {
    param (
        [string]$defaultLogDir = 'C:\Logs-TEMP'
    )

    # Determine script name and set up file paths dynamically
    $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

    # Set log path allowing dynamic configuration or fallback to defaults
    $logDir = if ($env:LOG_PATH -and $env:LOG_PATH -ne "") { $env:LOG_PATH } else { $defaultLogDir }
    $logFileName = "${scriptName}.log"
    $logPath = Join-Path $logDir $logFileName

    return @{
        LogDir = $logDir
        LogPath = $logPath
        ScriptName = $scriptName
    }
}

# Initialize paths
$paths = Initialize-ScriptPaths

# Set log directory and path variables for the current session
$global:logDir = $paths.LogDir
$global:logPath = $paths.LogPath

# Enhanced logging function with error handling and validation, refactored as a reusable method
function Log-Message {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "ERROR", "WARNING", "DEBUG", "CRITICAL")]
        [string]$MessageType = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$MessageType] $Message"

    try {
        # Ensure the log path exists, create if necessary
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -ErrorAction Stop
        }
        # Attempt to write to the log file
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    } catch {
        # Fallback: Log to console if writing to the log file fails
        Write-Error "Failed to write to log: $_"
        Write-Output $logEntry
    }
}

# Unified error handling function refactored as a reusable method
function Handle-Error {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage
    )
    Log-Message -Message "ERROR: $ErrorMessage" -MessageType "ERROR"
    [System.Windows.Forms.MessageBox]::Show($ErrorMessage, "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}

# Function to analyze suspicious Unicode characters
function Analyze-UnicodeCharacters {
    param (
        [string]$Content
    )
    Log-Message -Message "Analyzing suspicious Unicode characters."
    $output = "[Analyzing Suspicious Unicode Characters]:`n"
    # Exclude standard whitespace characters (Tab, LF, CR)
    $unicodePattern = '[^\x20-\x7E\x09\x0A\x0D]'
    $unicodeMatches = [regex]::Matches($Content, $unicodePattern)
    if ($unicodeMatches.Count -gt 0) {
        $output += "Suspicious Unicode Characters Found:`n"
        foreach ($match in $unicodeMatches) {
            $output += "Character: $($match.Value) | Code Point: $([int][char]$match.Value)`n"
        }
    } else {
        $output += "No suspicious Unicode characters found.`n"
    }
    return $output
}

# Function to decode Quoted-Printable content
function Decode-QuotedPrintable {
    param (
        [string]$Content
    )
    Log-Message -Message "Decoding Quoted-Printable content."
    $output = "`n[Quoted-Printable Decoding]:`n"

    $qpPattern = '(?ms)(Content-Transfer-Encoding:\s*quoted-printable.*?)(?:\r?\n){2}(.*?)(?:\r?\n){2}'
    $qpMatches = [regex]::Matches($Content, $qpPattern)

    if ($qpMatches.Count -gt 0) {
        foreach ($match in $qpMatches) {
            $encodedText = $match.Groups[2].Value

            # Remove soft line breaks
            $encodedText = $encodedText -replace "=\r?\n", ""

            # Decode the quoted-printable text
            $decodedText = $encodedText -replace '=([0-9A-Fa-f]{2})', { [char][Convert]::ToInt32($args[0].Groups[1].Value, 16) }

            $output += "`n[Decoded Quoted-Printable Text]:`n" + $decodedText + "`n"
        }
    } else {
        $output += "No Quoted-Printable content found.`n"
    }
    return $output
}

# Function to decode Base64 content
function Decode-Base64Content {
    param (
        [string]$Content
    )
    Log-Message -Message "Decoding Base64 content."
    $output = "`n[Base64 Decoding]:`n"
    $base64Pattern = '(?ms)(Content-Transfer-Encoding:\s*base64.*?)(?:\r?\n){2}(.*?)(?:\r?\n){2}'
    $base64Matches = [regex]::Matches($Content, $base64Pattern)

    if ($base64Matches.Count -gt 0) {
        foreach ($match in $base64Matches) {
            $encodedText = $match.Groups[2].Value -replace '\s', ''

            try {
                $decodedBytes = [System.Convert]::FromBase64String($encodedText)
                $decodedText = [System.Text.Encoding]::UTF8.GetString($decodedBytes)
                $output += "`n[Decoded Base64 Text]:`n" + $decodedText + "`n"
            } catch {
                $output += "[Error decoding Base64: $($_.Exception.Message)]`n"
                Log-Message -Message "Error decoding Base64: $($_.Exception.Message)" -MessageType "ERROR"
            }
        }
    } else {
        $output += "No Base64 content found.`n"
    }
    return $output
}

# Function to decode suspicious characters in the message body
function Decode-SuspiciousCharacters {
    param (
        [string]$Content,
        [string]$UserLanguage
    )
    Log-Message -Message "Decoding suspicious characters."
    $output = "`n[Decoding Suspicious Characters]:`n"

    # Extract the message body
    $bodyPattern = '(?s)\r?\n\r?\n(.*)'
    $bodyMatch = [regex]::Match($Content, $bodyPattern)
    if ($bodyMatch.Success) {
        $body = $bodyMatch.Groups[1].Value

        # Find suspicious characters (excluding whitespace)
        $unicodePattern = '[^\x20-\x7E\x09\x0A\x0D]'
        $suspiciousChars = [regex]::Matches($body, $unicodePattern) | ForEach-Object { $_.Value }

        if ($suspiciousChars.Count -gt 0) {
            $output += "Suspicious Characters Found in Message Body:`n"
            $codePoints = @()
            foreach ($char in $suspiciousChars) {
                $codePoint = [int][char]$char
                $output += "Character: $char | Code Point: $codePoint`n"
                $codePoints += $codePoint
            }

            if ($codePoints.Count -gt 0) {
                # Attempt various decoding methods
                $output += "`nAttempting to decode using different methods:`n"

                # Method 1: Subtract 128
                $decodedMessage1 = Decode-ByOffset -CodePoints $codePoints -Offset 128
                $output += "`nMethod 1 (Subtract 128):`n$decodedMessage1`n"

                # Method 2: Windows-1252 Encoding
                $decodedMessage2 = Decode-WithEncoding -CodePoints $codePoints -EncodingName 'Windows-1252'
                $output += "`nMethod 2 (Windows-1252):`n$decodedMessage2`n"

                # Method 3: UTF-8 Encoding
                $decodedMessage3 = Decode-WithEncoding -CodePoints $codePoints -EncodingName 'UTF-8'
                $output += "`nMethod 3 (UTF-8):`n$decodedMessage3`n"

                # Method 4: Subtract 96
                $decodedMessage4 = Decode-ByOffset -CodePoints $codePoints -Offset 96
                $output += "`nMethod 4 (Subtract 96):`n$decodedMessage4`n"

                # Analysis of Method 4
                $output += "`n[Analysis of Decoded Message - Method 4]:`n"
                $analysisResult = Analyze-DecodedMessage -DecodedMessage $decodedMessage4 -UserLanguage $UserLanguage
                $output += $analysisResult

                # Method 5: ROT13 Cipher
                $decodedMessage5 = Decode-ROT13 -InputString ($suspiciousChars -join '')
                $output += "`nMethod 5 (ROT13):`n$decodedMessage5`n"

                # Method 6: Caesar Cipher Brute Force
                $output += "`nMethod 6 (Caesar Cipher Brute Force):`n"
                for ($shift = 1; $shift -le 25; $shift++) {
                    $decodedMessage6 = Decode-CaesarCipher -CodePoints $codePoints -Shift $shift
                    if ($decodedMessage6 -match '[A-Za-zÀ-ÿ]') {
                        $output += "Shift ${shift}:`n${decodedMessage6}`n"
                    }
                }

            } else {
                $output += "No non-whitespace suspicious characters found for decoding.`n"
            }

        } else {
            $output += "No suspicious characters found in message body.`n"
        }
    } else {
        $output += "Could not extract message body.`n"
    }
    return $output
}

# Function to decode by subtracting an offset
function Decode-ByOffset {
    param (
        [int[]]$CodePoints,
        [int]$Offset
    )
    $decodedMessage = ""
    foreach ($codePoint in $CodePoints) {
        $adjustedCodePoint = $codePoint - $Offset
        while ($adjustedCodePoint -lt 32) {
            $adjustedCodePoint += 95  # Wrap around the printable ASCII range
        }
        if ($adjustedCodePoint -ge 32 -and $adjustedCodePoint -le 126) {
            $decodedMessage += [char]$adjustedCodePoint
        } else {
            $decodedMessage += '?'
        }
    }
    return $decodedMessage
}

# Function to decode using a specific encoding
function Decode-WithEncoding {
    param (
        [int[]]$CodePoints,
        [string]$EncodingName
    )
    $encoding = [System.Text.Encoding]::GetEncoding($EncodingName)
    $bytes = @()
    foreach ($codePoint in $CodePoints) {
        if ($codePoint -le 255) {
            $bytes += [byte]$codePoint
        }
    }
    $decodedMessage = $encoding.GetString($bytes)
    return $decodedMessage
}

# Function to perform ROT13 decoding
function Decode-ROT13 {
    param (
        [string]$InputString
    )
    $rot13 = ""
    foreach ($char in $InputString.ToCharArray()) {
        $codePoint = [int][char]$char
        if (($codePoint -ge 65 -and $codePoint -le 90) -or ($codePoint -ge 97 -and $codePoint -le 122)) {
            if ($codePoint -ge 65 -and $codePoint -le 90) {
                $base = 65
            } else {
                $base = 97
            }
            $rotatedCodePoint = (($codePoint - $base + 13) % 26) + $base
            $rot13 += [char]$rotatedCodePoint
        } else {
            $rot13 += $char
        }
    }
    return $rot13
}

# Function to decode using Caesar cipher with a given shift
function Decode-CaesarCipher {
    param (
        [int[]]$CodePoints,
        [int]$Shift
    )
    $decodedMessage = ""
    foreach ($codePoint in $CodePoints) {
        $adjustedCodePoint = $codePoint - $Shift
        while ($adjustedCodePoint -lt 32) {
            $adjustedCodePoint += 95  # Wrap around the printable ASCII range
        }
        if ($adjustedCodePoint -ge 32 -and $adjustedCodePoint -le 126) {
            $decodedMessage += [char]$adjustedCodePoint
        } else {
            $decodedMessage += '?'
        }
    }
    return $decodedMessage
}

# Function to segment words using a dictionary
function Segment-Words {
    param (
        [string]$Text,
        [string]$Language
    )
    $wordList = @()
    if ($Language -eq "Portuguese") {
        $wordList = @("mensagem", "de", "teste", "mensagem de teste")
    } elseif ($Language -eq "English") {
        $wordList = @("message", "test", "test message")
    } elseif ($Language -eq "Spanish") {
        $wordList = @("mensaje", "de", "prueba", "mensaje de prueba")
    }
    # Split the text using the word list
    $pattern = ($wordList | Sort-Object -Property Length -Descending | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $matches = [regex]::Matches($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($matches.Count -gt 0) {
        $segmentedText = ($matches | ForEach-Object { $_.Value } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }) -join ' '
        return $segmentedText
    } else {
        # If no matches, return the original text
        return $Text
    }
}

# Function to analyze the decoded message
function Analyze-DecodedMessage {
    param (
        [string]$DecodedMessage,
        [string]$UserLanguage
    )

    $output = ""

    # Remove any placeholders (e.g., '?') from the decoded message
    $cleanMessage = $DecodedMessage -replace '\?', ''

    # Remove repetitive patterns like '@!' from the message
    $cleanMessage = $cleanMessage -replace '(@!)+', ''

    # Remove any additional '@' or '!' characters that might be left
    $cleanMessage = $cleanMessage -replace '[@!]', ''

    # Check if the message contains readable text
    if ($cleanMessage -match '[A-Za-zÀ-ÿ]') {
        # Segment the message into words
        $segmentedMessage = Segment-Words -Text $cleanMessage -Language $UserLanguage

        $output += "`n[Decoded Message]:`n"
        $output += "$segmentedMessage`n"

        # Perform deeper analysis
        $output += "`n[Deeper Analysis]:`n"

        # Use the user-specified language
        $language = $UserLanguage
        $output += "Language Specified by User: $language`n"

        # Keyword Extraction
        $keywords = Extract-Keywords -Text $segmentedMessage -Language $language
        if ($keywords.Count -gt 0) {
            $output += "Extracted Keywords:`n"
            $output += ($keywords -join ', ') + "`n"
        } else {
            $output += "No significant keywords found.`n"
        }

        # Entity Recognition (URLs, Emails)
        $entities = Extract-Entities -Text $segmentedMessage
        if ($entities.Count -gt 0) {
            $output += "Extracted Entities:`n"
            foreach ($entity in $entities) {
                $output += "$entity`n"
            }
        } else {
            $output += "No entities found in the message.`n"
        }

        # Character Frequency Analysis
        $output += "`nCharacter Frequency Analysis:`n"
        $frequency = Get-CharacterFrequency -Text $segmentedMessage
        foreach ($item in $frequency.GetEnumerator() | Sort-Object -Property Value -Descending) {
            $output += "Character: '$($item.Key)' | Frequency: $($item.Value)`n"
        }

    } else {
        $output += "The decoded message does not contain readable text after cleaning.`n"
    }

    return $output
}

# Function to extract keywords (supports multiple languages)
function Extract-Keywords {
    param (
        [string]$Text,
        [string]$Language
    )
    # Define stop words for different languages
    $stopWords = @{
        "English" = @("the", "and", "is", "in", "at", "of", "a", "to", "it", "for", "on", "with", "as", "by", "that", "from")
        "Portuguese" = @("e", "o", "a", "os", "as", "de", "do", "da", "dos", "das", "em", "um", "uma", "para", "com", "no", "na", "nos", "nas")
        "Spanish" = @("el", "la", "los", "las", "y", "de", "del", "a", "un", "una", "para", "con", "en", "por", "que", "es", "al", "lo")
        # Add more languages and their stop words here
    }

    $languageStopWords = $stopWords[$Language] | ForEach-Object { $_.ToLower() }

    $words = ($Text -split '\W+') | Where-Object { $_ } | ForEach-Object { $_.ToLower() }
    $words = $words | Where-Object { $_ -and ($_ -notin $languageStopWords) }

    # Get word frequencies
    $wordFrequency = @{}
    foreach ($word in $words) {
        if ($wordFrequency.ContainsKey($word)) {
            $wordFrequency[$word] += 1
        } else {
            $wordFrequency[$word] = 1
        }
    }
    # Return the top 10 most frequent words
    return ($wordFrequency.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 10 | ForEach-Object { $_.Key })
}

# Function to extract entities like URLs and emails
function Extract-Entities {
    param (
        [string]$Text
    )
    $entities = @()

    # Extract URLs
    $urlPattern = '(http|https)://[^\s/$.?#].[^\s]*'
    $urls = [regex]::Matches($Text, $urlPattern) | ForEach-Object { $_.Value }
    if ($urls.Count -gt 0) {
        $entities += "URLs:"
        $entities += $urls
    }

    # Extract Email Addresses
    $emailPattern = '\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'
    $emails = [regex]::Matches($Text, $emailPattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase) | ForEach-Object { $_.Value }
    if ($emails.Count -gt 0) {
        $entities += "Email Addresses:"
        $entities += $emails
    }

    return $entities
}

# Function to perform character frequency analysis
function Get-CharacterFrequency {
    param (
        [string]$Text
    )
    $frequency = @{}
    foreach ($char in $Text.ToCharArray()) {
        if ($frequency.ContainsKey($char)) {
            $frequency[$char] += 1
        } else {
            $frequency[$char] = 1
        }
    }
    return $frequency
}

# Function to analyze the .eml file
function Analyze-EMLFile {
    param (
        [string]$FilePath,
        [string]$OutputFilePath,
        [string]$UserLanguage
    )

    Log-Message -Message "Starting analysis of file: $FilePath"
    try {
        # Load the content of the .eml file
        $content = Get-Content -Path $FilePath -Raw -ErrorAction Stop
    } catch {
        Handle-Error -ErrorMessage "Error loading file: $($_.Exception.Message)"
        return
    }

    # Create or clear the output file
    try {
        Remove-Item -Path $OutputFilePath -ErrorAction SilentlyContinue
        New-Item -Path $OutputFilePath -ItemType File -Force
    } catch {
        Handle-Error -ErrorMessage "Error creating output file: $($_.Exception.Message)"
        return
    }

    # Analyze suspicious Unicode characters
    $unicodeAnalysis = Analyze-UnicodeCharacters -Content $content
    Add-Content -Path $OutputFilePath -Value $unicodeAnalysis

    # Decode Quoted-Printable content
    $qpDecoded = Decode-QuotedPrintable -Content $content
    Add-Content -Path $OutputFilePath -Value $qpDecoded

    # Decode Base64 content
    $base64Decoded = Decode-Base64Content -Content $content
    Add-Content -Path $OutputFilePath -Value $base64Decoded

    # Decode suspicious characters using all methods
    $decodedSuspicious = Decode-SuspiciousCharacters -Content $content -UserLanguage $UserLanguage
    Add-Content -Path $OutputFilePath -Value $decodedSuspicious

    Log-Message -Message "Analysis completed for file: $FilePath"
}

# Interface to select and analyze the .eml file
$form = New-Object System.Windows.Forms.Form
$form.Text = "EML File Analysis Tool"
$form.Size = New-Object System.Drawing.Size(400, 350)
$form.StartPosition = "CenterScreen"
$form.Topmost = $true

# Button to select the .eml file
$buttonSelectFile = New-Object System.Windows.Forms.Button
$buttonSelectFile.Text = "Select EML File"
$buttonSelectFile.Size = New-Object System.Drawing.Size(360, 40)
$buttonSelectFile.Location = New-Object System.Drawing.Point(10, 20)
$buttonSelectFile.Add_Click({
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Filter = "EML Files (*.eml)|*.eml"
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $filePath = $dialog.FileName
            $textBoxFilePath.Text = $filePath
        }
    })

# TextBox to display the selected file path
$textBoxFilePath = New-Object System.Windows.Forms.TextBox
$textBoxFilePath.Size = New-Object System.Drawing.Size(360, 20)
$textBoxFilePath.Location = New-Object System.Drawing.Point(10, 70)
$textBoxFilePath.ReadOnly = $true

# Label for language selection
$labelLanguage = New-Object System.Windows.Forms.Label
$labelLanguage.Text = "Select Language:"
$labelLanguage.Location = New-Object System.Drawing.Point(10, 100)
$labelLanguage.Size = New-Object System.Drawing.Size(100, 20)

# ComboBox for language selection
$comboBoxLanguage = New-Object System.Windows.Forms.ComboBox
$comboBoxLanguage.Location = New-Object System.Drawing.Point(120, 100)
$comboBoxLanguage.Size = New-Object System.Drawing.Size(250, 20)
$comboBoxLanguage.DropDownStyle = 'DropDownList'
$comboBoxLanguage.Items.Add("English")
$comboBoxLanguage.Items.Add("Portuguese")
$comboBoxLanguage.Items.Add("Spanish")
$comboBoxLanguage.SelectedIndex = 0  # Default to English

# Label for output file path
$labelOutputPath = New-Object System.Windows.Forms.Label
$labelOutputPath.Text = "Output File Path:"
$labelOutputPath.Location = New-Object System.Drawing.Point(10, 130)
$labelOutputPath.Size = New-Object System.Drawing.Size(100, 20)

# TextBox for output file path
$textBoxOutputPath = New-Object System.Windows.Forms.TextBox
$textBoxOutputPath.Size = New-Object System.Drawing.Size(250, 20)
$textBoxOutputPath.Location = New-Object System.Drawing.Point(120, 130)
$textBoxOutputPath.Text = "C:\Logs-TEMP\EML_Analysis_Result.txt"

# Button to browse output file path
$buttonBrowseOutput = New-Object System.Windows.Forms.Button
$buttonBrowseOutput.Text = "Browse"
$buttonBrowseOutput.Size = New-Object System.Drawing.Size(80, 20)
$buttonBrowseOutput.Location = New-Object System.Drawing.Point(310, 130)
$buttonBrowseOutput.Add_Click({
        $dialog = New-Object System.Windows.Forms.SaveFileDialog
        $dialog.Filter = "Text Files (*.txt)|*.txt"
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $outputFilePath = $dialog.FileName
            $textBoxOutputPath.Text = $outputFilePath
        }
    })

# Status label
$labelStatus = New-Object System.Windows.Forms.Label
$labelStatus.Text = ""
$labelStatus.Location = New-Object System.Drawing.Point(10, 160)
$labelStatus.Size = New-Object System.Drawing.Size(360, 20)

# Button to start the analysis
$buttonAnalyze = New-Object System.Windows.Forms.Button
$buttonAnalyze.Text = "Start Analysis"
$buttonAnalyze.Size = New-Object System.Drawing.Size(360, 40)
$buttonAnalyze.Location = New-Object System.Drawing.Point(10, 190)
$buttonAnalyze.Add_Click({
        if ([string]::IsNullOrWhiteSpace($textBoxFilePath.Text)) {
            Handle-Error -ErrorMessage "Please select an EML file before starting the analysis."
        } else {
            $labelStatus.Text = "Analysis in progress..."
            $form.Refresh()
            $outputFilePath = $textBoxOutputPath.Text
            $userLanguage = $comboBoxLanguage.SelectedItem.ToString()
            Analyze-EMLFile -FilePath $textBoxFilePath.Text -OutputFilePath $outputFilePath -UserLanguage $userLanguage
            $labelStatus.Text = "Analysis completed."
            $form.Refresh()
            $result = [System.Windows.Forms.MessageBox]::Show("Analysis completed. Do you want to open the results?", "Analysis Completed", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Information)
            if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
                Invoke-Item -Path $outputFilePath
            }
        }
    })

# Add controls to the form
$form.Controls.Add($buttonSelectFile)
$form.Controls.Add($textBoxFilePath)
$form.Controls.Add($labelLanguage)
$form.Controls.Add($comboBoxLanguage)
$form.Controls.Add($labelOutputPath)
$form.Controls.Add($textBoxOutputPath)
$form.Controls.Add($buttonBrowseOutput)
$form.Controls.Add($labelStatus)
$form.Controls.Add($buttonAnalyze)

# Display the form
[void]$form.ShowDialog()

# End of script
