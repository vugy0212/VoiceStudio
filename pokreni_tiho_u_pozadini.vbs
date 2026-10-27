Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
currentDir = fso.GetParentFolderName(WScript.ScriptFullName)

' Pokreni bun scripts/on-demand-gateway.mjs u potpunosti sakriveno (0 = sakriven prozor)
WshShell.CurrentDirectory = currentDir
WshShell.Run "cmd.exe /c bun scripts/on-demand-gateway.mjs", 0, False
