Option Explicit
Dim shell, fso, root, bat
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
root = fso.GetParentFolderName(WScript.ScriptFullName)
bat = Chr(34) & fso.BuildPath(root, "启动白板工坊.bat") & Chr(34)
shell.CurrentDirectory = root
shell.Run bat, 0, False
