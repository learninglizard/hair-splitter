<#MIT License
Copyright (c) 2022 William Thompson
Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:
The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHOR OR COPYRIGHT HOLDER BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.#>
<#////////////////////////////////
# INSTRUCTIONS ON HOW TO RUN
# 1.)  Search for 'Windows  PowerShell ISE' in the start menu
# 2.)  If there is no untitled blank file open press Ctrl + R to make one appear
# 3.)  Drag script file or copy and paste the contents into the ISE
#          (The white background editor part... if it's missing, press Ctrl + 2)
# 4.)  Change the $usrMaxImportFileSize to the size you want your *.imscc files split by
# 5.)  Then smash the green play button! (Or press F5)
# 6.)  You should be able to upload the part files in any order
#      IMPORTANT!:  Upload all zip files as .zip files under the -courses- directory
# 7.) Check your course, everything should be gtg
#///////////////////////////////#>
<# NOTES FROM THE AUTHOR:
# The output will be one *.imscc file and zero or more *.zip files
# The output files will be located in the same directory as your original imscc file.
# HOW IT WORKS
# The 'algorithm' works the same way as one might load groceries onto a conveyor belt at the supermarket.
# It sorts all files in the *.imscc from smallest to largest
# Then it begins filling the first 'grocery cart' with all the files your course must have
# until it finishes with mandatory files or moves on to your course's 'Files' folder
# It creates new 'grocery carts' as required and continues until it finishes copying all data.
# Importing the *.imscc file generated by this script into Canvas will generate errors.
# However, once you import all the zip file parts (*.zip), your course should be completely intact.#>
# Resources
# Commmon Cartidge File Format specs
# https://www.imsglobal.org/cc/index.html

# import .NET 4.5 compression utilities & support for file browsing when run from CLI
    Add-Type -Assembly System.IO.Compression;
    Add-Type -Assembly System.IO.Compression.FileSystem;
    Add-Type -Assembly System.Windows.Forms;
Clear-Host
# //TODO change script to params to support pipelining
# /////         USER-CONFIGURABLE PREFERENCES      \\\\\
    # Powershell inherently supports files sizes, you can change this value to adjust the script
    # Ensure that you have the units with no space on the end ie. 2500KB or 1.5GB
    # You can use https://www.wolframalpha.com/input?i=how+long+to+upload+1GB+at+10+mbps
    # to calculate your optimum part files size. Try to make sure you can upload 1 part file in 30 minutes
    Set-Variable usrMaxImportFileSize -Option ReadOnly -Value 500MB -Force
# Part file suffix [default is "part" ie. Your_Original.imscc => Your_Original (part 1).imscc]
# Change this value if you want the output files to be names something besides "part"
    Set-Variable usrSuffix -Option ReadOnly -Value 'part' -Force
# /////   END   USER-CONFIGURABLE PREFERENCES  END   \\\\\
[System.IO.Compression.CompressionLevel]$Compression = "Fastest"

# Writes a part file to disk
$null= function Write-MemoryToArchive ($savePath)
        {
        # Finally close the orignal zip file.  This is necessary 
        # because the zip file does not get closed automatically
        # close our zipstream so that we can write it to disk without it being corrupt
        $zipStream.Dispose()
        # Create our FileStream
        [System.IO.FileStream]$fileStream = New-Object System.IO.FileStream(@($savePath), [System.IO.FileMode]::Create)
        # Go to the beggining of the memory stream to prepare to read it
        $memoryStream.Seek(0, [System.IO.SeekOrigin]::Begin)
        # Write to disk
        $memoryStream.CopyTo($fileStream)
        # Reset memory Stream
        $null = $memoryStream.Seek(0, [System.IO.SeekOrigin]::Begin)
        $null = $memoryStream.SetLength(0)
        $fileStream.Dispose()
        $fileStream.Dispose()
        }

# Generates part file names
$null=function File-NameGenerator($counter)
{
        return ($FileBrowser.FileName.Substring(0,$FileBrowser.FileName.Length-6))+' ('+$usrSuffix+' '+$counter+').zip'
}

# Crappy File Browsing Dialog
$FileBrowser = New-Object System.Windows.Forms.OpenFileDialog
$FileBrowser.filter = "Canvas Export Files (*.imscc)| *.imscc"
$FileBrowser.InitialDirectory = $env:USERPROFILE+'\Downloads'
$result = $FileBrowser.ShowDialog()
    if ($result -eq "Cancel")
        {
            Write-Output ("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
            "File browsing cancelled. Exiting.",
            "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX`n")
            return
    }
$FileBrowser.FileName
# Initialize File Counters & Paths
$PartFileCounter = 1
$TotalSizeWritten = 0
$IMSCCPartFilePath = ($FileBrowser.FileName.Substring(0,$FileBrowser.FileName.Length-6))+' ('+$usrSuffix+' '+$PartFileCounter+').zip'
# Check to see if we're going to overwrite some files!
# Relies on System.Mgmt.Automation, so try statement for all those MAC users
# Maybe it'll work?
try{
if (Test-Path $IMSCCPartFilePath)
{
    $caption = "                              Some part files already exist!"
    $message = "                  Do you want to proceed and Overwrite them? `n Don't forget to close all windows with any of the files open before continuing!"
    [int]$defaultChoice = 0
    $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Yes please; overwrite those part files!"
    $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Stop  stop stop."
    $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
    $choiceRTN = $host.ui.PromptForChoice($caption,$message, $options,$defaultChoice)
    if ($choiceRTN -ne 0)
    {
    Write-Output ("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
    "File browsing cancelled. Exiting.",
    "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX")
    return
    }
}
}
catch {
}
# Er body likes progress bars and metrics
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$scriptRuntime = [System.Diagnostics.Stopwatch]::StartNew()

# Use a MemoryStream to hold the inflated file content
$memoryStream = New-Object System.IO.MemoryStream
# Create the zip file in memory and leave it open:
$zipStream = New-Object System.IO.Compression.ZipArchive($memoryStream, [System.IO.Compression.ZipArchiveMode]::Create, $true)
    $zip = [IO.Compression.ZipFile]::OpenRead($FileBrowser.FileName)

# Calculate total compressed size
$TotalSize = ($zip.Entries | Measure  CompressedLength -Sum).Sum

    # Generate web_resource .zip files first
    $null = $zip.Entries |
        # For web resources, let's sort by size from smallest to largest
        # This helps prevent a massive *imscc file
        Sort-Object -Property CompressedLength |
        # The file will be everything in the web_resources folder
        Where-Object { $_.FullName -match ".*\web_resources\.*" } |
        ForEach-Object {
        $fileMemoryStream = New-Object System.IO.MemoryStream
        $file = $_.Open()
        $file.CopyTo($fileMemoryStream)
        # Removes web_resources folder
        $entry = $zipStream.CreateEntry($_.Fullname.Substring(14))
        # Loads file into memory
        $open = $entry.Open()
        $fileMemoryStream.Position = 0
        $fileMemoryStream.CopyTo($open)
        # Update our total progress first!
        $TotalSizeWritten = [math]::Round(($_.CompressedLength) + $TotalSizeWritten)
        $fileMemoryStream.Flush()
        $open.Flush()
        $open.Dispose()
        # Update Overall Progress Bar
        $webpercentComplete = [math]::Round($TotalSizeWritten/$TotalSize*100)
        $OverallActivityText = "Writing Canvas Files folder (.zip) files...   " + $_.FullName.Substring(14) + "  Overall progress " + [math]::Round($TotalSizeWritten/1MB) +" MB out of " + [math]::Round($TotalSize/1MB) + " MBs"
        $null = If ($sw.Elapsed.TotalMilliseconds -ge 1000) {
                               Write-Progress `
                               -Activity $OverallActivityText `
                               -Id 1 `
                               -PercentComplete $webpercentComplete;
                               $sw.Reset();
                               $sw.Start()}
        # If our memory stream which contains our part file is larger than the
        # usr specified part file size, time to write it to disk and make a new one
        if( [math]::Round(($memoryStream.Length)) -gt $usrMaxImportFileSize)
        {
            # Save our current progress to disk as a part file
            Write-MemoryToArchive ($IMSCCPartFilePath)
            # Increment the part file counter
            $PartFileCounter++
            $IMSCCPartFilePath = File-NameGenerator($PartFileCounter)
            # Make a new zipstream
            $zipStream = New-Object System.IO.Compression.ZipArchive($memoryStream, [System.IO.Compression.ZipArchiveMode]::Create, $true)
        }
        
    }

# Now that we're finished with the web resources, write the last web-resources part file!
            Write-MemoryToArchive ($IMSCCPartFilePath)
            # Increment the part file counter
            $PartFileCounter++
            $IMSCCPartFilePath = File-NameGenerator($PartFileCounter)
            # Make a new zipstream from the $memoryStream
            $zipStream = New-Object System.IO.Compression.ZipArchive($memoryStream, [System.IO.Compression.ZipArchiveMode]::Create, $true)

    $null= $zip.Entries |
        # The file will be everything NOT in the web_resources folder
        Where-Object { $_.FullName -notmatch ".*\web_resources\.*" } |
        ForEach-Object {
        $fileMemoryStream = New-Object System.IO.MemoryStream
        $file = $_.Open()
        $file.CopyTo($fileMemoryStream)
        # Create a new entry
        $entry = $zipStream.CreateEntry($_)
        # Loads file into memory
        $open = $entry.Open()
        $fileMemoryStream.Position = 0
        $fileMemoryStream.CopyTo($open)
        $fileMemoryStream.Flush()
        $open.Flush()
        $open.Dispose()
    # Update our total progress first!
    $TotalSizeWritten = [math]::Round(($_.Length) + $TotalSizeWritten)
    # Update Overall Progress Bar
    $percentComplete = [math]::Round(($TotalSizeWritten/1MB)/($TotalSize/1MB)*100)
    if ($percentComplete -ge 100) {$percentComplete = 98}
    $OverallActivityText = "Writing IMSCC files (*.imscc)...   " + $_.FullName + "  Overall progress " + $TotalSizeWritten/1MB +" MB out of " + $TotalSize/1MB + " MBs"
    $null = If ($sw.Elapsed.TotalMilliseconds -ge 1000) {
                               Write-Progress `
                               -Activity $OverallActivityText `
                               -Id 1 `
                               -PercentComplete [int]$percentComplete*100;
                               $sw.Reset();
                               $sw.Start()}
   }

    $IMSCCPartFilePath = ($FileBrowser.FileName.Substring(0,$FileBrowser.FileName.Length-6))+' ('+$usrSuffix+' '+$PartFileCounter+').imscc'
    Write-MemoryToArchive ($IMSCCPartFilePath)
    # Finally close the orignal zip file.  This is necessary 
    # because the zip file does not get closed automatically
    $zip.Dispose()
    # close our zipstream so that we can write it to disk without it being corrupt
    $zipStream.Dispose()
    $memoryStream.Dispose()
    $scriptRuntime.Stop()
    $percentComplete=1
    $webpercentComplete=1
    Write-Output ("The script has completed!", "" ,
    ("It generated " + $PartFileCounter +" part files in " + $scriptRuntime.Elapsed.Minutes +
    " minutes and " + $scriptRuntime.Elapsed.Seconds + " seconds.",
    "`n`n Your part files are located in: `n`n", $IMSCCPartFilePath))
