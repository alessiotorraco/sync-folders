#https://github.com/alessiotorraco/sync-folders
#MIT License

#Copyright (c) 2021 Alessio Torraco

#Permission is hereby granted, free of charge, to any person obtaining a copy
#of this software and associated documentation files (the "Software"), to deal
#in the Software without restriction, including without limitation the rights
#to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#copies of the Software, and to permit persons to whom the Software is
#furnished to do so, subject to the following conditions:

#The above copyright notice and this permission notice shall be included in all
#copies or substantial portions of the Software.

#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#SOFTWARE.

# Get file MD5 hash
function Get-FileMD5 {
    Param([string]$file)
    $md5 = [System.Security.Cryptography.HashAlgorithm]::Create("MD5")
    $IO = New-Object System.IO.FileStream($file, [System.IO.FileMode]::Open)
    $StringBuilder = New-Object System.Text.StringBuilder
    $md5.ComputeHash($IO) | % { [void] $StringBuilder.Append($_.ToString("x2")) }
    $hash = $StringBuilder.ToString()
    $IO.Dispose()
    return $hash
}

# Implementation of GCI with Depth levels
Function Get-ChildItemToDepth {
    Param(
        [String]$Path = $PWD,
        [String]$Filter = "*",
        [Byte]$ToDepth = 255,
        [Byte]$CurrentDepth = 0,
        [Switch]$DebugMode
    )
    $CurrentDepth++
    If ($DebugMode) {
        $DebugPreference = "Continue"
    }

    Get-ChildItem $Path | %{
        $_ | ?{ $_.Name -Like $Filter }

        If ($_.PsIsContainer) {
            If ($CurrentDepth -le $ToDepth) {

                # Callback to this function
                Get-ChildItemToDepth -Path $_.FullName -Filter $Filter `
                  -ToDepth $ToDepth -CurrentDepth $CurrentDepth
            }
        }
    }
}

# Print summary information
function showSummary() {
    Param(
        [string]$action = "pull"
    )
    if (($newer.count -eq 0) -And ($updated.count -eq 0) -And ($notUpdated.count -eq 0) -And ($created.count -eq 0) -And ($cancelled.count -eq 0)) {
        if ($action -eq "pull") {
            Write-Host -ForegroundColor Cyan "Everything is up-to-date`n"
        } else {
            Write-Host -ForegroundColor Cyan "Nothing to push`n"
        }
    } else {
        Write-Host -ForegroundColor DarkCyan "SUMMARY:`n"
        Write-Host -ForegroundColor Cyan "Newer file(s) found:"
        if ($newer.count -gt 0) {
            foreach ($item in $newer) {
                Write-Host $item
            }
            Write-Host
        } else {
            Write-Host "None`n"
        }
        Write-Host -ForegroundColor Cyan "Updated file(s):"
        if ($updated.count -gt 0) {
            foreach ($item in $updated) {
                Write-Host $item
            }
            Write-Host
        } else {
            Write-Host "None`n"
        }
        Write-Host -ForegroundColor Cyan "Not updated file(s):"
        if ($notUpdated.count -gt 0) {
            foreach ($item in $notUpdated) {
                Write-Host $item
            }
            Write-Host
        } else {
            Write-Host "None`n"
        }
        Write-Host -ForegroundColor Cyan "New file(s) created:"
        if ($created.count -gt 0) {
            foreach ($item in $created) {
                Write-Host $item
            }
            Write-Host
        } else {
            Write-Host "None`n"
        }
        Write-Host -ForegroundColor Red "Cancelled by user:"
        if ($cancelled.count -gt 0) {
            foreach ($item in $cancelled) {
                Write-Host $item
            }
            Write-Host
        } else {
            Write-Host "None`n"
        }
    }
}

# PULL
function pull {
    Param(
        [ValidateNotNullOrEmpty()]
        [string]$SRC_DIR=$(throw "Source directory is mandatory, please provide a value."),
        [ValidateNotNullOrEmpty()]
        [string]$DST_DIR=$(throw "Destination directory is mandatory, please provide a value."),
        $AUTO = $true,
        $VERBOSE = $false
    )
    $sourceFiles = $null
    foreach ($filter in $Filter) {
        $SourceFiles += Get-ChildItemToDepth -ToDepth 2 -Path $SRC_DIR -Filter $filter
    }
    $SourceFiles | % { # loop through the source dir files
        $src = $_.FullName #current source dir file
        $wdsrc = [datetime]$_.LastWriteTime
        if ($VERBOSE -eq $true) {
            Write-Host -ForegroundColor Yellow "SLW: " -NoNewLine; Write-Host $wdsrc -NoNewLine; Write-Host -ForegroundColor Red " SFN: " -NoNewLine; Write-Host $src
        }
        $dest = $src -replace $SRC_DIR.Replace('\','\\'),$DST_DIR
        if (test-path $dest) { #if file exists, check md5 hash
            $wddst = [datetime](Get-ItemProperty -Path $dest -Name LastWriteTime).lastwritetime
            if ($VERBOSE -eq $true) {
                Write-Host -ForegroundColor Yellow "DLW: " -NoNewLine; Write-Host $wddst -NoNewLine; Write-Host -ForegroundColor Red " DFN: " -NoNewLine; Write-Host $dest
            }
            if ((get-date $wdsrc) -gt (get-date $wddst)) {
                $newer += $src
                $srcMD5 = Get-FileMD5 -file $src
                if ($VERBOSE -eq $true) {
                    Write-Host -ForegroundColor Red "                         SFH: " -NoNewLine; Write-Host $srcMD5
                }
                $destMD5 = Get-FileMD5 -file $dest
                if ($VERBOSE -eq $true) {
                    Write-Host -ForegroundColor Red "                         DFH: " -NoNewLine; Write-Host $destMD5
                }
                if ($srcMD5 -eq $destMD5) { #Check md5 hash match.
                    if ($VERBOSE -eq $true) {
                        Write-Host -ForegroundColor Yellow "                              File hashes match. File already exists in destination folder and will be skipped.`n"
                    }
                    $notUpdated += $src
                    $cpy = $false
                }
                else { #if MD5 hashes do not match, overwrite
                    $cpy = $true
                    if ($VERBOSE -eq $true) {
                        Write-Host -ForegroundColor Yellow "                              File hashes don't match. File will be copied to destination folder.`n"
                    }
                }
            } else {
                $cpy = $false
            }
        }
        else { 
            #New files
            $cpy = $true
        }
        if ($cpy -eq $true) { 
            #Copy the file if file version is newer or if it doesn't exist in the destination dir.
            if (!(test-path $dest)) {
                $created += $dest
                if ($VERBOSE -eq $true) {
                    Write-Host -ForegroundColor DarkCyan "                         DFN: " -NoNewLine; Write-Host $dest
                }
                $null = New-Item -ItemType "File" -Path $dest -Force
            }
            # Update already existing file
            if ($AUTO -eq $true) {
                if ($dest -notin $created) {
                    $updated += $src
                }
                Copy-Item -Path $src -Destination $dest -Force
            } else {
                $choice = Read-Host "Press any key to continue or [c] to cancel.`n"
                if ($choice -ne "c") {
                    if ($dest -notin $created) {
                        $updated += $src
                    }
                    Copy-Item -Path $src -Destination $dest -Force
                } else {
                    $cancelled += $src
                }
            }
        }
    }
    if ($VERBOSE -ne $false) {
        Write-Host
    }
    return $newer, $updated, $notUpdated, $created, $cancelled
}

# PUSH
function push {
    Param(
        [ValidateNotNullOrEmpty()]
        [string]$SRC_DIR=$(throw "Source directory is mandatory, please provide a value."),
        [ValidateNotNullOrEmpty()]
        [string]$DST_DIR=$(throw "Destination directory is mandatory, please provide a value."),
        $AUTO = $false,
        $VERBOSE = $true
    )
    $sourceFiles = $null
    foreach ($filter in $Filter) {
        $SourceFiles += Get-ChildItemToDepth -ToDepth 2 -Path $SRC_DIR -Filter $filter
    }
    $SourceFiles | % { # loop through the source dir files
        $src = $_.FullName #current source dir file
        $wdsrc = [datetime]$_.LastWriteTime
        if ($VERBOSE -eq $true) {
            Write-Host -ForegroundColor Yellow "SLW: " -NoNewLine; Write-Host $wdsrc -NoNewLine; Write-Host -ForegroundColor Red " SFN: " -NoNewLine; Write-Host $src
        }
        $dest = $src -replace $SRC_DIR.Replace('\','\\'),$DST_DIR
        if (test-path $dest) { #if file exists, check md5 hash
            $wddst = [datetime](Get-ItemProperty -Path $dest -Name LastWriteTime).lastwritetime
            if ($VERBOSE -eq $true) {
                Write-Host -ForegroundColor Yellow "DLW: " -NoNewLine; Write-Host $wddst -NoNewLine; Write-Host -ForegroundColor Red " DFN: " -NoNewLine; Write-Host $dest
            }
            if ((get-date $wdsrc) -gt (get-date $wddst)) {
                $newer += $src
                $srcMD5 = Get-FileMD5 -file $src
                if ($VERBOSE -eq $true) {
                    Write-Host -ForegroundColor Red "                         SFH: " -NoNewLine; Write-Host $srcMD5
                }
                $destMD5 = Get-FileMD5 -file $dest
                if ($VERBOSE -eq $true) {
                    Write-Host -ForegroundColor Red "                         DFH: " -NoNewLine; Write-Host $destMD5
                }
                if ($srcMD5 -eq $destMD5) { #Check md5 hash match.
                    if ($VERBOSE -eq $true) {
                        Write-Host -ForegroundColor Yellow "                              File hashes match. File already exists in destination folder and will be skipped.`n"
                    }
                    $notUpdated += $src
                    $cpy = $false
                }
                else { #if MD5 hashes do not match, overwrite
                    $cpy = $true
                    if ($VERBOSE -eq $true) {
                        Write-Host -ForegroundColor Yellow "                              File hashes don't match. File will be copied to destination folder.`n"
                    }
                }
            } else {
                $cpy = $false
            }
        }
        else { 
            #New files
            $cpy = $true
        }
        if ($cpy -eq $true) { 
            #Copy the file if file version is newer or if it doesn't exist in the destination dir.
            if (!(test-path $dest)) {
                $created += $dest
                if ($VERBOSE -eq $true) {
                    Write-Host -ForegroundColor DarkCyan "                         DFN: " -NoNewLine; Write-Host $dest
                }
                $null = New-Item -ItemType "File" -Path $dest -Force
            }
            # Update already existing file
            if ($AUTO -eq $true) {
                if ($dest -notin $created) {
                    $updated += $src
                }
                Copy-Item -Path $src -Destination $dest -Force
            } else {
                $choice = Read-Host "Press any key to continue or [c] to cancel.`n"
                if ($choice -ne "c") {
                    if ($dest -notin $created) {
                        $updated += $src
                    }
                    Copy-Item -Path $src -Destination $dest -Force
                } else {
                    $cancelled += $src
                }
            }
        }
    }
    if ($VERBOSE -ne $false) {
        Write-Host
    }
    return $newer, $updated, $notUpdated, $created, $cancelled
}

#CHECK INPUT
$input=$args[0]

#VARIABLES
$DebugPreference = "continue"
$newer = @()
$updated = @()
$notUpdated = @()
$created = @()
$cancelled = @()
$Filter = ('*.ear', '*.yml', 'Dockerfile', '*.properties', 'XmlUsers.xml', '*.zip', '*.sh')

#PARAMETERS
$SRC_DIR = ''
$DST_DIR = ''

if ($input -eq "pull" -Or $input -eq "push") {
    #PULL
    if ($input -eq "pull") {
        Write-Host -ForegroundColor DarkCyan "`nPULL " -NoNewLine; Write-Host -ForegroundColor Yellow "[$DST_DIR]`n"
        $newer, $updated, $notUpdated, $created, $cancelled = pull $DST_DIR $SRC_DIR
        showSummary
    } 
    #PUSH
    else {
        Write-Host -ForegroundColor DarkRed "`nPUSH " -NoNewLine; Write-Host -ForegroundColor Yellow "[$DST_DIR]`n"
        $newer, $updated, $notUpdated, $created, $cancelled = push $SRC_DIR $DST_DIR -AUTO $false
        showSummary "push"
    }
} else {
    Write-Host -ForegroundColor Red "Error: Input parameters not existing or invalid."
    $filename = $MyInvocation.MyCommand.Name
    $usageMessage = [PSCustomObject]@()
    $usageMessage += New-Object PSCustomObject -Property @{
        "Script Path" = "$PSScriptRoot\$filename"
        "Option" = "pull"
        "Description" = "Pull files from remote folder"
    }
    $usageMessage += New-Object PSObject -Property @{
        "Script Path" = "$PSScriptRoot\$filename"
        "Option" = "push"
        "Description" = "Push files to remote folder"
    }
    $usageMessage | Format-Table "Script Path", "Option", "Description" -AutoSize
}
