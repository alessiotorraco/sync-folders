# MIT LICENSE @ ALESSIO TORRACO 2021

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
            #Else {
            #    Write-Debug $("Skipping GCI for Folder: $($_.FullName) " + `
            #      "(Why: Current depth $CurrentDepth vs limit depth $ToDepth)")
            #}
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

# One-way sync files (SRC <- DST)
# PULL
function pull {
    Param(
        [ValidateNotNullOrEmpty()]
        [string]$SRC_DIR=$(throw "Source directory is mandatory, please provide a value."),
        [ValidateNotNullOrEmpty()]
        [string]$DST_DIR=$(throw "Destination directory is mandatory, please provide a value."),
        $AUTO = $true,
        $VERBOSE = $false,
        $SKIP_EAR = $true
    )
    $sourceFiles = $null
    foreach ($filter in $Filter) {
        $SourceFiles += Get-ChildItemToDepth -ToDepth 2 -Path $SRC_DIR -Filter $filter
    }
    $SourceFiles | % { # loop through the source dir files
        $src = $_.FullName #current source dir file
        $wdsrc = [datetime]$_.LastWriteTime
        $extn = [IO.Path]::GetExtension($src)
        if ($extn -eq ".ear" -And $SKIP_EAR -eq $true)
        {
            # Skip *.ear files
        } else {
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
                #Write-Debug "File doesn't exist in destination folder and will be copied."
                $cpy = $true
            }
            #Write-Debug "Copy is $cpy"
            if ($cpy -eq $true) { #Copy the file if file version is newer or if it doesn't exist in the destination dir.
                #Write-Debug "Copying $src to $dest"
                if (!(test-path $dest)) {
                    $created += $dest
                    if ($VERBOSE -eq $true) {
                        Write-Host -ForegroundColor DarkCyan "                         DFN: " -NoNewLine; Write-Host $dest
                    }
                    $null = New-Item -ItemType "File" -Path $dest -Force
                }
            # update already existing file
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
            #Write-Debug "File doesn't exist in destination folder and will be copied."
            $cpy = $true
        }
        #Write-Debug "Copy is $cpy"
        if ($cpy -eq $true) { #Copy the file if file version is newer or if it doesn't exist in the destination dir.
            #Write-Debug "Copying $src to $dest"
            if (!(test-path $dest)) {
                $created += $dest
                if ($VERBOSE -eq $true) {
                    Write-Host -ForegroundColor DarkCyan "                         DFN: " -NoNewLine; Write-Host $dest
                }
                $null = New-Item -ItemType "File" -Path $dest -Force
            }
            # update already existing file
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

function moveToHistoryFolder {
    Param(
        [ValidateNotNullOrEmpty()]
        [string]$SRC_DIR=$(throw "Source directory is mandatory, please provide a value.")
    )
    $moved = @()
    $SourceFiles = $null
    $SourceFiles = Get-ChildItemToDepth -ToDepth 2 -Path $SRC_DIR -Filter "*.ear"
    $latest = $null
    #Write-Host "LATEST: $latest"
    $SourceFiles | % { # loop through the source dir files
        $src = $_.FullName #current source dir file
        $srcDir = [System.IO.Path]::GetDirectoryName($src)
        $latest = (Get-ChildItem -Path $srcDir -Filter *.ear | sort LastWriteTime | Select -Last 1).FullName
        #Write-Host $srcDir
        #Write-Host $latest
        if ($src -eq $latest) {
            #Write-Host "$src EQ $latest"
        } else {
            $destName = $_.Name
            $dest = $srcDir+"\Stable\"
            #Write-Host "Move-Item -Path $src -Destination $dest -Force"
            if (!(test-path $dest)) {
                $null = New-Item -ItemType Directory -Path $dest -Force
            }
            $dest += $destName
            Move-Item -Path $src -Destination $dest -Force
            $moved += $dest
            Write-Host -ForegroundColor Red "Moved $dest"
        }
    }
    if ($moved.count -gt 0) {
        Write-Host -ForegroundColor Cyan "Moved file(s):"
        foreach ($item in $moved) {
            Write-Host $item
        }
        Write-Host
    }
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
        $newer, $updated, $notUpdated, $created, $cancelled = push $SRC_DIR $DST_DIR -VERBOSE $false
        showSummary "push"
        # Move older *.ear files to history folder except for latest one
        moveToHistoryFolder $DST_DIR
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
