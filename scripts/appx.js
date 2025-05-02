const path = require("path")
const promisify = require("util").promisify
const fs = require("fs")
const copy = promisify(fs.copyFile)

const VERSION = "10.0.26100.0"

const windowsKitsDir = "C:\\Program Files (x86)\\Windows Kits\\10"
const sourceDir = path.resolve(windowsKitsDir, "bin", VERSION)
const destination = path.join(__dirname, "../out/winCodeSign/windows-10")

// noinspection SpellCheckingInspection
const files = [
  "appxpackaging.dll",
  "makeappx.exe",
  "makecert.exe",

  "makecat.exe",
  "makecat.exe.manifest",

  "Microsoft.Windows.Build.Signing.mssign32.dll.manifest",
  "mssign32.dll",

  "Microsoft.Windows.Build.Appx.AppxSip.dll.manifest",
  "appxsip.dll",

  "Microsoft.Windows.Build.Signing.wintrust.dll.manifest",
  "wintrust.dll",

  "makepri.exe",
  "Microsoft.Windows.Build.Appx.AppxPackaging.dll.manifest",
  "Microsoft.Windows.Build.Appx.OpcServices.dll.manifest",
  "opcservices.dll",
  "signtool.exe",
  "signtool.exe.manifest",
  "pvk2pfx.exe"
]

function copyFiles(files, archWin, archNode) {
  fs.mkdirSync(path.join(destination, archNode), { recursive: true })
  return files.map(async file => {
    await copy(path.join(sourceDir, archWin, file), path.join(destination, archNode, file))
    return file
  })
}

// copy files
Promise.all([
  ...copyFiles(files, "x86", "ia32"),
  ...copyFiles(files, "x64", "x64"),
  ...copyFiles(files, "arm64", "arm64"),
])
.then(files => {
  console.log("Files copied successfully")
  console.log("Files copied:")
  files.forEach(file => {
    console.log(`- ${file}`)
  })
})
.catch(error => {
  process.exitCode = 1
  console.error(error)
})

// add version file
fs.writeFileSync(
  path.join(destination, "VERSION"),
  VERSION,
  "utf8"
)