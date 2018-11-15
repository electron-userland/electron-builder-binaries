#!/usr/bin/env bash
set -e

# custom homebrew prefix and DYLD_FALLBACK_LIBRARY_PATH doesn't work due to unknown reasons on Travis
# homebrew bottle and DYLD_FALLBACK_LIBRARY_PATH doesn't work due to not found library on Travis
# so, we just build it without brew http://mybyways.com/blog/compiling-wine-from-scratch-on-macos-with-retina-mode
# also, we build very minimal wine (~ 15 MB compressed)

WINE_VERSION=3.0.3
LIBPNG_VERSION=1.6.35
# 2.8.1 leads to error - https://forums.gentoo.org/viewtopic-p-8119832.html
FREETYPE_VERSION=2.9.1

rm -rf /tmp/wine-stage
mkdir -p /tmp/wine-stage/wine
cd /tmp/wine-stage/wine
mkdir usr
mkdir usr/lib
mkdir usr/bin
mkdir usr/include

export TARGET=$(PWD)
export CPPFLAGS="-I$TARGET/usr/include"
export CFLAGS="-O3 -I$TARGET/usr/include"
export CXXFLAGS="$CFLAGS "
export LDFLAGS=" -L$TARGET/usr/lib"
export PATH="$TARGET/usr/bin:$PATH"
export PKG_CONFIG_PATH="$TARGET/usr/lib/pkgconfig"

cd ..

# libxml required for wix
curl -L http://xmlsoft.org/sources/libxml2-2.9.6.tar.gz | tar xz
cd libxml2-*
./configure --prefix=$TARGET/usr --without-python --without-lzma --disable-dependency-tracking
make -j9
make install
cd ..

curl -L http://ijg.org/files/jpegsrc.v9b.tar.gz | tar xz
cd jpeg-9b
./configure --prefix=$TARGET/usr
make install
cd ..

curl -L http://downloads.sourceforge.net/project/libpng/libpng16/$LIBPNG_VERSION/libpng-$LIBPNG_VERSION.tar.gz | tar xz
cd libpng-$LIBPNG_VERSION
./configure --prefix=$TARGET/usr
make install
cd ..

curl -L http://download.savannah.gnu.org/releases/freetype/freetype-$FREETYPE_VERSION.tar.gz | tar xz
cd freetype-$FREETYPE_VERSION
./configure --prefix=$TARGET/usr
make -j9
make install
cd ..

curl https://dl.winehq.org/wine/source/3.0/wine-$WINE_VERSION.tar.xz | tar xz
cd wine-$WINE_VERSION
./configure --prefix=$TARGET/usr --disable-win16 --enable-win64 --without-x
make -j9
make install

cd ../wine/usr

# prepare wine home
WINEPREFIX=/tmp/wine-stage/wine/usr/wine-home ./bin/wineboot --init

unlink bin/widl
unlink bin/wrc
unlink bin/wmc

rm -rf share/man
rm -rf share/doc
rm -rf share/gtk-doc
rm -rf include

rm -rf wine-home/drive_c/windows/Installer
rm -rf wine-home/drive_c/windows/Microsoft.NET
rm -rf wine-home/drive_c/windows/mono
rm -rf wine-home/drive_c/windows/system32/gecko
rm -rf wine-home/drive_c/windows/syswow64/gecko
rm -rf wine-home/drive_c/windows/Migration
rm -rf wine-home/drive_c/windows/logs
rm -rf wine-home/drive_c/windows/inf
rm -f wine-home/drive_c/windows/dotnet462.installed.workaround
rm -f wine-home/drive_c/windows/dd_SetupUtility.txt

PATH=./bin:$PATH WINEPREFIX=/tmp/wine-stage/wine/usr/wine-home winetricks -q dotnet462

cd wine-home/drive_c/windows/Microsoft.NET
rm NETFXRepair*

cd assembly/GAC_32
rm -rf PresentationCore
rm -rf Microsoft.VisualBasic.Activities.Compiler
rm -rf CustomMarshalers
rm -rf ISymWrapper
rm -rf Microsoft.Transactions.Bridge.Dtc
rm -rf System.*

cd ../GAC_MSIL
rm -rf System.Web.*
rm -rf Microsoft.Build*
rm -rf AspNetMMCExt
rm -rf Microsoft.JScript
rm -rf Microsoft.VisualBasic*
rm -rf UIAutomation*
rm -rf WindowsFormsIntegration
rm -rf XsdBuildTask
rm -rf XamlBuildTask
rm -rf System.Xaml*
rm -rf System.Workflow*
rm -rf System.Windows*
rm -rf System.Speech
rm -rf Microsoft.Activities.Build
rm -rf Microsoft.VisualC
rm -rf Microsoft.VisualC.STLCLR
rm -rf Microsoft.Workflow.Compiler
rm -rf PresentationBuildTasks
rm -rf PresentationFramework*
rm -rf PresentationUI
rm -rf ReachFramework
rm -rf System.Drawing*
rm -rf System.Design
rm -rf System.Deployment
rm -rf System.ServiceModel*
rm -rf System.Runtime.Serialization.Formatters.Soap
rm -rf System.Runtime.Serialization.Json
rm -rf Microsoft.Windows.ApplicationServer.Applications
rm -rf Microsoft.Transactions.Bridge
rm -rf Microsoft.Data.Entity.Build.Tasks
rm -rf Microsoft.Internal.Tasks.Dataflow
rm -rf System.Activities*
rm -rf System.ComponentModel*
rm -rf System.Data.*
rm -rf System.Linq*
rm -rf System.Net*
rm -rf System.Runtime*
rm -rf System.Reflection*
rm -rf WindowsBase
rm -rf System.Threading*
rm -rf System.ServiceProcess
rm -rf System.ObjectModel
rm -rf System.Messaging
rm -rf System.Management*
rm -rf System.IdentityModel*
rm -rf System.Dynamic*
rm -rf System.DirectoryServices*
rm -rf System.Configuration*
rm -rf System.AddIn*
rm -rf System.Xml.Linq
rm -rf System.Diagnostics*
rm -rf System.Device
rm -rf System.Numerics*

cd Framework
unlink NETFXSBS10.exe
cd v4.0.*
rm -rf WPF
rm *.exe
rm *.exe.config

rm System.Web.*
rm Microsoft.VisualBasic.*
rm -rf MSBuild
rm ngen.*
rm Microsoft.Build.*
rm -rf ASP.NETWebAdminFiles
rm aspnet_*
rm Aspnet_*
rm aspnet.*
rm Aspnet.*
unlink AspNetMMCExt.dll
unlink AdoNetDiag.dll
rm adonetdiag*
unlink CLR-ETW.man
rm System.ServiceModel*
unlink System.Design.dll
unlink System.Windows.Forms.dll
unlink System.Data.Entity.dll
unlink System.Activities.Presentation.dll
unlink System.Windows.Forms.DataVisualization.dll
unlink System.Workflow.ComponentModel.dll
unlink System.Data.Entity.Design.dll
unlink System.IdentityModel.dll
unlink System.Workflow.Activities.dll
unlink System.Deployment.dll
unlink Microsoft.JScript.dll
unlink System.Activities.dll
unlink System.Activities.Core.Presentation.dll
unlink System.Data.Linq.dll
unlink System.Data.Linq.dll
unlink System.Data.Services.dll
unlink System.Drawing.dll
unlink webengine4.dll
unlink System.Data.OracleClient.dll
unlink System.Workflow.Runtime.dll
unlink System.WorkflowServices.dll
unlink System.Data.Services.Client.dll
unlink System.Data.Services.Design.dll
unlink diasymreader.dll
unlink System.Data.SqlXml.dll
unlink System.Xaml.dll
unlink Microsoft.Windows.ApplicationServer.Applications.45.man
unlink System.Runtime.Serialization.dll
unlink System.EnterpriseServices.dll
unlink System.Data.dll
unlink Microsoft.Transactions.Bridge.dll
unlink System.Runtime.Remoting.dll
unlink _ServiceModelEndpointPerfCounters.ini
unlink System.Transactions.dll
unlink System.Messaging.dll
unlink Microsoft.Common.targets
unlink System.Net.dll
unlink System.DirectoryServices.Protocols.dll
unlink System.Net.Http.dll
unlink System.IdentityModel.Services.dll
unlink FileTracker.dll
unlink PerfCounter.dll
unlink peverify.dll
unlink Microsoft.Internal.Tasks.Dataflow.dll
unlink System.Runtime.DurableInstancing.dll
unlink _Networkingperfcounters.ini
unlink System.Xml.Linq.dll
unlink dfdll.dll
unlink System.ServiceModel.Channels.dll
unlink PerfCounters.ini
unlink System.Management.Instrumentation.dll
unlink mscorpehost.dll
unlink System.IdentityModel.Selectors.dll
unlink System.Activities.DurableInstancing.dll
unlink System.Runtime.Serialization.Formatters.Soap.dll
unlink Microsoft.Windows.ApplicationServer.Applications.dll
unlink clretwrc.dll
unlink System.ServiceModel.Internals.dll
unlink _ServiceModelOperationPerfCounters.ini
unlink System.AddIn.dll
unlink System.Numerics.dll
unlink _TransactionBridgePerfCounters.ini
unlink System.ServiceProcess.dll
unlink _SMSvcHostPerfCounters.ini
unlink XamlBuildTask.dll
unlink ServiceModelPerformanceCounters.dll
unlink corperfmonsymbols.ini
unlink mscordacwks.dll
unlink SOS.dll
unlink _ServiceModelServicePerfCounters.ini
unlink EventLogMessages.dll
unlink System.Management.dll
unlink System.configuration.dll
unlink System.ComponentModel.Composition.dll
unlink System.DirectoryServices.AccountManagement.dll
unlink Microsoft.Transactions.Bridge.Dtc.dll
unlink System.ServiceModel.Routing.dll
unlink System.Dynamic.dll
unlink ServiceModelPerformanceCounters.man
unlink CORPerfMonExt.dll
unlink dv_aspnetmmc.chm
unlink System.Drawing.Design.dll
unlink TLBREF.DLL
unlink System.EnterpriseServices.Wrapper.dll
unlink MmcAspExt.dll
unlink System.EnterpriseServices.Thunk.dll
unlink _dataperfcounters_shared12_neutral.ini
unlink CustomMarshalers.dll
unlink fusion.dll
unlink mscorpe.dll
unlink System.Windows.Forms.tlb
unlink System.Windows.Forms.DataVisualization.Design.dll
unlink System.Data.DataSetExtensions.dll
unlink ISymWrapper.dll
unlink XsdBuildTask.dll
unlink _DataOracleClientPerfCounters_shared12_neutral.ini
unlink alink.dll
unlink Microsoft.CSharp.dll
unlink System.DirectoryServices.dll
unlink WorkflowServiceHostPerformanceCounters.dll
unlink Microsoft.JScript.tlb
unlink _Networkingperfcounters_v2.ini
unlink Microsoft.Data.Entity.Build.Tasks.dll
unlink System.AddIn.Contract.dll
unlink System.Net.Http.WebRequest.dll
unlink Microsoft.VisualC.STLCLR.dll
unlink _DataPerfCounters.ini
unlink Microsoft.Activities.Build.dll
unlink System.XML.dll
unlink System.ComponentModel.DataAnnotations.dll
unlink Microsoft.Xaml.targets
unlink MSBuild.rsp
unlink XPThemes.manifest
unlink Microsoft.Data.Entity.targets
unlink Microsoft.Common.OverrideTasks
unlink ngen_service.old.log
unlink System.Drawing.tlb
unlink Workflow.VisualBasic.Targets
unlink System.Configuration.Install.dll
unlink System.Runtime.Caching.dll
unlink System.Diagnostics.Tracing.dll
unlink System.ServiceModel.Http.dll
rm System.Threading.*
unlink System.Collections.Concurrent.dll
unlink System.Xaml.Hosting.dll
unlink System.Resources.ResourceManager.dll
unlink System.ObjectModel.dll
rm System.Reflection.*
rm System.Runtime.*
rm *.sql
rm *.SQL
rm -rf "Temporary ASP.NET Files"
rm -rf SQL
rm -rf MUI
rm -rf MOF
rm -rf Config
rm *.h

rm -rf "1033"