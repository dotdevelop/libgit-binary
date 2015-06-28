<#
.SYNOPSIS
    Builds a version of libgit2 and copies it to the nuget packaging directory.
.PARAMETER vs
    Version of Visual Studio project files to generate. Cmake supports "10", "11" and "12" (default).
#>

Param(
    [string]$vs = '12'
)

Set-StrictMode -Version Latest

$projectDirectory = Split-Path $MyInvocation.MyCommand.Path
$libgit2Directory = Join-Path $projectDirectory "external\libgit2"
$x86Directory = Join-Path $projectDirectory "windows"
#$x64Directory = Join-Path $projectDirectory "windows64"
$hashFile = Join-Path $projectDirectory "libgit2_hash.txt"
$sha = Get-Content $hashFile 
$binaryFilename = "git2-" + $sha.Substring(0,7)
$configuration = "RelWithDebInfo"

function Run-Command([scriptblock]$Command, [switch]$Fatal, [switch]$Quiet) {
    $output = ""
    if ($Quiet) {
        $output = & $Command 2>&1
    } else {
        & $Command
    }

    if (!$Fatal) {
        return
    }

    $exitCode = 0
    if ($LastExitCode -ne 0) {
        $exitCode = $LastExitCode
    } elseif (!$?) {
        $exitCode = 1
    } else {
        return
    }

    $error = "``$Command`` failed"
    if ($output) {
        Write-Host -ForegroundColor yellow $output
        $error += ". See output above."
    }
    Throw $error
}

function Find-CMake {
    # Look for cmake.exe in $Env:PATH.
    $cmake = @(Get-Command cmake.exe)[0] 2>$null
    if ($cmake) {
        $cmake = $cmake.Definition
    } else {
        # Look for the highest-versioned cmake.exe in its default location.
        $cmake = @(Resolve-Path (Join-Path ${Env:ProgramFiles(x86)} "CMake *\bin\cmake.exe"))
        if ($cmake) {
            $cmake = $cmake[-1].Path
        }
    }
    if (!$cmake) {
        throw "Error: Can't find cmake.exe"
    }
    $cmake
}

function Ensure-Property($expected, $propertyValue, $propertyName, $path) {
    if ($propertyValue -eq $expected) {
        return
    }

    throw "Error: Invalid '$propertyName' property in generated '$path' (Expected: $expected - Actual: $propertyValue)"
}

function Assert-Consistent-Naming($expected, $path) {
    $dll = get-item $path

    Ensure-Property $expected $dll.Name "Name" $dll.Fullname
    Ensure-Property $expected $dll.VersionInfo.InternalName "VersionInfo.InternalName" $dll.Fullname
    Ensure-Property $expected $dll.VersionInfo.OriginalFilename "VersionInfo.OriginalFilename" $dll.Fullname
}

if (Test-Path(Join-Path $x86Directory "$binaryFilename.dll")) {
    Write-Output "Binaries don't need rebuilding!"
    Exit
}

try {
    Push-Location $libgit2Directory

    $cmake = Find-CMake

    Write-Output "Building 32-bit..."
    Run-Command { & remove-item build -recurse -force }
    Run-Command { & mkdir build }
    cd build
    Run-Command -Fatal { & $cmake -G "Visual Studio $vs" -D ENABLE_TRACE=ON -D "LIBGIT2_FILENAME=$binaryFilename" -DSTDCALL=ON -D "EMBED_SSH_PATH=../libssh2" -DBUILD_CLAR:BOOL=OFF \ .. }
    Run-Command -Fatal { & $cmake --build . --config $configuration }
    cd $configuration
    Assert-Consistent-Naming "$binaryFilename.dll" "*.dll"

    Pop-Location

    Run-Command { & rm "$libgit2Directory\build\$configuration\*.exp" }
    if (Test-Path "$x86Directory\*") {
        Run-Command { & git rm "$x86Directory\*" }
    }
    Run-Command { & mkdir -fo "$x86Directory" }
    Run-Command { & copy -fo "$libgit2Directory\build\$configuration\*" -Destination $x86Directory -Exclude *.lib }
    Run-Command { & git add "$x86Directory" }

    #Write-Output "Building 64-bit..."
    #cd ..
    #Run-Command { & mkdir build64 }
    #cd build64
    #Run-Command -Fatal { & $cmake -G "Visual Studio $vs Win64" -D THREADSAFE=ON -D ENABLE_TRACE=ON -D "LIBGIT2_FILENAME=$binaryFilename" -DSTDCALL=ON ../.. }
    #Run-Command -Fatal { & $cmake --build . --config $configuration }
    #cd $configuration
    #Assert-Consistent-Naming "$binaryFilename.dll" "*.dll"
    #Run-Command { & rm *.exp }
    #Run-Command { & rm $x64Directory\* }
    #Run-Command { & mkdir -fo $x64Directory }
    #Run-Command -Fatal { & copy -fo * $x64Directory -Exclude *.lib }

    Write-Output "Done!"
}
finally {
    Pop-Location
}
